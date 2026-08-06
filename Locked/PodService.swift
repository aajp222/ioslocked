import Foundation

/// Everything that needs other humans goes through here.
///
/// `RemotePodService` talks to `server/locked_server.py` — that's the real one.
/// `OfflinePodService` stands in before you've signed in or when the server is
/// unreachable, and it fabricates nothing: no pod, no verdicts, no activity.
/// `AppState.connect(_:)` swaps them at runtime.
protocol PodService: AnyObject {
    /// True when a real pod is on the other end.
    var isRemote: Bool { get }

    /// Ask the pod to let me out. Returns whatever they decided (or `.expired`).
    func send(_ request: UnlockRequest, pod: [PodMember]) async -> Verdict

    /// Anything waiting for *me* to answer.
    func pollIncoming(pod: [PodMember], mySeed: UInt64) async -> UnlockRequest?

    /// Tell the pod I started / finished / folded, so it lands in their feed.
    func publish(_ event: FeedEvent) async

    /// My verdict on somebody else's request.
    func answer(_ request: UnlockRequest, approve: Bool, quip: String) async

    /// Same, but by server id — a notification action can arrive with the app
    /// freshly launched and no local copy of the request.
    func answer(requestID: String, approve: Bool, quip: String) async

    /// Hand APNs this device so the pod can reach us with the app closed.
    func registerDevice(token: String, environment: String) async

    /// Publish live status — who's locked, on what, until when. Hours are *not*
    /// sent: the server derives those from the session records below.
    func pushState(session: Session?, tzOffsetMinutes: Int) async

    /// Open a session record the server owns. This is what hours are counted from.
    /// Returns false if the server didn't take it, so the app can retry later.
    @discardableResult
    func openSession(_ session: Session, tzOffsetMinutes: Int) async -> Bool

    /// Close it out — completed or caved, with the seconds actually served.
    @discardableResult
    func closeSession(id: UUID, outcome: String, servedSeconds: Int) async -> Bool

    /// The pod as the server sees it.
    func fetchPod() async -> RemotePod?

    /// Feed events since a cursor.
    func fetchFeed(since cursor: Int) async -> (events: [FeedEvent], cursor: Int)?

    /// Step out of the pod, but keep the account.
    func leavePod() async

    /// Remove somebody else — pod owner only, enforced server-side.
    func kick(memberID: String) async

    /// Delete the account and everything attached to it.
    func deleteAccount() async
}

/// Local-only services don't need to implement the syncing half.
extension PodService {
    var isRemote: Bool { false }
    func answer(_ request: UnlockRequest, approve: Bool, quip: String) async {}
    func answer(requestID: String, approve: Bool, quip: String) async {}
    func registerDevice(token: String, environment: String) async {}
    func pushState(session: Session?, tzOffsetMinutes: Int) async {}
    func openSession(_ session: Session, tzOffsetMinutes: Int) async -> Bool { false }
    func closeSession(id: UUID, outcome: String, servedSeconds: Int) async -> Bool { false }
    func fetchPod() async -> RemotePod? { nil }
    func fetchFeed(since cursor: Int) async -> (events: [FeedEvent], cursor: Int)? { nil }
    func leavePod() async {}
    func kick(memberID: String) async {}
    func deleteAccount() async {}
}

struct RemotePod {
    var name: String
    var inviteCode: String
    /// Everyone except me.
    var members: [PodMember]
    var me: PodMember?
    /// My own totals, as the server derived them from my session records.
    var myTodaySeconds: Int?
    var myCavesThisWeek: Int?
    var iOwnIt: Bool = false
}

// MARK: - Offline (no pod yet)

/// What runs before you've signed in, or when the server can't be reached.
///
/// It invents nothing. There used to be a `SimulatedPodService` here that played
/// four friends convincingly — that made the app demo well and lie to you. An
/// accountability app whose pod is imaginary has no product in it.
final class OfflinePodService: PodService {
    var isRemote: Bool { false }

    func send(_ request: UnlockRequest, pod: [PodMember]) async -> Verdict {
        // Nobody to ask.
        .expired
    }

    func pollIncoming(pod: [PodMember], mySeed: UInt64) async -> UnlockRequest? { nil }

    func publish(_ event: FeedEvent) async {}
}

// MARK: - Simulated (dev mode only)

/// Four actors who behave like a pod: a 2.6s deliberation, then a verdict using
/// the prototype's rule — a genuine-sounding reason gets you five minutes,
/// everything else gets you laughed at. Also invents the occasional incoming
/// request so the judge's side can be demonstrated.
///
/// Only ever used when dev mode is switched on in Settings. `isRemote` stays
/// false, so nothing it produces is ever published to a real server.
final class SimulatedPodService: PodService {
    func send(_ request: UnlockRequest, pod: [PodMember]) async -> Verdict {
        try? await Task.sleep(nanoseconds: 2_600_000_000)

        let responders = pod.isEmpty ? PodMember.demoCast : pod
        let reason = request.reason.lowercased()

        // Softest member grants; the strictest denies.
        let granter = responders.min(by: { $0.streak < $1.streak }) ?? responders[0]
        let denier = responders.max(by: { $0.streak < $1.streak }) ?? responders[0]

        let approves: Bool
        if reason.contains("mom") || reason.contains("call") {
            approves = true
        } else if reason.contains("food") || reason.contains("order") {
            approves = Int.random(in: 0..<10) < 3
        } else if request.remainingAtRequest < 5 * 60 {
            approves = Int.random(in: 0..<10) < 5
        } else {
            approves = false
        }

        return approves
            ? .approved(by: granter.name, minutes: 5)
            : .denied(by: denier.name, quip: Copy.denials.randomElement() ?? Copy.denials[0])
    }

    func pollIncoming(pod: [PodMember], mySeed: UInt64) async -> UnlockRequest? {
        let candidates = pod.filter { $0.status.isLocked }
        guard let asker = candidates.randomElement(),
              case .locked(let goal, let endsAt) = asker.status
        else { return nil }

        return UnlockRequest(
            requesterName: asker.name,
            requesterInitials: asker.initials,
            isOutgoing: false,
            reason: Copy.reasons.randomElement() ?? Copy.reasons[0],
            goal: goal,
            remainingAtRequest: max(60, Int(endsAt.timeIntervalSinceNow)),
            streak: asker.streak,
            cavesThisWeek: Int.random(in: 0...3)
        )
    }

    func publish(_ event: FeedEvent) async {}
}

// MARK: - Remote

struct BackendError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

/// Talks to `server/locked_server.py`. See that file for the wire format.
final class RemotePodService: PodService {
    let config: ServerConfig
    private let http: URLSession

    var isRemote: Bool { true }

    init(config: ServerConfig) {
        self.config = config
        let settings = URLSessionConfiguration.ephemeral
        settings.timeoutIntervalForRequest = 12
        settings.waitsForConnectivity = false
        self.http = URLSession(configuration: settings)
    }

    // MARK: Requests

    func send(_ request: UnlockRequest, pod: [PodMember]) async -> Verdict {
        // The local UUID is the server's id too, so no mapping is needed.
        let body: [String: Any] = [
            "id": request.id.uuidString,
            "reason": request.reason,
            "goal": request.goal,
            "remaining": request.remainingAtRequest,
            "streak": request.streak,
            "caves": request.cavesThisWeek,
            "lifetime": request.lifetime,
        ]
        guard (try? await call("requests", method: "POST", json: body)) != nil else { return .expired }

        // Poll until the request's own deadline passes.
        while Date() < request.expiresAt {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let data = try? await call("requests/\(request.id.uuidString)"),
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let verdict = payload["verdict"] as? [String: Any] {
                return Self.decodeVerdict(verdict)
            }
        }
        return .expired
    }

    func pollIncoming(pod: [PodMember], mySeed: UInt64) async -> UnlockRequest? {
        guard let data = try? await call("requests/incoming"), !data.isEmpty,
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let created = Self.date(row["created_at"]) ?? Date()
        return UnlockRequest(
            remoteID: row["id"] as? String,
            requesterName: row["requester_name"] as? String ?? "Someone",
            requesterInitials: row["requester_initials"] as? String ?? "??",
            isOutgoing: false,
            reason: row["reason"] as? String ?? "No reason given",
            goal: row["goal"] as? String ?? "Work",
            remainingAtRequest: row["remaining"] as? Int ?? 0,
            streak: row["streak"] as? Int ?? 0,
            cavesThisWeek: row["caves"] as? Int ?? 0,
            createdAt: created,
            lifetime: row["lifetime"] as? Double ?? 60
        )
    }

    func answer(_ request: UnlockRequest, approve: Bool, quip: String) async {
        await answer(
            requestID: request.remoteID ?? request.id.uuidString,
            approve: approve,
            quip: quip
        )
    }

    func answer(requestID: String, approve: Bool, quip: String) async {
        _ = try? await call(
            "requests/\(requestID)/verdict",
            method: "POST",
            json: ["approve": approve, "minutes": 5, "quip": quip]
        )
    }

    func leavePod() async {
        _ = try? await call("pods/leave", method: "POST", json: [:])
    }

    func kick(memberID: String) async {
        _ = try? await call("pods/members/\(memberID)/kick", method: "POST", json: [:])
    }

    func deleteAccount() async {
        _ = try? await call("me", method: "DELETE")
    }

    func registerDevice(token: String, environment: String) async {
        _ = try? await call(
            "devices",
            method: "POST",
            json: ["token": token, "environment": environment]
        )
    }

    // MARK: Feed and state

    func publish(_ event: FeedEvent) async {
        guard let encoded = try? JSONEncoder.iso.encode(event),
              let payload = try? JSONSerialization.jsonObject(with: encoded)
        else { return }
        _ = try? await call("events", method: "POST", json: ["payload": payload])
    }

    func pushState(session: Session?, tzOffsetMinutes: Int) async {
        var body: [String: Any] = ["tz_offset_minutes": tzOffsetMinutes]
        if let session, session.outcome == .running {
            body["status"] = "locked"
            body["goal"] = session.goal
            body["ends_at"] = Self.iso.string(from: session.endsAt)
            body["detail"] = session.plannedMinutes
        } else {
            body["status"] = "idle"
        }
        _ = try? await call("me/state", method: "PUT", json: body)
    }

    func openSession(_ session: Session, tzOffsetMinutes: Int) async -> Bool {
        (try? await call("sessions", method: "POST", json: [
            "id": session.id.uuidString,
            "goal": session.goal,
            "planned_minutes": session.plannedMinutes,
            "started_at": Self.iso.string(from: session.startedAt),
            "ends_at": Self.iso.string(from: session.endsAt),
            "tz_offset_minutes": tzOffsetMinutes,
        ])) != nil
    }

    func closeSession(id: UUID, outcome: String, servedSeconds: Int) async -> Bool {
        (try? await call("sessions/\(id.uuidString)/close", method: "POST", json: [
            "outcome": outcome,
            "served_seconds": servedSeconds,
        ])) != nil
    }

    private static let iso = ISO8601DateFormatter()

    func fetchPod() async -> RemotePod? {
        guard let data = try? await call("pod"),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = payload["members"] as? [[String: Any]]
        else { return nil }

        var others: [PodMember] = []
        var me: PodMember?
        var myToday: Int?
        var myCaves: Int?

        for row in rows {
            let member = Self.decodeMember(row)
            if row["is_me"] as? Bool == true {
                me = member
                myToday = row["today_seconds"] as? Int
                myCaves = row["caves_this_week"] as? Int
            } else {
                others.append(member)
            }
        }

        return RemotePod(
            name: payload["name"] as? String ?? "The pod",
            inviteCode: payload["invite_code"] as? String ?? "",
            members: others,
            me: me,
            myTodaySeconds: myToday,
            myCavesThisWeek: myCaves,
            iOwnIt: payload["i_own_it"] as? Bool ?? false
        )
    }

    func fetchFeed(since cursor: Int) async -> (events: [FeedEvent], cursor: Int)? {
        guard let data = try? await call("events?since=\(cursor)"),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = payload["events"] as? [[String: Any]]
        else { return nil }

        var events: [FeedEvent] = []
        for row in rows {
            guard let raw = row["payload"],
                  let blob = try? JSONSerialization.data(withJSONObject: raw),
                  var event = try? JSONDecoder.iso.decode(FeedEvent.self, from: blob)
            else { continue }
            // Trust the server on authorship, not the payload.
            event.isMe = row["is_me"] as? Bool ?? false
            if let name = row["author_name"] as? String { event.authorName = name }
            if let initials = row["author_initials"] as? String { event.authorInitials = initials }
            events.append(event)
        }
        return (events, payload["cursor"] as? Int ?? cursor)
    }

    // MARK: Wire

    @discardableResult
    private func call(_ path: String, method: String = "GET", json: [String: Any]? = nil) async throws -> Data {
        try await Backend.call(config.baseURL, path, method: method, json: json, token: config.token, session: http)
    }

    static func decodeVerdict(_ payload: [String: Any]) -> Verdict {
        let by = payload["by"] as? String ?? "Someone"
        switch payload["kind"] as? String {
        case "approved":
            return .approved(by: by, minutes: payload["minutes"] as? Int ?? 5)
        case "denied":
            return .denied(by: by, quip: payload["quip"] as? String ?? "no.")
        default:
            return .expired
        }
    }

    static func decodeMember(_ row: [String: Any]) -> PodMember {
        let name = row["name"] as? String ?? "Someone"
        let status: MemberStatus
        switch row["status"] as? String {
        case "locked":
            let endsAt = date(row["ends_at"]) ?? Date()
            status = endsAt > Date()
                ? .locked(goal: row["goal"] as? String ?? "something", endsAt: endsAt)
                : .idle
        case "caved":
            status = .caved(minutesIn: row["detail"] as? Int ?? 0, at: date(row["updated_at"]) ?? Date())
        case "finished":
            status = .finished(seconds: (row["detail"] as? Int ?? 0) * 60, at: date(row["updated_at"]) ?? Date())
        default:
            status = .idle
        }

        return PodMember(
            remoteID: row["id"] as? String,
            name: name,
            initials: row["initials"] as? String ?? AppState.initials(for: name),
            note: "In your pod",
            inPod: true,
            weeklySeconds: row["weekly_seconds"] as? Int ?? 0,
            streak: row["streak"] as? Int ?? 0,
            status: status
        )
    }

    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let iso = ISO8601DateFormatter()
        if let parsed = iso.date(from: text) { return parsed }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: text)
    }
}

// MARK: - Server config

/// Where the pod lives, and who I am to it. Stored in the app group.
struct ServerConfig: Codable, Equatable {
    var baseURL: String
    var token: String
    var userID: String
    var name: String
    var podName: String?
    var inviteCode: String?

    var isInPod: Bool { podName != nil }

    static let key = "locked.server.config"

    static func load() -> ServerConfig? {
        guard let data = LockedShared.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ServerConfig.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        LockedShared.defaults.set(data, forKey: Self.key)
    }

    static func clear() {
        LockedShared.defaults.removeObject(forKey: key)
    }
}

// MARK: - Pairing

/// The handful of calls that happen before there's a service to talk through:
/// health check, register, create a pod, join a pod.
enum Backend {
    static func normalize(_ url: String) -> String {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return text }
        if !text.contains("://") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    static func health(_ baseURL: String) async -> Bool {
        (try? await call(normalize(baseURL), "health")) != nil
    }

    /// Trade Apple's signed identity token for our own session token.
    ///
    /// Apple hands over the person's name **only on the first authorization ever**,
    /// so it goes up in this same call or it's gone for good. If the account is
    /// already in a pod (they signed in on another device, or reinstalled), the
    /// server tells us and we can go straight to connected.
    static func signInWithApple(
        baseURL: String,
        identityToken: String,
        fullName: String?,
        tzOffsetMinutes: Int
    ) async throws -> ServerConfig {
        let base = normalize(baseURL)
        var body: [String: Any] = [
            "identity_token": identityToken,
            "tz_offset_minutes": tzOffsetMinutes,
        ]
        if let fullName, !fullName.isEmpty { body["full_name"] = fullName }

        let data = try await call(base, "auth/apple", method: "POST", json: body)
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = payload["token"] as? String,
              let userID = payload["user_id"] as? String
        else { throw BackendError(message: "The server's reply made no sense.") }

        var config = ServerConfig(
            baseURL: base,
            token: token,
            userID: userID,
            name: payload["name"] as? String ?? fullName ?? "You"
        )
        if let pod = payload["pod"] as? [String: Any] {
            config.podName = pod["name"] as? String
            config.inviteCode = pod["invite_code"] as? String
        }
        config.save()
        return config
    }

    static func register(baseURL: String, name: String) async throws -> ServerConfig {
        let base = normalize(baseURL)
        let data = try await call(base, "register", method: "POST", json: ["name": name])
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = payload["token"] as? String,
              let userID = payload["user_id"] as? String
        else { throw BackendError(message: "The server's reply made no sense.") }

        let config = ServerConfig(baseURL: base, token: token, userID: userID, name: name)
        config.save()
        return config
    }

    static func createPod(_ config: ServerConfig, name: String) async throws -> ServerConfig {
        let data = try await call(config.baseURL, "pods", method: "POST", json: ["name": name], token: config.token)
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackendError(message: "The server's reply made no sense.")
        }
        var updated = config
        updated.podName = payload["name"] as? String ?? name
        updated.inviteCode = payload["invite_code"] as? String
        updated.save()
        return updated
    }

    static func joinPod(_ config: ServerConfig, code: String) async throws -> ServerConfig {
        let cleaned = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let data = try await call(
            config.baseURL, "pods/join", method: "POST",
            json: ["invite_code": cleaned], token: config.token
        )
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BackendError(message: "The server's reply made no sense.")
        }
        var updated = config
        updated.podName = payload["name"] as? String
        updated.inviteCode = payload["invite_code"] as? String ?? cleaned
        updated.save()
        return updated
    }

    /// Connection failures are nearly always one of two mistakes, so say so.
    static func unreachable(_ baseURL: String, _ error: Error) -> String {
        if baseURL.contains("localhost") || baseURL.contains("127.0.0.1") {
            #if !targetEnvironment(simulator)
            return "Can't reach \(baseURL). On a phone, localhost means the phone itself — use your Mac's address on the same Wi-Fi (something like http://10.0.0.80:8787) or a tunnel URL."
            #endif
        }
        return "Can't reach \(baseURL) — \(error.localizedDescription). Is the server running?"
    }

    @discardableResult
    static func call(
        _ baseURL: String,
        _ path: String,
        method: String = "GET",
        json: [String: Any]? = nil,
        token: String? = nil,
        session: URLSession = .shared
    ) async throws -> Data {
        guard let url = URL(string: "\(baseURL)/v1/\(path)") else {
            throw BackendError(message: "“\(baseURL)” isn't a usable address.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json { request.httpBody = try? JSONSerialization.data(withJSONObject: json) }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw BackendError(message: Backend.unreachable(baseURL, error))
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw BackendError(message: detail ?? "Server said \(status).")
        }
        return data
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

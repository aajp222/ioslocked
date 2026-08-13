import SwiftUI

enum Route: Hashable { case today, pod, standings }

/// The state machine behind "beg the pod for 5 minutes".
enum OutgoingPhase: Equatable {
    case none
    case composing
    case pending(reason: String)
    case verdict(Verdict)
}

struct Standing: Identifiable {
    var id: String { name }
    var name: String
    var seconds: Int
    var isMe: Bool
    var rank: Int
}

@MainActor
final class AppState: ObservableObject {
    @Published var data: AppData
    /// Ticks every second so every clock in the app stays honest.
    @Published var now = Date()
    @Published var route: Route = .today

    // Transient UI state
    @Published var outgoing: OutgoingPhase = .none
    @Published var showCaveSheet = false
    @Published var incoming: UnlockRequest? = nil
    @Published var incomingVerdict: Verdict? = nil
    @Published var completed: Session? = nil
    @Published var showSettings = false

    /// The Lock Screen / Dynamic Island countdown.
    let live = LiveActivityController()

    // Server, when there is one.
    @Published var remote: ServerConfig?
    @Published var syncError: String?
    @Published var lastSync: Date?
    /// Only the person who made the pod can remove people from it.
    @Published var iOwnPod = false

    /// Injectable so tests can move time without waiting for it.
    private let clock: () -> Date
    /// Where state is persisted. Tests point this at a temp file.
    private let storageURL: URL

    private var service: PodService
    private let shield: ShieldManager
    private var timer: Timer?
    private var saveWork: DispatchWorkItem?
    private var verdictTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var lastIncomingCheck = Date()
    private var lastSyncAttempt = Date.distantPast

    /// APNs device token, kept so it can be re-uploaded whenever we connect.
    @Published private(set) var pushToken: String?
    private let pushTokenKey = "locked.push.token"

    var isConnected: Bool { service.isRemote }
    var timeZoneOffsetMinutes: Int { TimeZone.current.secondsFromGMT() / 60 }

    // MARK: Init

    init(
        service: PodService? = nil,
        shield: ShieldManager,
        clock: @escaping () -> Date = { Date() },
        storageURL: URL? = nil,
        startTimer: Bool = true
    ) {
        let url = storageURL ?? AppState.defaultFileURL
        self.clock = clock
        self.storageURL = url

        let stored = ServerConfig.load()
        self.remote = stored

        let loaded = AppState.load(from: url)
        if let service {
            self.service = service
        } else if let stored, stored.isInPod {
            self.service = RemotePodService(config: stored)
        } else if loaded?.devMode == true {
            self.service = SimulatedPodService()
        } else {
            self.service = OfflinePodService()
        }

        self.shield = shield
        self.data = loaded ?? AppData()
        self.pushToken = LockedShared.defaults.string(forKey: "locked.push.token")
        self.now = clock()

        rollOver()
        // A session may have finished while the app was dead.
        settleSession()

        if let session = data.session, session.outcome == .running, data.liveActivityEnabled {
            // Cold launch mid-session: take over the Live Activity that's
            // already on the Lock Screen rather than starting a second one.
            publishSnapshot()
            live.resume(
                    goal: session.goal,
                    podNames: pod.map(\.name),
                    blockedCount: session.sealedCount,
                    plannedMinutes: session.plannedMinutes,
                startedAt: session.startedAt,
                endsAt: session.endsAt,
                breakUntil: session.breakUntil,
                requestsSent: session.requestsSent
            )
            shield.engage(window: session.startedAt...session.endsAt)
        } else {
            live.end()
            SessionSnapshot.clear()
        }

        if startTimer {
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
    }

    deinit { timer?.invalidate() }

    // MARK: Derived

    var session: Session? { data.session }
    var me: Profile { data.me }
    var pod: [PodMember] { data.members.filter(\.inPod) }

    var remaining: Int { session?.remaining(at: now) ?? 0 }
    var progress: Double { session?.progress(at: now) ?? 0 }
    var onBreak: Bool { session?.onBreak(at: now) ?? false }
    var breakRemaining: Int {
        guard let until = session?.breakUntil else { return 0 }
        return max(0, Int(until.timeIntervalSince(now).rounded(.up)))
    }

    var dayProgress: Double {
        guard data.me.dailyGoalSeconds > 0 else { return 0 }
        return min(1, Double(todayTotal) / Double(data.me.dailyGoalSeconds))
    }

    /// Banked time plus whatever the live session has already served.
    var todayTotal: Int {
        data.me.todaySeconds + (session?.elapsed(at: now) ?? 0)
    }

    var weekTotal: Int {
        data.me.weeklySeconds + (session?.elapsed(at: now) ?? 0)
    }

    var standings: [Standing] {
        var rows = pod.map { (name: $0.name, seconds: $0.weeklySeconds, isMe: false) }
        rows.append((name: "You", seconds: weekTotal, isMe: true))
        rows.sort { $0.seconds > $1.seconds }
        return rows.enumerated().map { i, r in
            Standing(name: r.name, seconds: r.seconds, isMe: r.isMe, rank: i + 1)
        }
    }

    var myPodRank: Int { standings.first(where: \.isMe)?.rank ?? 1 }
    var podSize: Int { standings.count }

    var podWeekSeconds: Int { pod.reduce(weekTotal) { $0 + $1.weeklySeconds } }

    var pendingIncoming: [UnlockRequest] {
        data.requests.filter { !$0.isOutgoing && $0.verdict == nil && $0.secondsLeft > 0 }
    }

    var greeting: String {
        switch Calendar.current.component(.hour, from: now) {
        case 0..<5: return "Still up, \(data.me.firstName)"
        case 5..<12: return "Good morning, \(data.me.firstName)"
        case 12..<18: return "Good afternoon, \(data.me.firstName)"
        default: return "Good evening, \(data.me.firstName)"
        }
    }

    /// How many apps and categories iOS will actually seal.
    ///
    /// Reads the live `FamilyActivitySelection` rather than a stored list. The
    /// tokens behind it are opaque by design — an app is never told which apps
    /// you picked — so a count is the whole of what can honestly be shown.
    var sealedCount: Int { shield.selectedCount }

    // MARK: Clock

    private func tick() {
        now = clock()

        if let s = session, s.outcome == .running {
            if s.remaining(at: now) == 0 {
                completeSession()
            } else if let until = s.breakUntil, until <= now {
                data.session?.breakUntil = nil
                shield.engage(window: s.startedAt...s.endsAt)
                publishSnapshot()
                live.update(startedAt: s.startedAt, endsAt: s.endsAt, breakUntil: nil, requestsSent: s.requestsSent)
                Haptics.seal()
                Notifier.nudge(title: "Sealed again.", body: "Break's over. Back to \(s.goal).")
                save()
            }
        }

        expireStaleRequests()
        maybeReceiveIncoming()

        if service.isRemote, now.timeIntervalSince(lastSyncAttempt) > 10 {
            syncTask?.cancel()
            syncTask = Task { [weak self] in await self?.sync() }
        }
    }

    /// Called when the app comes back to the foreground.
    func refresh() {
        now = clock()
        rollOver()
        settleSession()
        if service.isRemote {
            syncTask?.cancel()
            syncTask = Task { [weak self] in await self?.sync(force: true) }
        }
    }

    // MARK: The pod server

    /// Point the app at a real pod. Everything the simulated cast was standing in
    /// for gets replaced by whoever is actually in it.
    func connect(_ config: ServerConfig) {
        config.save()
        remote = config
        service = RemotePodService(config: config)

        data.devMode = false
        data.me.name = config.name
        data.me.initials = AppState.initials(for: config.name)
        if let podName = config.podName { data.podName = podName }
        // Drop the seeded stand-ins and everything they "did"; the server's
        // members and event log replace them.
        data.members.removeAll { $0.remoteID == nil }
        data.feed.removeAll()
        data.requests.removeAll()
        data.feedCursor = 0
        syncError = nil
        save()

        uploadPushToken()
        syncTask?.cancel()
        syncTask = Task { [weak self] in await self?.sync(force: true) }
    }

    /// Step out of the pod on the server, then fall back to the simulated one.
    func leavePodForReal() async {
        await service.leavePod()
        disconnect()
    }

    /// Remove someone else. The server refuses unless I made the pod.
    func kick(_ member: PodMember) async {
        guard let remoteID = member.remoteID else { return }
        await service.kick(memberID: remoteID)
        await sync(force: true)
    }

    /// Delete the account server-side, then wipe this device too — anything less
    /// isn't really deletion.
    func deleteAccountEverywhere() async {
        await service.deleteAccount()
        disconnect()
        resetEverything()
    }

    func disconnect() {
        syncTask?.cancel()
        ServerConfig.clear()
        remote = nil
        service = OfflinePodService()
        syncError = nil
        lastSync = nil
        iOwnPod = false
        // Nothing to fall back to — an empty pod is the truth. Dev mode is a
        // deliberate switch, not a fallback.
        data.members = []
        data.feed = []
        save()
    }

    // MARK: Push

    /// Called by the app delegate when APNs hands us a token.
    func registerPushToken(_ token: String) {
        guard token != pushToken else { return }
        pushToken = token
        LockedShared.defaults.set(token, forKey: pushTokenKey)
        uploadPushToken()
    }

    private func uploadPushToken() {
        guard service.isRemote, let token = pushToken else { return }
        Task { [service] in
            await service.registerDevice(token: token, environment: Notifier.pushEnvironment)
        }
    }

    /// A notification tap, or one of its buttons. The app may have been launched
    /// by this, so it can't assume any in-memory state exists.
    func handlePush(userInfo: [AnyHashable: Any], action: String) {
        switch userInfo["kind"] as? String {
        case "request":
            let requestID = userInfo["request_id"] as? String
            let requester = userInfo["requester"] as? String ?? "Someone"
            switch action {
            case Notifier.approveAction:
                answerFromNotification(requestID, requester: requester, approve: true)
            case Notifier.denyAction:
                answerFromNotification(requestID, requester: requester, approve: false)
            default:
                // Plain tap: bring the request up so they can decide properly.
                route = .pod
                nudgeSync()
            }

        case "verdict":
            // The outgoing poll will surface it; make sure we're current.
            nudgeSync()

        default:
            break
        }
    }

    /// Rule on someone else's request straight from the Lock Screen.
    private func answerFromNotification(_ requestID: String?, requester: String, approve: Bool) {
        guard let requestID, service.isRemote else { return }
        let quip = Copy.denials.randomElement() ?? Copy.denials[0]

        addFeed(FeedEvent(
            authorName: data.me.name, authorInitials: data.me.initials, isMe: true,
            kind: approve ? .granted(to: requester, minutes: 5) : .denied(to: requester)
        ))

        if let index = data.requests.firstIndex(where: { $0.remoteID == requestID }) {
            data.requests[index].verdict = approve
                ? .approved(by: data.me.name, minutes: 5)
                : .denied(by: data.me.name, quip: quip)
        }
        if incoming?.remoteID == requestID {
            incoming = nil
            incomingVerdict = nil
        }

        approve ? Haptics.success() : Haptics.seal()
        Task { [service] in
            await service.answer(requestID: requestID, approve: approve, quip: quip)
        }
        save()
        nudgeSync()
    }

    /// Record how the session ended and try to hand it to the server now.
    ///
    /// Queued first, uploaded second: hours are what the whole app is about, so a
    /// session finished on a train with no signal still counts once there is one.
    private func recordFinished(_ session: Session, outcome: String, served: Int) {
        data.pendingSessions.append(PendingSession(
            session: session,
            outcome: outcome,
            servedSeconds: served,
            tzOffsetMinutes: timeZoneOffsetMinutes
        ))

        // And back to Orbit, if this session came from a task there. It rides
        // here rather than in `completeSession` and `cave` because this is
        // already the one place a finished session fans out — which also means
        // the settle-on-relaunch path, where a session ended while the app was
        // dead, is covered without knowing it exists.
        OrbitLink.record(session, outcome: outcome, served: served, at: clock())

        save()
        flushSessions()
    }

    /// Retry anything the server hasn't accepted. Safe to call repeatedly — the
    /// server upserts on session id, so a double send changes nothing.
    private func flushSessions() {
        guard service.isRemote, !data.pendingSessions.isEmpty else { return }
        Task { [service] in
            for pending in self.data.pendingSessions {
                guard await service.openSession(pending.session, tzOffsetMinutes: pending.tzOffsetMinutes),
                      await service.closeSession(
                        id: pending.session.id,
                        outcome: pending.outcome,
                        servedSeconds: pending.servedSeconds
                      )
                else { continue }
                self.data.pendingSessions.removeAll { $0.id == pending.id }
            }
            self.save()
        }
    }

    // MARK: Dev mode

    /// Turn the Lock Screen timer on or off. Off ends whatever is showing now.
    func setLiveActivity(_ on: Bool) {
        data.liveActivityEnabled = on
        if on {
            if let session, session.outcome == .running {
                live.resume(
                    goal: session.goal,
                    podNames: pod.map(\.name),
                    blockedCount: session.sealedCount,
                    plannedMinutes: session.plannedMinutes,
                    startedAt: session.startedAt,
                    endsAt: session.endsAt,
                    breakUntil: session.breakUntil,
                    requestsSent: session.requestsSent
                )
            }
        } else {
            live.end()
        }
        Haptics.select()
        save()
    }

    /// Fill the pod with actors, or clear them out again.
    ///
    /// Only available while signed out of a real pod — mixing invented activity
    /// into a real feed would be worse than useless.
    func setDevMode(_ on: Bool) {
        guard !isConnected else { return }
        data.devMode = on

        if on {
            service = SimulatedPodService()
            data.members = PodMember.demoCast
            data.feed = FeedEvent.demoFeed
            data.podName = "Fifth Floor"
        } else {
            service = OfflinePodService()
            data.members = []
            data.feed = []
            data.requests = []
            incoming = nil
            incomingVerdict = nil
            data.podName = "Your pod"
        }
        Haptics.select()
        save()
    }

    /// Dev mode invents the occasional request so the judge's side can be seen.
    private func maybeReceiveIncoming() {
        guard data.devMode, !isConnected else { return }
        guard incoming == nil, session == nil else { return }
        guard now.timeIntervalSince(lastIncomingCheck) > 45 else { return }
        lastIncomingCheck = now
        guard Int.random(in: 0..<4) == 0 else { return }
        Task { await pullIncoming(force: false) }
    }

    /// Push a state change to the pod now rather than on the next tick.
    private func nudgeSync() {
        guard service.isRemote else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in await self?.sync(force: true) }
    }

    func sync(force: Bool = false) async {
        guard service.isRemote, let config = remote, config.isInPod else { return }
        if !force, clock().timeIntervalSince(lastSyncAttempt) < 10 { return }
        lastSyncAttempt = clock()

        await service.pushState(session: session, tzOffsetMinutes: timeZoneOffsetMinutes)

        if let pod = await service.fetchPod() {
            merge(pod)
            syncError = nil
            lastSync = clock()
        } else {
            syncError = "Can't reach \(config.baseURL)."
            return
        }

        if let feed = await service.fetchFeed(since: data.feedCursor) {
            merge(feed.events, cursor: feed.cursor)
        }

        flushSessions()

        // Somebody else's request, waiting on me.
        if incoming == nil, session == nil,
           let request = await service.pollIncoming(pod: pod, mySeed: 0) {
            let alreadyKnown = data.requests.contains { $0.remoteID == request.remoteID && $0.verdict != nil }
            if !alreadyKnown {
                data.requests.insert(request, at: 0)
                incoming = request
                incomingVerdict = nil
                Haptics.select()
                Notifier.nudge(
                    title: "\(request.requesterName) wants out.",
                    body: "“\(request.reason)” — \(Fmt.span(request.remainingAtRequest)) still on the clock."
                )
            }
        }

        save()
    }

    private func merge(_ pod: RemotePod) {
        data.podName = pod.name
        iOwnPod = pod.iOwnIt

        // The server counts hours from session records now, so while we're
        // connected its numbers win over our local tally. The running session
        // isn't in them yet, which is why `todayTotal` still adds elapsed time.
        if let mine = pod.me {
            data.me.weeklySeconds = mine.weeklySeconds
            data.me.streak = mine.streak
        }
        if let today = pod.myTodaySeconds { data.me.todaySeconds = today }
        if let caves = pod.myCavesThisWeek { data.me.cavesThisWeek = caves }

        // Keep local UUIDs stable across syncs so SwiftUI doesn't re-animate rows.
        data.members = pod.members.map { fresh in
            guard let existing = data.members.first(where: { $0.remoteID == fresh.remoteID }) else { return fresh }
            var updated = fresh
            updated.id = existing.id
            return updated
        }

        if var config = remote, config.inviteCode != pod.inviteCode || config.podName != pod.name {
            config.inviteCode = pod.inviteCode
            config.podName = pod.name
            config.save()
            remote = config
        }
    }

    private func merge(_ events: [FeedEvent], cursor: Int) {
        guard !events.isEmpty else {
            data.feedCursor = max(data.feedCursor, cursor)
            return
        }
        var known = Set(data.feed.map(\.id))
        for event in events where !known.contains(event.id) {
            data.feed.append(event)
            known.insert(event.id)
        }
        data.feed.sort { $0.date > $1.date }
        if data.feed.count > 60 { data.feed.removeLast(data.feed.count - 60) }
        data.feedCursor = cursor
    }

    /// If the clock ran out while we weren't running, close the session out now.
    private func settleSession() {
        guard let s = session, s.outcome == .running, s.remaining(at: clock()) == 0 else { return }
        completeSession(silent: true)
    }

    private func rollOver() {
        let cal = Calendar.current

        if !cal.isDate(data.dayStamp, inSameDayAs: now) {
            data.me.todaySeconds = 0
            data.dayStamp = now
            // A streak survives one night, not two.
            if let last = data.me.lastCompletedDay,
               let days = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: now)).day,
               days > 1 {
                data.me.streak = 0
            }
        }

        let sameWeek = cal.isDate(data.weekStamp, equalTo: now, toGranularity: .weekOfYear)
        if !sameWeek {
            data.me.weeklySeconds = 0
            data.me.cavesThisWeek = 0
            for i in data.members.indices { data.members[i].weeklySeconds = 0 }
            data.weekStamp = now
            save()
        }
    }

    // MARK: Sessions

    func startSession(goal: String, minutes: Int, stake: Stake, orbitTaskID: UUID? = nil) {
        let start = clock()
        let session = Session(
            goal: goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Work" : goal,
            plannedMinutes: minutes,
            startedAt: start,
            endsAt: start.addingTimeInterval(Double(minutes) * 60),
            blockedCount: sealedCount,
            orbitTaskID: orbitTaskID,
            stake: stake
        )

        data.session = session
        data.lastGoal = session.goal
        data.lastMinutes = minutes
        data.stake = stake
        outgoing = .none
        completed = nil

        shield.engage(window: session.startedAt...session.endsAt)
        publishSnapshot()
        if data.liveActivityEnabled {
            live.start(
            goal: session.goal,
            podNames: pod.map(\.name),
            blockedCount: session.sealedCount,
            plannedMinutes: session.plannedMinutes,
                startedAt: session.startedAt,
                endsAt: session.endsAt
            )
        }
        Notifier.scheduleSessionEnd(at: session.endsAt, goal: session.goal)
        if service.isRemote {
            Task { [service, offset = timeZoneOffsetMinutes] in
                await service.openSession(session, tzOffsetMinutes: offset)
            }
        }
        addFeed(FeedEvent(
            authorName: data.me.name, authorInitials: data.me.initials, isMe: true,
            kind: .locked(goal: session.goal, seconds: session.plannedSeconds)
        ))
        Haptics.seal()
        save()
        nudgeSync()
    }

    func completeSession(silent: Bool = false) {
        guard var s = data.session, s.outcome == .running else { return }
        s.outcome = .completed
        let served = s.plannedSeconds

        data.me.todaySeconds += served
        data.me.weeklySeconds += served
        data.me.bankedMinutes += max(1, s.plannedMinutes / 5)

        // Clock-driven rather than `isDateInToday`, so a day boundary is testable.
        let cal = Calendar.current
        let today = clock()
        let counted = data.me.lastCompletedDay.map { cal.isDate($0, inSameDayAs: today) } ?? false
        if !counted {
            data.me.streak += 1
            data.me.lastCompletedDay = today
        }

        data.history.insert(s, at: 0)
        data.session = nil
        outgoing = .none
        showCaveSheet = false

        addFeed(FeedEvent(
            authorName: data.me.name, authorInitials: data.me.initials, isMe: true,
            kind: .finished(seconds: served, streak: data.me.streak, goal: s.goal)
        ))

        shield.standDown()
        live.end()
        SessionSnapshot.clear()
        recordFinished(s, outcome: "completed", served: served)
        Notifier.cancelSessionEnd()
        if !silent {
            completed = s
            Haptics.success()
        }
        save()
        nudgeSync()
    }

    func cave() {
        guard var s = data.session, s.outcome == .running else { return }
        let left = s.remaining(at: clock())
        let served = s.elapsed(at: clock())
        s.outcome = .caved
        s.endsAt = clock()

        // Time actually served still counts. The failure is what gets published.
        data.me.todaySeconds += served
        data.me.weeklySeconds += served
        data.me.cavesThisWeek += 1
        data.me.streak = 0
        data.me.lastCompletedDay = nil

        data.history.insert(s, at: 0)
        data.session = nil
        outgoing = .none
        showCaveSheet = false

        // Published bare. Whatever the pod says about it, they say themselves —
        // see the note where `pileOn` used to be.
        addFeed(FeedEvent(
            authorName: data.me.name, authorInitials: data.me.initials, isMe: true,
            kind: .caved(remaining: left, goal: s.goal, reason: nil)
        ))

        shield.standDown()
        live.end()
        SessionSnapshot.clear()
        recordFinished(s, outcome: "caved", served: served)
        Notifier.cancelSessionEnd()
        route = .pod
        Haptics.failure()
        save()
        nudgeSync()
    }

    // `pileOn` used to live here. It waited 1.8 seconds after a real cave and
    // then wrote a comment — "lmao", "four. minutes." — attributed to a random
    // real member of your pod, plus a shame count for reactions nobody had made.
    //
    // It was not behind dev mode. It ran on live pods, putting words in the
    // mouths of actual people and showing them to those same people in the
    // shared feed. In an app whose entire argument is that self-reported
    // accountability is not accountability, inventing the pod's reaction is the
    // one thing it cannot do. `fetchFeed` already delivers the real thing.
    //
    // If a cave lands to silence, that is information about your pod.

    // MARK: Begging

    func compose() {
        outgoing = .composing
        Haptics.tap()
    }

    func cancelCompose() {
        outgoing = .none
        verdictTask?.cancel()
    }

    func sendRequest(reason: String) {
        guard let s = session else { return }
        let request = UnlockRequest(
            requesterName: data.me.name,
            requesterInitials: data.me.initials,
            isOutgoing: true,
            reason: reason,
            goal: s.goal,
            remainingAtRequest: s.remaining(at: now),
            streak: data.me.streak,
            cavesThisWeek: data.me.cavesThisWeek
        )

        data.session?.requestsSent += 1
        data.requests.insert(request, at: 0)
        outgoing = .pending(reason: reason)
        if let updated = data.session {
            live.update(
                startedAt: updated.startedAt,
                endsAt: updated.endsAt,
                breakUntil: updated.breakUntil,
                requestsSent: updated.requestsSent
            )
        }
        Haptics.tap()
        save()

        verdictTask?.cancel()
        verdictTask = Task { [weak self] in
            guard let self else { return }
            let verdict = await self.service.send(request, pod: self.pod)
            guard !Task.isCancelled else { return }
            self.applyVerdict(verdict, for: request.id)
        }
    }

    func applyVerdict(_ verdict: Verdict, for id: UUID) {
        if let i = data.requests.firstIndex(where: { $0.id == id }) {
            data.requests[i].verdict = verdict
        }
        outgoing = .verdict(verdict)

        switch verdict {
        case .approved(let by, let minutes):
            data.session?.breakUntil = clock().addingTimeInterval(Double(minutes) * 60)
            shield.lift()
            publishSnapshot()
            if let s = data.session {
                live.update(
                    startedAt: s.startedAt,
                    endsAt: s.endsAt,
                    breakUntil: s.breakUntil,
                    requestsSent: s.requestsSent
                )
            }
            Haptics.success()
            Notifier.nudge(title: "\(by) gave you \(minutes) minutes.",
                           body: "Then it seals again. They're watching the timer.")
        case .denied(let by, let quip):
            Haptics.failure()
            Notifier.nudge(title: "\(by) said no.", body: "“\(quip)” The clock keeps running.")
        case .expired:
            Haptics.failure()
        }
        save()
    }

    func dismissVerdict() {
        outgoing = .none
    }

    // MARK: Answering other people

    func pullIncoming(force: Bool) async {
        guard let request = await service.pollIncoming(pod: pod, mySeed: 0) else { return }
        guard force || incoming == nil else { return }
        data.requests.insert(request, at: 0)
        incoming = request
        incomingVerdict = nil
        Haptics.select()
        Notifier.nudge(title: "\(request.requesterName) wants out.",
                       body: "“\(request.reason)” — \(Fmt.span(request.remainingAtRequest)) still on the clock.")
        save()
    }

    func answer(_ request: UnlockRequest, approve: Bool) {
        let quip = Copy.denials.randomElement() ?? Copy.denials[0]
        let verdict: Verdict = approve
            ? .approved(by: data.me.name, minutes: 5)
            : .denied(by: data.me.name, quip: quip)

        if service.isRemote {
            Task { [service] in await service.answer(request, approve: approve, quip: quip) }
        }

        if let i = data.requests.firstIndex(where: { $0.id == request.id }) {
            data.requests[i].verdict = verdict
        }

        addFeed(FeedEvent(
            authorName: data.me.name, authorInitials: data.me.initials, isMe: true,
            kind: approve ? .granted(to: request.requesterName, minutes: 5) : .denied(to: request.requesterName)
        ))

        incomingVerdict = verdict
        approve ? Haptics.success() : Haptics.seal()
        save()
    }

    func dismissIncoming() {
        if let request = incoming,
           let i = data.requests.firstIndex(where: { $0.id == request.id }),
           data.requests[i].verdict == nil {
            data.requests[i].verdict = .expired
        }
        incoming = nil
        incomingVerdict = nil
        save()
    }

    private func expireStaleRequests() {
        var changed = false
        for i in data.requests.indices where data.requests[i].verdict == nil {
            if data.requests[i].secondsLeft == 0 {
                data.requests[i].verdict = .expired
                changed = true
                if data.requests[i].isOutgoing, case .pending = outgoing {
                    outgoing = .verdict(.expired)
                }
            }
        }
        if changed { save() }
    }

    // MARK: Pod

    func nudge(_ member: PodMember) {
        addFeed(FeedEvent(
            authorName: data.me.name, authorInitials: data.me.initials, isMe: true,
            kind: .nudged(name: member.name)
        ))
        Haptics.tap()
        Notifier.nudge(title: "Nudge sent.", body: "\(member.name) has been told to lock something.")
        save()
    }

    func shame(_ event: FeedEvent) {
        guard let i = data.feed.firstIndex(where: { $0.id == event.id }) else { return }
        data.feed[i].shame += 1
        Haptics.tap()
        save()
    }

    func finishOnboarding() {
        data.hasOnboarded = true
        Haptics.success()
        save()
    }

    func resetEverything() {
        verdictTask?.cancel()
        shield.lift()
        Notifier.cancelSessionEnd()
        data = AppData()
        route = .today
        outgoing = .none
        incoming = nil
        completed = nil
        save()
    }

    private func addFeed(_ event: FeedEvent) {
        data.feed.insert(event, at: 0)
        if data.feed.count > 60 { data.feed.removeLast(data.feed.count - 60) }
        Task { await service.publish(event) }
    }

    // MARK: Notification permission

    func askForNotificationsIfNeeded() {
        guard !data.notificationsAsked else { return }
        data.notificationsAsked = true
        save()
        Task { _ = await Notifier.requestAuthorization() }
    }

    // MARK: Persistence

    /// Lives in the app group so the shield and monitor extensions share it.
    static var defaultFileURL: URL {
        LockedShared.file("locked-state.json")
    }

    /// Where it lived before the app group existed.
    private static var legacyURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("locked-state.json")
    }

    private static func load(from url: URL) -> AppData? {
        if let raw = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder.iso.decode(AppData.self, from: raw) {
            return decoded
        }
        // One-time migration out of Documents.
        guard url == defaultFileURL,
              let raw = try? Data(contentsOf: legacyURL),
              let decoded = try? JSONDecoder.iso.decode(AppData.self, from: raw)
        else { return nil }
        try? raw.write(to: url, options: .atomic)
        try? FileManager.default.removeItem(at: legacyURL)
        return decoded
    }

    /// The slice the extensions read: goal, clock, who's watching.
    private func publishSnapshot() {
        guard let session = data.session, session.outcome == .running else {
            SessionSnapshot.clear()
            return
        }
        SessionSnapshot(
            goal: session.goal,
            startedAt: session.startedAt,
            endsAt: session.endsAt,
            breakUntil: session.breakUntil,
            podNames: pod.map(\.name),
            blockedCount: session.sealedCount,
            ownerName: data.me.firstName
        ).save()
    }

    /// Debounced — the timer touches state every second and we don't need a
    /// write per tick.
    func save() {
        saveWork?.cancel()
        let snapshot = data
        let url = storageURL
        let work = DispatchWorkItem {
            guard let raw = try? JSONEncoder.iso.encode(snapshot) else { return }
            try? raw.write(to: url, options: .atomic)
        }
        saveWork = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        guard let raw = try? JSONEncoder.iso.encode(data) else { return }
        try? raw.write(to: storageURL, options: .atomic)
    }
}

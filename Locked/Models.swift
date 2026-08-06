import Foundation

// MARK: - Stakes

enum Stake: String, Codable, CaseIterable, Identifiable {
    case post, streak, money

    var id: String { rawValue }

    var title: String {
        switch self {
        case .post: return "Auto-post the failure"
        case .streak: return "Lose the streak"
        case .money: return "Five dollars to the pot"
        }
    }

    var note: String {
        switch self {
        case .post: return "A card in the pod feed with the exact minute you quit."
        case .streak: return "Every day gone. Back to zero, publicly."
        case .money: return "Whoever logs the most hours this month takes it."
        }
    }
}

// MARK: - Pod members

enum MemberStatus: Codable, Hashable {
    case idle
    case locked(goal: String, endsAt: Date)
    case caved(minutesIn: Int, at: Date)
    case finished(seconds: Int, at: Date)

    var isLocked: Bool {
        if case .locked(_, let endsAt) = self { return endsAt > Date() }
        return false
    }
}

struct PodMember: Identifiable, Codable, Hashable {
    var id = UUID()
    /// The server's id for this person, when the pod is real.
    var remoteID: String? = nil
    var name: String
    var initials: String
    /// The line shown under the name when picking a pod.
    var note: String
    var inPod: Bool
    var weeklySeconds: Int = 0
    var streak: Int = 0
    var status: MemberStatus = .idle

    var statusLine: String {
        switch status {
        case .idle:
            return "Nothing today. Not one minute"
        case .locked(let goal, let endsAt):
            let left = Int(endsAt.timeIntervalSinceNow)
            return left > 0 ? "Locked · \(goal)" : "Finished · \(goal)"
        case .caved(let minutesIn, _):
            return "Caved \(minutesIn) minute\(minutesIn == 1 ? "" : "s") in"
        case .finished(let seconds, _):
            return "Finished \(Fmt.span(seconds))"
        }
    }

    var statusTrailing: String {
        switch status {
        case .locked(_, let endsAt):
            let left = Int(endsAt.timeIntervalSinceNow)
            return left > 0 ? "\(Fmt.span(left)) left" : ""
        case .caved(_, let at), .finished(_, let at):
            return Fmt.time(at)
        case .idle:
            return ""
        }
    }
}

// MARK: - The feed

struct FeedEvent: Identifiable, Codable, Hashable {
    var id = UUID()
    var authorName: String
    var authorInitials: String
    var isMe: Bool = false
    var kind: Kind
    var date: Date = Date()
    var shame: Int = 0
    var comment: String? = nil
    var commentAuthor: String? = nil

    enum Kind: Codable, Hashable {
        case caved(remaining: Int, goal: String, reason: String?)
        case finished(seconds: Int, streak: Int, goal: String)
        case locked(goal: String, seconds: Int)
        case granted(to: String, minutes: Int)
        case denied(to: String)
        case nudged(name: String)
    }

    /// The big serif headline on each card.
    var headline: String {
        switch kind {
        case .caved(let remaining, let goal, _):
            let who = isMe ? "You folded" : "\(authorName) folded"
            _ = goal
            return "\(who) with \(Fmt.clock(remaining)) left. Everyone knows."
        case .finished(let seconds, let streak, _):
            let who = isMe ? "You finished" : "Finished"
            return "\(who) \(Fmt.span(seconds)). Streak \(streak)."
        case .locked(let goal, let seconds):
            return "Locked for \(Fmt.span(seconds)) — \(goal)"
        case .granted(let to, let minutes):
            return isMe ? "You gave \(to) \(minutes) minutes." : "\(authorName) let \(to) out for \(minutes) minutes."
        case .denied(let to):
            return isMe ? "You told \(to) no." : "\(authorName) told \(to) no."
        case .nudged(let name):
            return "\(name) got a nudge."
        }
    }

    var subline: String? {
        switch kind {
        case .caved(_, let goal, let reason):
            if let reason { return "Reason given: “\(reason)” · \(goal)" }
            return "Goal abandoned: \(goal)"
        case .finished(_, _, let goal):
            return "Goal checked off: \(goal)"
        case .locked:
            return nil
        case .granted, .denied:
            return "The pod feed remembers."
        case .nudged:
            return nil
        }
    }

    var isFailure: Bool {
        if case .caved = kind { return true }
        return false
    }
}

// MARK: - Unlock requests

enum Verdict: Codable, Hashable {
    case approved(by: String, minutes: Int)
    case denied(by: String, quip: String)
    case expired

    var isApproval: Bool {
        if case .approved = self { return true }
        return false
    }
}

struct UnlockRequest: Identifiable, Codable, Hashable {
    var id = UUID()
    /// Set for requests that arrived from the server; my own outgoing requests
    /// use `id.uuidString` as their server id, so they don't need one.
    var remoteID: String? = nil
    var requesterName: String
    var requesterInitials: String
    /// True when this is *my* request going out to the pod.
    var isOutgoing: Bool
    var reason: String
    var goal: String
    var remainingAtRequest: Int
    var streak: Int
    var cavesThisWeek: Int
    var createdAt: Date = Date()
    /// The prototype's rule: ignore it and the request dies in 60 seconds.
    var lifetime: TimeInterval = 60
    var verdict: Verdict? = nil

    var expiresAt: Date { createdAt.addingTimeInterval(lifetime) }
    var secondsLeft: Int { max(0, Int(expiresAt.timeIntervalSinceNow.rounded())) }
}

// MARK: - A session

struct Session: Identifiable, Codable, Hashable {
    var id = UUID()
    var goal: String
    var plannedMinutes: Int
    var startedAt: Date
    var endsAt: Date
    var blocked: [String]
    var stake: Stake
    /// Set when the pod grants a break — the shield lifts but the clock keeps running.
    var breakUntil: Date? = nil
    var outcome: Outcome = .running
    var requestsSent: Int = 0

    enum Outcome: String, Codable { case running, completed, caved }

    var plannedSeconds: Int { plannedMinutes * 60 }

    func remaining(at now: Date = Date()) -> Int {
        max(0, Int(endsAt.timeIntervalSince(now).rounded(.up)))
    }

    func elapsed(at now: Date = Date()) -> Int {
        max(0, min(plannedSeconds, Int(now.timeIntervalSince(startedAt))))
    }

    func progress(at now: Date = Date()) -> Double {
        guard plannedSeconds > 0 else { return 1 }
        return min(1, max(0, Double(elapsed(at: now)) / Double(plannedSeconds)))
    }

    func onBreak(at now: Date = Date()) -> Bool {
        guard let breakUntil else { return false }
        return breakUntil > now
    }
}

// MARK: - Me

struct Profile: Codable {
    var name = "You"
    var initials = "YO"
    var streak = 0
    var dailyGoalSeconds = 4 * 3600
    var todaySeconds = 0
    var weeklySeconds = 0
    var bankedMinutes = 0
    var cavesThisWeek = 0
    var globalTotal = 214_900
    /// So a streak counts days, not sessions.
    var lastCompletedDay: Date? = nil

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }

    /// Where you'd sit on a global board. Derived from hours locked this week so
    /// the number actually moves; swap for a server value when you have one.
    var globalRank: Int {
        let tau = 2.55 * 3600
        let fraction = exp(-Double(weeklySeconds) / tau)
        return max(1, min(globalTotal, Int(Double(globalTotal) * fraction)))
    }

    var globalPercentile: Int {
        max(1, Int((Double(globalRank) / Double(globalTotal) * 100).rounded(.up)))
    }
}

// MARK: - App toggles
//
// The chip list from the prototype. When the Screen Time entitlement is live
// these are replaced by real ApplicationTokens from FamilyActivityPicker —
// see Blocking.swift.

struct AppToggle: Identifiable, Codable, Hashable {
    var id: String { name }
    var name: String
    var on: Bool
}

/// A finished session waiting to be uploaded.
struct PendingSession: Codable, Identifiable, Hashable {
    var session: Session
    var outcome: String
    var servedSeconds: Int
    var tzOffsetMinutes: Int

    var id: UUID { session.id }
}

// MARK: - Persisted root

struct AppData: Codable {
    var hasOnboarded = false
    var podName = "Your pod"
    var me = Profile()
    var members: [PodMember] = []
    var feed: [FeedEvent] = []
    var apps: [AppToggle] = AppToggle.seed
    var stake: Stake = .post
    var lastGoal = "Finish the problem set"
    var lastMinutes = 90
    var session: Session? = nil
    var requests: [UnlockRequest] = []
    var history: [Session] = []
    /// Day/week boundaries so "today" and "this week" actually roll over.
    var dayStamp: Date = Date()
    var weekStamp: Date = Date()
    var notificationsAsked = false
    /// How far through the server's event log we've read.
    var feedCursor: Int = 0
    /// Finished sessions the server hasn't accepted yet. Hours are the product;
    /// losing them to a dropped connection isn't acceptable.
    var pendingSessions: [PendingSession] = []
    /// Dev mode: a simulated pod of actors, for demos and testing. Off unless
    /// explicitly switched on in Settings.
    var devMode = false

    var pod: [PodMember] { members.filter(\.inPod) }
}

// MARK: - Dev mode fixtures
//
// A real pod's members and feed only ever come from the server. This cast exists
// solely for dev mode — an explicit switch in Settings for demos and testing. It
// is never loaded otherwise, and nothing it "does" leaves the device.

extension PodMember {
    static var demoCast: [PodMember] {
        [
            PodMember(name: "Maya", initials: "MK", note: "Never once caved", inPod: true,
                      weeklySeconds: 11 * 3600 + 40 * 60, streak: 14,
                      status: .locked(goal: "thesis chapter 3", endsAt: Date().addingTimeInterval(72 * 60))),
            PodMember(name: "Priya", initials: "PR", note: "Terrifying. Good.", inPod: true,
                      weeklySeconds: 14 * 3600 + 5 * 60, streak: 12,
                      status: .locked(goal: "grading", endsAt: Date().addingTimeInterval(24 * 60))),
            PodMember(name: "Dev", initials: "DV", note: "Caves constantly. Keep him", inPod: true,
                      weeklySeconds: 3 * 3600 + 2 * 60, streak: 0,
                      status: .caved(minutesIn: 4, at: Calendar.current.date(bySettingHour: 11, minute: 42, second: 0, of: Date()) ?? Date())),
            PodMember(name: "Jonah", initials: "JN", note: "Roommate, so he can see you", inPod: true,
                      weeklySeconds: 0, streak: 0, status: .idle),
        ]
    }
}

extension FeedEvent {
    static var demoFeed: [FeedEvent] {
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
        }
        return [
            FeedEvent(authorName: "Maya", authorInitials: "MK",
                      kind: .locked(goal: "thesis chapter 3", seconds: 72 * 60),
                      date: Date().addingTimeInterval(-20 * 60)),
            FeedEvent(authorName: "Dev", authorInitials: "DV",
                      kind: .caved(remaining: 116 * 60, goal: "a 2 hour session", reason: "need to check one thing"),
                      date: at(11, 42), shame: 7, comment: "four. minutes.", commentAuthor: "Priya"),
            FeedEvent(authorName: "Priya", authorInitials: "PR",
                      kind: .finished(seconds: 150 * 60, streak: 12, goal: "grade the midterms"),
                      date: at(9, 5)),
        ]
    }
}

extension AppToggle {
    static var seed: [AppToggle] {
        [
            AppToggle(name: "Instagram", on: true),
            AppToggle(name: "TikTok", on: true),
            AppToggle(name: "X", on: true),
            AppToggle(name: "YouTube", on: true),
            AppToggle(name: "Reddit", on: true),
            AppToggle(name: "Snapchat", on: false),
        ]
    }
}

enum Copy {
    static let goalChips = [
        "Finish the problem set",
        "Write the essay",
        "Study for the final",
        "Inbox to zero",
    ]

    static let durations = [30, 60, 90, 120]

    static let reasons = [
        "My mom is calling",
        "Ordering food, genuinely",
        "Actually just bored",
        "I want to argue online",
    ]

    /// What a pod member says when they turn you down.
    static let denials = [
        "you asked me to do this.",
        "no. go back.",
        "absolutely not, you have 40 minutes left.",
        "this is what you wanted.",
        "read your own goal again.",
    ]
}

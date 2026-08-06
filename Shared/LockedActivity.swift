import ActivityKit
import Foundation

/// What the Lock Screen and Dynamic Island get told about a session.
///
/// The countdown itself is *not* in here — `Text(timerInterval:)` and
/// `ProgressView(timerInterval:)` tick on their own from the date range, so a
/// running session needs no updates at all. We only push an update when
/// something actually changes: the pod grants a break, or it re-seals.
struct LockedActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var startedAt: Date
        var endsAt: Date
        /// Set while the pod has granted phone time. The clock keeps running.
        var breakUntil: Date?
        var requestsSent: Int

        var onBreak: Bool { (breakUntil ?? .distantPast) > Date() }

        /// The window the countdown counts over.
        var range: ClosedRange<Date> {
            let start = min(startedAt, endsAt.addingTimeInterval(-1))
            return start...max(endsAt, start.addingTimeInterval(1))
        }
    }

    var goal: String
    var podNames: [String]
    var blockedCount: Int
    var plannedMinutes: Int

    var watcherLine: String {
        guard !podNames.isEmpty else { return "No pod" }
        return Fmt.names(podNames, max: 2) + (podNames.count == 1 ? " is watching" : " watching")
    }
}

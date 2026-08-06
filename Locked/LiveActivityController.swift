import ActivityKit
import Foundation

/// Owns the one Live Activity a session gets.
///
/// The countdown needs no updates — the Lock Screen ticks it locally from the
/// date range. We only talk to ActivityKit at the four moments the *state*
/// changes: start, break granted, break over, session over.
@MainActor
final class LiveActivityController: ObservableObject {
    @Published private(set) var isRunning = false

    /// Why the Lock Screen is empty, when it is. Surfaced in Settings rather
    /// than swallowed: a silent `catch` here hid a bug for a whole build.
    @Published private(set) var lastError: String?

    /// False when the user has switched Live Activities off for Locked.
    var isAllowed: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    private var activity: Activity<LockedActivityAttributes>?

    /// One line for Settings.
    var status: String {
        if !isAllowed { return "Off in iOS Settings › Locked" }
        if let lastError { return lastError }
        if isRunning { return "On the Lock Screen" }
        return "Starts with your next session"
    }

    func start(
        goal: String,
        podNames: [String],
        blockedCount: Int,
        plannedMinutes: Int,
        startedAt: Date,
        endsAt: Date
    ) {
        guard isAllowed else {
            isRunning = false
            lastError = nil
            return
        }

        // Capture the stragglers *before* requesting, and never end the one we
        // are about to create.
        //
        // This used to call an async "end everything" helper first. Being async,
        // it ran after this function returned — by which point the new activity
        // existed, so our own cleanup ended it immediately and the Lock Screen
        // stayed empty. Order matters more than it looks here.
        let stragglers = Activity<LockedActivityAttributes>.activities

        let attributes = LockedActivityAttributes(
            goal: goal,
            podNames: podNames,
            blockedCount: blockedCount,
            plannedMinutes: plannedMinutes
        )
        let state = LockedActivityAttributes.ContentState(
            startedAt: startedAt,
            endsAt: endsAt,
            breakUntil: nil,
            requestsSent: 0
        )

        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: endsAt.addingTimeInterval(120)),
                pushType: nil
            )
            isRunning = true
            lastError = nil
        } catch {
            isRunning = false
            lastError = "iOS refused it: \(error.localizedDescription)"
        }

        let keep = activity?.id
        Task {
            for stray in stragglers where stray.id != keep {
                await stray.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    func update(startedAt: Date, endsAt: Date, breakUntil: Date?, requestsSent: Int) {
        guard let activity else { return }
        let state = LockedActivityAttributes.ContentState(
            startedAt: startedAt,
            endsAt: endsAt,
            breakUntil: breakUntil,
            requestsSent: requestsSent
        )
        let content = ActivityContent(state: state, staleDate: endsAt.addingTimeInterval(120))
        Task { await activity.update(content) }
    }

    func end() {
        let closing = activity
        let stragglers = Activity<LockedActivityAttributes>.activities
        activity = nil
        isRunning = false
        Task {
            await closing?.end(nil, dismissalPolicy: .immediate)
            for stray in stragglers {
                await stray.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// After a cold launch mid-session, take ownership of the activity that's
    /// already on the Lock Screen instead of starting a second one.
    func reattach() {
        activity = Activity<LockedActivityAttributes>.activities.first
        isRunning = activity != nil
    }

    /// Cold launch with a session still running: adopt the existing activity, or
    /// start a fresh one if there isn't one (reinstalled, or the user turned
    /// Live Activities back on mid-session).
    func resume(
        goal: String,
        podNames: [String],
        blockedCount: Int,
        plannedMinutes: Int,
        startedAt: Date,
        endsAt: Date,
        breakUntil: Date?,
        requestsSent: Int
    ) {
        reattach()
        if activity == nil {
            start(
                goal: goal,
                podNames: podNames,
                blockedCount: blockedCount,
                plannedMinutes: plannedMinutes,
                startedAt: startedAt,
                endsAt: endsAt
            )
        }
        update(startedAt: startedAt, endsAt: endsAt, breakUntil: breakUntil, requestsSent: requestsSent)
    }
}

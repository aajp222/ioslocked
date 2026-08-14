import Foundation

/// LOCKED's side of the Orbit bridge.
///
/// Read-only with respect to Orbit's plan, append-only with respect to
/// receipts. LOCKED never writes a plan and never deletes a receipt — those
/// belong to Orbit, and keeping the ownership one-way per file is what lets two
/// apps share a directory without a database or a lock on the common path.
///
/// It also exists so that rolling the integration back is deleting one file and
/// reverting five call sites, rather than unpicking Orbit-shaped logic from
/// `AppState`.
enum OrbitLink {

    /// Whether *this* app holds the shared-container entitlement.
    ///
    /// Deliberately not exposed to the UI. It says nothing about Orbit: LOCKED
    /// entitles itself, so this is true on a phone that has never had Orbit
    /// installed. Reporting it as "connected" is exactly the mistake `status`
    /// exists to prevent — use that instead.
    private static var containerIsProvisioned: Bool { OrbitBridge.isAvailable }

    /// What the bridge can honestly claim right now.
    enum Status: Equatable {
        /// The App Group isn't provisioned to this build. Nothing to be done
        /// from inside the app; it means a signing problem.
        case unavailable
        /// Nobody has ever written a plan here. Orbit isn't installed, or has
        /// never finished a refresh. Indistinguishable from outside, and the
        /// advice is the same either way.
        case noPlan
        /// Orbit wrote a plan, but not recently enough to lock against.
        case stale(since: Date)
        /// Fresh, and Orbit says you have nothing due.
        case empty
        /// Fresh, with this many things worth sealing the phone for.
        case ready(count: Int)
    }

    /// Derived from a plan value rather than read directly, so every branch is
    /// reachable in a test. `status` is the convenience that reads the disk.
    static func status(
        for plan: OrbitBridge.FocusPlan?,
        provisioned: Bool,
        now: Date = Date()
    ) -> Status {
        guard provisioned else { return .unavailable }
        guard let plan else { return .noPlan }
        guard plan.isFresh(at: now) else { return .stale(since: plan.generatedAt) }
        return plan.candidates.isEmpty ? .empty : .ready(count: plan.candidates.count)
    }

    static var status: Status {
        status(for: OrbitBridge.storedPlan(), provisioned: containerIsProvisioned)
    }

    /// What Orbit thinks is worth sealing the phone for.
    ///
    /// Empty when there is no plan, it can't be read, or it has gone stale —
    /// all three mean the same thing to the caller, which is to fall back to
    /// LOCKED's own goal chips. A stale plan is not a lesser plan; locking
    /// yourself to yesterday's priorities is worse than locking yourself to
    /// "Work", because it feels informed.
    static func suggestions() -> [OrbitBridge.FocusCandidate] {
        OrbitBridge.readPlan()?.candidates ?? []
    }

    /// One candidate by id, for a deep link that names a task.
    static func candidate(for taskID: UUID) -> OrbitBridge.FocusCandidate? {
        OrbitBridge.readPlan()?.candidates.first { $0.id == taskID }
    }

    /// Hands a finished session back to Orbit.
    ///
    /// A no-op for sessions that did not come from a task, which is most of
    /// them — LOCKED works perfectly well with Orbit uninstalled and should
    /// carry on doing so.
    ///
    /// What crosses is time served, not completion. LOCKED knows the phone was
    /// sealed for ninety minutes against a task id; it does not know whether the
    /// essay is written, and it is not going to guess.
    static func record(_ session: Session, outcome: String, served: Int, at endedAt: Date) {
        guard let taskID = session.orbitTaskID,
              let kind = OrbitBridge.SessionReceipt.Outcome(rawValue: outcome)
        else { return }

        OrbitBridge.append(OrbitBridge.SessionReceipt(
            id: session.id,
            taskID: taskID,
            outcome: kind,
            servedSeconds: served,
            startedAt: session.startedAt,
            endedAt: endedAt
        ))
    }
}

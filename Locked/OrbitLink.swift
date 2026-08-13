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

    /// Whether Orbit is set up to talk to this build at all.
    ///
    /// Distinct from "has a plan": a provisioned bridge with nothing in it means
    /// Orbit looked and you have nothing due, which is a real answer. An
    /// unprovisioned one means the two apps were never introduced.
    static var isAvailable: Bool { OrbitBridge.isAvailable }

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

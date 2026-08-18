import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// The backstop. iOS runs this even when Locked isn't running, so force-quitting
/// the app mid-session doesn't hand the phone back.
///
/// `intervalDidStart` fires at the start of the session window and re-applies
/// the shield from the tokens the app saved in the group; `intervalDidEnd` fires
/// when the window closes and clears it. Between those, the app itself keeps the
/// shield in step (breaks, folding early).
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let store = ManagedSettingsStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        guard activity.rawValue == LockedShared.activityName else { return }
        applyShield()
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity.rawValue == LockedShared.activityName else { return }
        clearShield()
        SessionSnapshot.clear()
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
    }

    // MARK: Shield

    private func applyShield() {
        // A snapshot we cannot read is not evidence that the session ended.
        //
        // This used to fall through to `clearShield`, which meant any failure
        // to read — a write that had not landed yet, a transient App Group
        // problem — unlocked the phone. For an app whose entire claim is that
        // the block is not yours to remove, an unreadable state must never
        // resolve to "unlocked". Leave whatever the app set and let the next
        // interval boundary sort it out.
        guard let snapshot = SessionSnapshot.load() else { return }

        // A finished session or a pod-granted break are different: both are
        // positive knowledge that the shield should come down.
        guard snapshot.isRunning, !snapshot.onBreak else {
            clearShield()
            return
        }
        guard let selection = loadSelection() else { return }

        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    private func clearShield() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }

    private func loadSelection() -> FamilyActivitySelection? {
        guard let data = LockedShared.defaults.data(forKey: LockedShared.selectionKey) else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }
}

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
        // Don't re-arm over a pod-granted break, or after the session ended.
        guard let snapshot = SessionSnapshot.load(), snapshot.isRunning, !snapshot.onBreak else {
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

import SwiftUI

#if canImport(FamilyControls)
import DeviceActivity
import FamilyControls
import ManagedSettings
#endif

/// How much of the lock is real right now.
enum ShieldState: Equatable {
    /// Framework isn't on this platform at all.
    case unsupported
    /// Framework is here but Apple hasn't granted the app the Family Controls
    /// entitlement, or the user hasn't authorized it yet.
    case needsPermission
    case denied
    /// Authorized — but nothing picked to block yet.
    case noSelection
    /// Real system-level blocking is armed.
    case ready

    var isReal: Bool { self == .ready }

    var label: String {
        switch self {
        case .unsupported: return "Not available on this device"
        case .needsPermission: return "Screen Time access not granted"
        case .denied: return "Screen Time access denied"
        case .noSelection: return "No apps picked yet"
        case .ready: return "Real blocking armed"
        }
    }
}

/// Wraps Apple's Screen Time stack (FamilyControls + ManagedSettings).
///
/// Blocking other apps at the OS level is the one thing an app cannot do on its
/// own: it needs the `com.apple.developer.family-controls` entitlement, which
/// Apple grants by request. Until that lands, the app runs in honour-system
/// mode — every screen, timer, stake and pod mechanic works, the shield just
/// isn't enforced by iOS. `state` says which mode you're in, and the UI is
/// honest about it rather than pretending.
@MainActor
final class ShieldManager: ObservableObject {
    @Published private(set) var state: ShieldState = .unsupported
    @Published private(set) var engaged = false

    #if canImport(FamilyControls)
    @Published var selection = FamilyActivitySelection() {
        didSet {
            persistSelection()
            refreshState()
        }
    }

    private let store = ManagedSettingsStore()
    private let center = DeviceActivityCenter()
    #endif

    init() {
        #if canImport(FamilyControls)
        restoreSelection()
        refreshState()
        #else
        state = .unsupported
        #endif
    }

    var selectedCount: Int {
        #if canImport(FamilyControls)
        return selection.applicationTokens.count + selection.categoryTokens.count
        #else
        return 0
        #endif
    }

    /// True when the framework is present, so it's worth showing the UI at all.
    var isAvailable: Bool {
        #if canImport(FamilyControls)
        return true
        #else
        return false
        #endif
    }

    /// The last thing Family Controls said when it refused. Kept because the
    /// reasons are genuinely different — a Managed Apple ID, a Screen Time
    /// passcode someone else set, a child account, a missing entitlement — and
    /// they need different answers. Throwing this away and reporting "not
    /// granted" for all of them turns a five-second fix into an afternoon.
    @Published private(set) var lastAuthorizationError: String?

    func requestAuthorization() async {
        #if canImport(FamilyControls)
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            lastAuthorizationError = nil
        } catch {
            lastAuthorizationError = String(describing: error)
        }
        refreshState()
        #endif
    }

    /// Arm the shield for a session. Returns whether iOS is actually enforcing
    /// anything, so a caller can tell a real lock from the honour system.
    ///
    /// Pass the session window and the monitor extension will re-apply the
    /// shield even if the app is killed, and clear it when the interval ends.
    ///
    /// Authorization is re-read first rather than trusted. `state` is a cached
    /// answer to a question only iOS can settle, and it goes stale the moment
    /// you grant Screen Time access in Settings while this app is in the
    /// background — which is the most likely way anyone ever grants it.
    /// Deciding on the cached value meant refusing to arm a shield the system
    /// would have allowed, and saying nothing about it.
    @discardableResult
    func engage(window: ClosedRange<Date>? = nil) -> Bool {
        #if canImport(FamilyControls)
        refreshState()
        guard state == .ready else {
            // Honour system: the session is real, the block is not. `engaged`
            // says which, and must not claim otherwise.
            engaged = false
            return false
        }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        if let window { startMonitoring(window) }
        engaged = true
        return true
        #else
        engaged = false
        return false
        #endif
    }

    /// Re-read the authorization iOS holds, which can change without this app
    /// running. Cheap, and the answer is the difference between a lock and a
    /// timer with strong opinions.
    func refreshAuthorization() {
        refreshState()
    }

    /// Lift it — session over, folded, or on a pod-granted break.
    func lift() {
        engaged = false
        #if canImport(FamilyControls)
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
        #endif
    }

    /// Session over for good: also tear down the schedule.
    func standDown() {
        lift()
        #if canImport(FamilyControls)
        center.stopMonitoring([DeviceActivityName(LockedShared.activityName)])
        #endif
    }

    #if canImport(FamilyControls)
    private func startMonitoring(_ window: ClosedRange<Date>) {
        // Apple rejects schedules shorter than 15 minutes. Below that the app
        // is alive for the whole session anyway, so the in-app shield covers it.
        guard window.upperBound.timeIntervalSince(window.lowerBound) >= 15 * 60 else { return }

        let cal = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: cal.dateComponents([.hour, .minute, .second], from: window.lowerBound),
            intervalEnd: cal.dateComponents([.hour, .minute, .second], from: window.upperBound),
            repeats: false
        )
        let name = DeviceActivityName(LockedShared.activityName)
        center.stopMonitoring([name])
        try? center.startMonitoring(name, during: schedule)
    }
    #endif

    // MARK: Diagnostics
    //
    // Everything here reads back what the system currently holds rather than
    // what this app believes it set. That distinction is the whole point: the
    // app can report "armed" while `ManagedSettingsStore` holds nothing,
    // because writing a shield and a shield existing are different events and
    // nothing in between reports failure.

    /// What `ManagedSettingsStore` says is shielded *right now*, read back out
    /// of the store rather than from `selection`. Nil means nothing is shielded.
    var shieldedApplicationCount: Int? {
        #if canImport(FamilyControls)
        store.shield.applications?.count
        #else
        nil
        #endif
    }

    var shieldedCategoryDescription: String {
        #if canImport(FamilyControls)
        switch store.shield.applicationCategories {
        case .none: return "none"
        case .some(.all): return "all"
        case .some(.specific(let set, except: _)): return "\(set.count) specific"
        @unknown default: return "unknown"
        }
        #else
        return "unsupported"
        #endif
    }

    /// DeviceActivity schedules iOS is currently monitoring. If ours is absent
    /// mid-session the backstop is not running; if it is present but the shield
    /// is empty, the extension has cleared it.
    var activeSchedules: [String] {
        #if canImport(FamilyControls)
        center.activities.map(\.rawValue)
        #else
        []
        #endif
    }

    var authorizationDescription: String {
        #if canImport(FamilyControls)
        return "\(AuthorizationCenter.shared.authorizationStatus)"
        #else
        return "unsupported"
        #endif
    }

    var selectionCounts: String {
        #if canImport(FamilyControls)
        return "\(selection.applicationTokens.count) apps · \(selection.categoryTokens.count) cats · \(selection.webDomainTokens.count) web"
        #else
        return "unsupported"
        #endif
    }

    /// Whether the tokens survive a trip through the App Group store — the
    /// thing the monitor extension depends on, and the thing the recurring
    /// CFPrefs complaint would break.
    var groupRoundTrip: String {
        #if canImport(FamilyControls)
        guard let data = LockedShared.defaults.data(forKey: LockedShared.selectionKey) else {
            return "nothing stored"
        }
        guard let restored = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) else {
            return "stored but won't decode (\(data.count) bytes)"
        }
        let n = restored.applicationTokens.count + restored.categoryTokens.count
        return n == selectedCount ? "ok (\(n))" : "MISMATCH: group \(n) vs live \(selectedCount)"
        #else
        return "unsupported"
        #endif
    }

    private func refreshState() {
        #if canImport(FamilyControls)
        let status = AuthorizationCenter.shared.authorizationStatus
        switch status {
        case .notDetermined:
            state = .needsPermission
        case .denied:
            state = .denied
        case .approved:
            state = selectedCount == 0 ? .noSelection : .ready
        default:
            // iOS 26.4 added `.approvedWithDataAccess`, which is also authorized.
            if #available(iOS 26.4, *), status == .approvedWithDataAccess {
                state = selectedCount == 0 ? .noSelection : .ready
            } else {
                state = .needsPermission
            }
        }
        #else
        state = .unsupported
        #endif
    }

    #if canImport(FamilyControls)
    private func persistSelection() {
        guard let data = try? JSONEncoder().encode(selection) else { return }
        // The app group, not standard defaults — the monitor extension reads this.
        LockedShared.defaults.set(data, forKey: LockedShared.selectionKey)
    }

    private func restoreSelection() {
        guard let data = LockedShared.defaults.data(forKey: LockedShared.selectionKey),
              let restored = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return }
        selection = restored
    }
    #endif
}

// MARK: - Picker

/// Opens Apple's own app picker when Screen Time access exists. The picker is
/// the only way to get app tokens — apps can never see the user's app list.
struct RealAppPicker: View {
    @EnvironmentObject private var shield: ShieldManager
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                Haptics.tap()
                if shield.state == .needsPermission || shield.state == .denied {
                    Task { await shield.requestAuthorization() }
                } else {
                    showPicker = true
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: shield.state.isReal ? "lock.shield.fill" : "lock.shield")
                        .font(.system(size: 15))
                    Text(buttonTitle)
                        .font(.display(15, .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Ink.paper(0.3))
                }
                .foregroundStyle(Ink.goldType)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .goldGlass(18, fill: 0.16, border: 0.4)
            }
            .pressable()
            .disabled(!shield.isAvailable)

            Text(footnote)
                .font(.ui(11.5))
                .foregroundStyle(Ink.paper(0.38))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        #if canImport(FamilyControls)
        .familyActivityPicker(isPresented: $showPicker, selection: $shield.selection)
        #endif
    }

    private var buttonTitle: String {
        switch shield.state {
        case .ready: return "\(shield.selectedCount) app\(shield.selectedCount == 1 ? "" : "s") really blocked"
        case .noSelection: return "Pick the real apps to block"
        case .needsPermission, .denied: return "Turn on real blocking"
        case .unsupported: return "Real blocking unavailable"
        }
    }

    private var footnote: String {
        switch shield.state {
        case .ready:
            return "iOS enforces this. Your pod sees the count, never the names — apps are never told which apps you picked."
        case .noSelection:
            return "Screen Time access granted. Pick the apps iOS should seal off."
        case .needsPermission:
            return "Needs Apple’s Family Controls entitlement on this build. Until it lands, a session runs on the honour system — the timer, the pod and the stakes are real, the block is not."
        case .denied:
            return "Screen Time access was declined. Re-enable it in Settings › Screen Time to make the lock real."
        case .unsupported:
            return "This build can't reach the Screen Time frameworks."
        }
    }
}

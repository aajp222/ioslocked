import SwiftUI

@main
@MainActor
struct LockedApp: App {
    /// APNs tokens and notification taps only arrive through UIKit.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var shield: ShieldManager
    @StateObject private var state: AppState

    init() {
        // One shield, shared: the store arms and lifts it, the UI reads its state.
        //
        // To go multiplayer, swap the service here:
        //   AppState(service: RemotePodService(base: url, token: token), shield: shield)
        let shield = ShieldManager()
        _shield = StateObject(wrappedValue: shield)
        _state = StateObject(wrappedValue: AppState(shield: shield))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .environmentObject(shield)
                .preferredColorScheme(.dark)
                .tint(Ink.gold)
                .task {
                    // So a notification response can reach the store, even when
                    // the tap is what launched the app.
                    AppDelegate.state = state
                    Notifier.registerForRemoteNotifications()
                }
        }
    }
}

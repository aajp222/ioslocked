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
                .onOpenURL { url in
                    // Only invite links so far. A link never acts on its own —
                    // it puts the code up for confirmation. Anything we do not
                    // recognise opens the app and does nothing, which is the
                    // right outcome for a scheme anyone can construct.
                    guard let code = InviteLink.code(from: url) else { return }
                    state.receiveInvite(code)
                }
        }
    }
}

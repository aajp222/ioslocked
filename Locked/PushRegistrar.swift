import SwiftUI
import UIKit
import UserNotifications

/// The app had no delegate — SwiftUI's `App` doesn't need one — but APNs device
/// tokens and notification responses are only delivered through UIKit, so here
/// is the smallest possible one.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by `LockedApp` at launch so a notification can reach the store even
    /// when the tap is what launched the app.
    @MainActor static weak var state: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Notifier.registerCategories()
        return true
    }

    // MARK: Device token

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            AppDelegate.state?.registerPushToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Simulators without a paired push service land here; the app falls back
        // to polling and everything still works.
        print("[push] registration failed: \(error.localizedDescription)")
    }

    // MARK: Responses

    /// Show pod notifications even with the app open — they're time-critical.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// A tap, or one of the Give 5 min / Absolutely not buttons.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier
        await MainActor.run {
            AppDelegate.state?.handlePush(userInfo: info, action: action)
        }
    }
}

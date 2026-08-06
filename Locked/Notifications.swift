import Foundation
import UIKit
import UserNotifications

/// Local notifications, plus the categories and registration that make the
/// server's pushes actionable. The pod's real pushes come from
/// `server/apns.py`; this file decides what their buttons do.
enum Notifier {
    private static let sessionEndID = "locked.session.end"

    /// Must match `apns.CATEGORY_UNLOCK` on the server.
    static let unlockCategory = "unlock-request"
    static let approveAction = "unlock.approve"
    static let denyAction = "unlock.deny"

    /// Registers the Give 5 min / Absolutely not buttons. No
    /// `authenticationRequired`, deliberately: ruling on someone else's request
    /// should work straight from the Lock Screen without unlocking the phone.
    static func registerCategories() {
        let deny = UNNotificationAction(
            identifier: denyAction,
            title: "Absolutely not",
            options: [.destructive]
        )
        let approve = UNNotificationAction(
            identifier: approveAction,
            title: "Give 5 min",
            options: []
        )
        let unlock = UNNotificationCategory(
            identifier: unlockCategory,
            actions: [deny, approve],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([unlock])
    }

    static func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            if granted { await registerForRemoteNotifications() }
            return granted
        } catch {
            return false
        }
    }

    /// Ask APNs for a device token. Safe to call on every launch — the token can
    /// change, and the delegate uploads whatever comes back.
    @MainActor
    static func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Which APNs host the server must use for the tokens this build produces.
    static var pushEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    static func settingsAllow() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized
    }

    /// One notification at the exact moment the phone unlocks itself.
    static func scheduleSessionEnd(at date: Date, goal: String) {
        cancelSessionEnd()
        let interval = date.timeIntervalSinceNow
        guard interval > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time served."
        content.body = "\(goal) — the phone is yours again."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: sessionEndID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelSessionEnd() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [sessionEndID])
    }

    /// Fire-and-forget, a couple of seconds out so it lands like a real push.
    static func nudge(title: String, body: String, after seconds: TimeInterval = 1) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(0.5, seconds), repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }
}

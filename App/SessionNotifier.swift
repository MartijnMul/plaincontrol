import Foundation
import PlaincontrolCore
import UserNotifications
import os

/// Shows a notification when a session starts waiting for the user or finishes a turn.
///
/// Each session has at most one notification, identified by its session ID: a newer one
/// replaces it, and it is withdrawn once the session works again or ends. Notifications wait
/// ``SessionAlert/gracePeriod`` before they show, so a change in the meantime cancels them.
@MainActor
final class SessionNotifier: NSObject {
    private let center = UNUserNotificationCenter.current()
    /// Called with the session ID when the user clicks a notification.
    var onOpen: ((String) -> Void)?

    func start() {
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func handle(_ change: StatusChange, of session: Session) {
        let id = change.sessionID
        center.removePendingNotificationRequests(withIdentifiers: [id])
        if change.withdrawsShownAlert {
            center.removeDeliveredNotifications(withIdentifiers: [id])
        }
        guard let alert = SessionAlert(for: change) else { return }

        let content = UNMutableNotificationContent()
        content.title = session.displayName
        content.body = alert.message
        content.threadIdentifier = id
        content.userInfo = ["sessionID": id]
        if case .waiting = alert {
            content.sound = .default
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: SessionAlert.gracePeriod, repeats: false)
        // The completion-handler form keeps requests in call order with the removals above.
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)) { _ in }
    }
}

extension SessionNotifier: UNUserNotificationCenterDelegate {
    /// Shows notifications as banners even while the app's menu is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Opens the session when the user clicks its notification.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let sessionID = response.notification.request.content.userInfo["sessionID"] as? String
        else { return }
        Logger(subsystem: AppInfo.subsystem, category: "notifications")
            .info("Opened the notification of session \(sessionID, privacy: .public)")
        await MainActor.run { onOpen?(sessionID) }
    }
}

extension SessionAlert {
    var message: String {
        switch self {
        case .waiting(.permission): "Needs your permission"
        case .waiting(.question): "Has a question for you"
        case .waiting(.planApproval): "Has a plan for you to review"
        case .waiting(.input): "Needs your input"
        case .finished: "Finished"
        }
    }
}

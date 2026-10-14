import Foundation
import PlaincontrolCore
import UserNotifications

/// Shows a notification when a session starts waiting for the user or finishes a turn.
///
/// Each session has at most one notification, identified by its session ID: a newer one
/// replaces it, and it is withdrawn once the session works again or ends. Notifications wait
/// ``SessionAlert/gracePeriod`` before they show, so a change in the meantime cancels them.
@MainActor
final class SessionNotifier: NSObject {
    private let center = UNUserNotificationCenter.current()

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

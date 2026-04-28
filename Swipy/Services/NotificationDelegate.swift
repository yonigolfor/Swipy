//
//  NotificationDelegate.swift
//  Swipy

import UserNotifications

class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    private override init() {}

    func setupInApp() {
        UNUserNotificationCenter.current().delegate = self
    }

    // Show banner even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    // Handle tap on notification or action button
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let action = response.actionIdentifier

        switch action {
        case NotificationManager.deleteAllAction:
            navigateTo(destination: "reviewBin")
            NotificationCenter.default.post(name: .notificationDeleteAll, object: nil)

        case NotificationManager.sortNowAction:
            navigateTo(destination: "swipe")

        default: // cleanNowAction or banner tap
            let destination = info["destination"] as? String ?? "swipe"
            navigateTo(destination: destination)
        }

        completionHandler()
    }

    private func navigateTo(destination: String) {
        let tab: Int
        switch destination {
        case "filters":    tab = 0
        case "reviewBin":  tab = 2
        default:           tab = 1
        }
        NotificationCenter.default.post(name: .notificationNavigate, object: tab)
    }
}

extension Notification.Name {
    static let notificationNavigate  = Notification.Name("notificationNavigate")
    static let notificationDeleteAll = Notification.Name("notificationDeleteAll")
}

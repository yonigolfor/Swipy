//
//  NotificationManager.swift
//  Swipy

import UserNotifications
import Photos
import UIKit

class NotificationManager {
    static let shared = NotificationManager()

    // Category identifiers
    static let reviewBinCategory      = "REVIEW_BIN"
    static let photoBurstCategory     = "PHOTO_BURST"
    static let milestoneCategory      = "MILESTONE"
    static let weeklyCategory         = "WEEKLY_CLEANUP"
    static let inactivityCategory     = "INACTIVITY"
    static let swipeLimitResetCategory = "SWIPE_LIMIT_RESET"

    // Action identifiers
    static let cleanNowAction  = "CLEAN_NOW"
    static let deleteAllAction = "DELETE_ALL"
    static let sortNowAction   = "SORT_NOW"

    // Notification identifiers
    static let reviewBinNotif       = "com.swipy.reviewBinReminder"
    static let photoBurstNotif      = "com.swipy.photoBurst"
    static let milestoneNotif       = "com.swipy.milestone"
    static let weeklyNotif          = "com.swipy.weeklyCleanup"
    static let inactivityNotif      = "com.swipy.inactivity"
    static let swipeLimitResetNotif = "com.swipy.swipeLimitReset"

    private init() {}

    // MARK: - Authorization

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, _ in
            DispatchQueue.main.async {
                if granted { self.registerCategories() }
                completion(granted)
            }
        }
    }

    private func registerCategories() {
        let cleanNow = UNNotificationAction(
            identifier: Self.cleanNowAction,
            title: String(localized: "notif.action.cleanNow"),
            options: [.foreground]
        )
        let deleteAll = UNNotificationAction(
            identifier: Self.deleteAllAction,
            title: String(localized: "notif.action.deleteAll"),
            options: [.destructive, .foreground]
        )
        let sortNow = UNNotificationAction(
            identifier: Self.sortNowAction,
            title: String(localized: "notif.action.sortNow"),
            options: [.foreground]
        )

        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: Self.reviewBinCategory,
                                   actions: [cleanNow, deleteAll],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.photoBurstCategory,
                                   actions: [sortNow],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.milestoneCategory,
                                   actions: [cleanNow],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.weeklyCategory,
                                   actions: [sortNow],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.inactivityCategory,
                                   actions: [sortNow],
                                   intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.swipeLimitResetCategory,
                                   actions: [sortNow],
                                   intentIdentifiers: [])
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    // MARK: - Review Bin Reminder

    func scheduleReviewBinReminder(itemCount: Int, spaceSavedBytes: Int64) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notif.reviewBin.title")
        content.body = String(format: String(localized: "notif.reviewBin.body"), formatBytes(spaceSavedBytes))
        content.categoryIdentifier = Self.reviewBinCategory
        content.sound = .default
        content.userInfo = ["destination": "reviewBin", "itemCount": itemCount]

        schedule(identifier: Self.reviewBinNotif, content: content, delay: 24 * 3600)
        UserDefaults.standard.set(Date(), forKey: "lastReviewBinNotifScheduled")
    }

    // MARK: - Photo Burst

    func schedulePhotoBurstNotification(newPhotoCount: Int, latestAsset: PHAsset?) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notif.burst.title")
        content.body = String(format: String(localized: "notif.burst.body"), newPhotoCount)
        content.categoryIdentifier = Self.photoBurstCategory
        content.sound = .default
        content.userInfo = ["destination": "swipe", "photoCount": newPhotoCount]

        if let asset = latestAsset {
            attachThumbnail(from: asset, to: content) { self.schedule(identifier: Self.photoBurstNotif, content: $0, delay: 3600) }
        } else {
            schedule(identifier: Self.photoBurstNotif, content: content, delay: 3600)
        }
        UserDefaults.standard.set(Date(), forKey: "lastPhotoBurstNotifDate")
    }

    // MARK: - Milestone

    func scheduleMilestoneNotification(gbSaved: Int) {
        let content = UNMutableNotificationContent()
        content.title = String(format: String(localized: "notif.milestone.title"), gbSaved)
        content.body = String(localized: "notif.milestone.body")
        content.categoryIdentifier = Self.milestoneCategory
        content.sound = .default
        content.userInfo = ["destination": "swipe", "gb": gbSaved]

        schedule(identifier: "\(Self.milestoneNotif).\(gbSaved)gb", content: content, delay: 1)
        UserDefaults.standard.set(gbSaved, forKey: "lastMilestoneNotifiedGB")
    }

    // MARK: - Swipe Limit Reset

    /// Schedules a notification for 00:01 of the next calendar day — when the daily limit resets.
    /// Only call when a free user has just exhausted their daily swipe allowance.
    /// Replaces any previously scheduled reset notification (same identifier = atomic swap).
    func scheduleSwipeLimitResetNotification() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notif.swipeLimitReset.title")
        content.body = String(localized: "notif.swipeLimitReset.body")
        content.categoryIdentifier = Self.swipeLimitResetCategory
        content.sound = .default
        content.userInfo = ["destination": "swipe"]

        // 00:01 next day — one minute after the daily counter resets at midnight.
        let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: nextDay)
        comps.hour = 0
        comps.minute = 1

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: Self.swipeLimitResetNotif, content: content, trigger: trigger)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.swipeLimitResetNotif])
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Weekly Cleanup

    func scheduleWeeklyCleanup() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notif.weekly.title")
        content.body = String(localized: "notif.weekly.body")
        content.categoryIdentifier = Self.weeklyCategory
        content.sound = .default
        content.userInfo = ["destination": "swipe"]

        var comps = DateComponents()
        comps.weekday = 1 // Sunday
        comps.hour = 21
        comps.minute = 30

        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: Self.weeklyNotif, content: content, trigger: trigger)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.weeklyNotif])
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Inactivity Reminder (72 h since last foreground)

    /// Cancel any pending inactivity notification and reschedule for 72 hours from now.
    /// Call every time the app enters foreground — effectively resets the clock.
    func rescheduleInactivityReminder() {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "notif.inactivity.title")
        content.body = String(localized: "notif.inactivity.body")
        content.categoryIdentifier = Self.inactivityCategory
        content.sound = .default
        content.userInfo = ["destination": "swipe"]

        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.inactivityNotif])
        schedule(identifier: Self.inactivityNotif, content: content, delay: 72 * 3600)
    }

    // MARK: - Helpers

    private func schedule(identifier: String, content: UNMutableNotificationContent, delay: TimeInterval) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(delay, 1), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().add(request)
    }

    private func attachThumbnail(from asset: PHAsset, to content: UNMutableNotificationContent, completion: @escaping (UNMutableNotificationContent) -> Void) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.isSynchronous = false

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 200, height: 200),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            if let data = image?.jpegData(compressionQuality: 0.7) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                try? data.write(to: url)
                if let attachment = try? UNNotificationAttachment(identifier: "photo", url: url, options: nil) {
                    content.attachments = [attachment]
                }
            }
            completion(content)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1fGB", gb) }
        let mb = Double(bytes) / 1_048_576
        if mb >= 1 { return String(format: "%.0fMB", mb) }
        return "\(bytes / 1024)KB"
    }
}

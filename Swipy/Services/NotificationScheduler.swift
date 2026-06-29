//
//  NotificationScheduler.swift
//  Swipy

import Foundation
import Photos
import BackgroundTasks
import UserNotifications

class NotificationScheduler {
    static let shared = NotificationScheduler()

    private let manager = NotificationManager.shared
    private let persistence = PersistenceService.shared
    private let bgTaskIdentifier = "com.swipy.notificationCheck"

    // Serial queue — all evaluation runs on this queue, never concurrently
    private let queue = DispatchQueue(label: "com.swipy.notificationScheduler")

    private init() {}

    // MARK: - Daily notification cap (max 2/day, thread-safe)

    private func currentDayCount() -> Int {
        let dateKey = "notifCapDate"
        let countKey = "notifCapCount"
        let today = Calendar.current.startOfDay(for: Date())
        if let stored = UserDefaults.standard.object(forKey: dateKey) as? Date,
           Calendar.current.isDate(stored, inSameDayAs: today) {
            return UserDefaults.standard.integer(forKey: countKey)
        }
        // New day — reset
        UserDefaults.standard.set(today, forKey: dateKey)
        UserDefaults.standard.set(0, forKey: countKey)
        return 0
    }

    private func incrementDayCount() {
        // Re-read from UserDefaults directly to avoid double-reset race in todayCount
        let count = UserDefaults.standard.integer(forKey: "notifCapCount")
        UserDefaults.standard.set(count + 1, forKey: "notifCapCount")
        UserDefaults.standard.set(Calendar.current.startOfDay(for: Date()), forKey: "notifCapDate")
    }

    // MARK: - Background Tasks

    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: bgTaskIdentifier, using: nil) { task in
            self.handleBackgroundTask(task as! BGAppRefreshTask)
        }
    }

    func scheduleBackgroundTask() {
        let request = BGAppRefreshTaskRequest(identifier: bgTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleBackgroundTask(_ task: BGAppRefreshTask) {
        scheduleBackgroundTask() // Reschedule immediately

        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        queue.async {
            self.runAllTriggers()
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: - Public entry point

    func evaluateAndScheduleNotifications() {
        queue.async { self.runAllTriggers() }
    }

    // MARK: - Private: run all triggers in order

    private func runAllTriggers() {
        checkReviewBinTrigger()
        checkPhotoBurstTrigger()
        checkMilestoneTrigger()
    }

    // MARK: - Trigger 1: Review Bin (fires 24h after items are left pending)

    private func checkReviewBinTrigger() {
        guard !persistence.reviewBinIDs.isEmpty else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [NotificationManager.reviewBinNotif])
            return
        }

        // If there's a pending notification that hasn't fired yet (scheduled < 24h ago),
        // replace it with fresh data. The same identifier means iOS atomically swaps
        // the pending one — not an additional notification, so no daily cap hit.
        let lastScheduled = UserDefaults.standard.object(forKey: "lastReviewBinNotifScheduled") as? Date
        let hasPendingNotif = lastScheduled.map { Date().timeIntervalSince($0) < 24 * 3600 } ?? false

        if !hasPendingNotif {
            guard currentDayCount() < 2 else { return }
        }

        manager.scheduleReviewBinReminder(
            itemCount: persistence.reviewBinIDs.count,
            spaceSavedBytes: persistence.reviewBinSpaceSaved
        )
        if !hasPendingNotif { incrementDayCount() }
    }

    // MARK: - Trigger 2: Photo Burst (50+ new photos since last check)

    private func checkPhotoBurstTrigger() {
        guard currentDayCount() < 2 else { return }

        // Cool-down: once per 24 h
        if let last = UserDefaults.standard.object(forKey: "lastPhotoBurstNotifDate") as? Date,
           Date().timeIntervalSince(last) < 24 * 3600 { return }

        let fetchOptions = PHFetchOptions()
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary]
        let current = PHAsset.fetchAssets(with: fetchOptions).count

        let previousKey = "lastKnownPhotoCount"

        // First run: baseline without notifying
        guard let previous = UserDefaults.standard.object(forKey: previousKey) as? Int else {
            UserDefaults.standard.set(current, forKey: previousKey)
            return
        }

        let diff = current - previous
        // Do NOT advance the baseline here — let diffs accumulate across background cycles
        // until they cross the threshold. Baseline only moves when a notification fires.
        guard diff >= 50 else { return }

        UserDefaults.standard.set(current, forKey: previousKey)

        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 1
        let latest = PHAsset.fetchAssets(with: opts).firstObject

        manager.schedulePhotoBurstNotification(newPhotoCount: diff, latestAsset: latest)
        incrementDayCount()
    }

    // MARK: - Trigger 3: Milestone — celebrate every new GB saved

    private func checkMilestoneTrigger() {
        guard currentDayCount() < 2 else { return }

        let gbSaved = Int(Double(persistence.totalSpaceSavedLifetime) / 1_073_741_824)
        guard gbSaved >= 1 else { return }

        let lastNotified = UserDefaults.standard.integer(forKey: "lastMilestoneNotifiedGB")
        guard gbSaved > lastNotified else { return }

        manager.scheduleMilestoneNotification(gbSaved: gbSaved)
        incrementDayCount()
    }

    // MARK: - Foreground session burst tracking

    /// Call when the app enters foreground — sets the baseline for this session.
    func resetBurstBaseline() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.includeAssetSourceTypes = [.typeUserLibrary]
        let count = PHAsset.fetchAssets(with: fetchOptions).count
        UserDefaults.standard.set(count, forKey: "burstSessionBaseCount")
        // Also keep lastKnownPhotoCount in sync for the background task path
        UserDefaults.standard.set(count, forKey: "lastKnownPhotoCount")
    }

    /// Call from PHPhotoLibraryChangeObserver when new photos are inserted.
    /// `insertedCount` = number of newly inserted assets in this change event.
    func checkBurstFromLibraryChange(insertedCount: Int) {
        guard insertedCount > 0 else { return }
        queue.async {
            guard self.currentDayCount() < 2 else { return }

            if let last = UserDefaults.standard.object(forKey: "lastPhotoBurstNotifDate") as? Date,
               Date().timeIntervalSince(last) < 24 * 3600 { return }

            let base = UserDefaults.standard.integer(forKey: "burstSessionBaseCount")
            let fetchOptions = PHFetchOptions()
            fetchOptions.includeAssetSourceTypes = [.typeUserLibrary]
            let current = PHAsset.fetchAssets(with: fetchOptions).count
            let diff = current - base

            guard diff >= 50 else { return }

            // Reset baseline so the next burst needs another 50 on top
            UserDefaults.standard.set(current, forKey: "burstSessionBaseCount")
            UserDefaults.standard.set(current, forKey: "lastKnownPhotoCount")

            let opts = PHFetchOptions()
            opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            opts.fetchLimit = 1
            let latest = PHAsset.fetchAssets(with: opts).firstObject

            self.manager.schedulePhotoBurstNotification(newPhotoCount: diff, latestAsset: latest)
            self.incrementDayCount()
        }
    }

    // MARK: - Weekly cleanup (called once; trigger repeats automatically)

    func scheduleWeeklyCleanupIfNeeded() {
        // V2 key forces reschedule for existing users who had the old Saturday 19:00 trigger.
        let key = "weeklyCleanupScheduledV2"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        manager.scheduleWeeklyCleanup()
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Cancel any pending inactivity notification and arm a new 72-hour one.
    /// Must be called every time the app enters foreground.
    func rescheduleInactivityReminder() {
        manager.rescheduleInactivityReminder()
    }
}

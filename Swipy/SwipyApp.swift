//
//  SwipyApp.swift
//  Swipy

import SwiftUI

@main
struct SwipyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SplashScreenView()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                NotificationScheduler.shared.resetBurstBaseline()
                NotificationScheduler.shared.evaluateAndScheduleNotifications()
                NotificationScheduler.shared.rescheduleInactivityReminder()
                NotificationScheduler.shared.rescheduleWeeklyCleanup()
            }
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Must register background tasks synchronously before returning true
        NotificationScheduler.shared.registerBackgroundTasks()

        NotificationDelegate.shared.setupInApp()

        return true
    }
}

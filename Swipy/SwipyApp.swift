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
                // Forced app-wide, not just for the onboarding/handoff transitions: on
                // an RTL device (Hebrew), iOS mirrors the entire root coordinate space,
                // which flips even raw-offset transitions (not just Edge.leading/.trailing-
                // based ones) — the only reliable fix is overriding layoutDirection at the
                // root. Hebrew text itself still renders correctly (Unicode bidi is
                // independent of this); only container layout (HStack ordering, transition
                // direction) is pinned to LTR everywhere, so "forward" always means right.
                .environment(\.layoutDirection, .leftToRight)
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

        // Touch PremiumManager.shared as early as possible so its async StoreKit 2
        // entitlement resolution races the whole launch pipeline (permission checks,
        // stack load) instead of racing the user's first swipe gesture. Without this,
        // the singleton's lazy init doesn't fire until the first canSwipe check.
        _ = PremiumManager.shared

        return true
    }
}

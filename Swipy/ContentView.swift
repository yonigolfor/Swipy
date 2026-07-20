//
//  ContentView.swift
//  CleanSwipe
//
//  המסך הראשי עם Tab Bar Navigation
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var stackViewModel: PhotoStackViewModel
    @StateObject private var photoService = PhotoLibraryService.shared

    @State private var selectedTab = 1

    var body: some View {
        TabView(selection: $selectedTab) {
            SmartFiltersView(selectedTab: $selectedTab)
                .environmentObject(stackViewModel)
                .tabItem {
                    Label(String(localized: "tab.filters"), systemImage: "line.3.horizontal.decrease.circle")
                }
                .tag(0)

            SwipeStackView(selectedTab: $selectedTab)
                .environmentObject(stackViewModel)
                .tabItem {
                    Label(String(localized: "tab.swipe"), systemImage: "rectangle.stack")
                }
                .tag(1)

            ReviewBinView()
                .environmentObject(stackViewModel)
                .tabItem {
                    Label(String(localized: "tab.review"), systemImage: "trash")
                }
                .badge(stackViewModel.reviewBin.count)
                .tag(2)
        }
        .onAppear {
            checkPhotoLibraryAuthorization()
            requestNotificationAuthorizationIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .notificationNavigate)) { note in
            if let tab = note.object as? Int {
                withAnimation { selectedTab = tab }
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    NotificationCenter.default.post(name: .resumeVideoObserver, object: nil)
                }
            } else {
                NotificationCenter.default.post(name: .stopCurrentVideo, object: nil)
            }
        }
    }

    private func checkPhotoLibraryAuthorization() {
        photoService.checkAuthorization()
    }

    /// Asked here (main screen, post-onboarding) rather than at cold launch — HIG discourages
    /// prompting for notification permission before the user has seen any app value.
    /// Safe to call on every appearance: requestAuthorization no-ops once the user has decided.
    private func requestNotificationAuthorizationIfNeeded() {
        NotificationManager.shared.requestAuthorization { granted in
            guard granted else { return }
            NotificationScheduler.shared.scheduleBackgroundTask()
            NotificationScheduler.shared.evaluateAndScheduleNotifications()
        }
    }
}

#Preview {
    ContentView(stackViewModel: PhotoStackViewModel())
}

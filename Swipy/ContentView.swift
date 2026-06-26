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
        .onAppear { checkPhotoLibraryAuthorization() }
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
}

#Preview {
    ContentView(stackViewModel: PhotoStackViewModel())
}

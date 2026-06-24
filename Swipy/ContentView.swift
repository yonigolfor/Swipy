//
//  ContentView.swift
//  CleanSwipe
//
//  המסך הראשי עם Tab Bar Navigation
//

import SwiftUI
import Photos

struct ContentView: View {
    @ObservedObject var stackViewModel: PhotoStackViewModel
    @StateObject private var photoService = PhotoLibraryService.shared
    
    @State private var selectedTab = 1
    // Height reserved at the bottom of SwipeStackView's card area so cards never
    // overlap the tab bar. Computed on appear: bar visual height + device safe area.
    @State private var tabBarReservedHeight: CGFloat = 90
    
    var body: some View {
        mainTabView
            .onAppear {
                checkPhotoLibraryAuthorization()
                // Measure device bottom safe area (home indicator) at appear time,
                // then add the tab bar's visual content height (~58pt: icons+labels+padding).
                let bottomInset = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .first?.windows.first(where: \.isKeyWindow)?.safeAreaInsets.bottom ?? 0
                tabBarReservedHeight = 58 + bottomInset
            }
            .onReceive(NotificationCenter.default.publisher(for: .notificationNavigate)) { note in
                if let tab = note.object as? Int {
                    withAnimation { selectedTab = tab }
                }
            }
    }
    
    // MARK: - Main Tab View

    private var mainTabView: some View {
        // .safeAreaInset renders GlassmorphicTabBar as a floating bottom overlay.
        // SwipeStackView also receives tabBarReservedHeight so its card column stops
        // above the bar on every device. scaleEffect during pinch-zoom overflows the
        // layout frame visually, so the zoomed card covers the whole screen.
        TabView(selection: $selectedTab) {
            SmartFiltersView(selectedTab: $selectedTab)
                .environmentObject(stackViewModel)
                .tag(0)

            SwipeStackView(selectedTab: $selectedTab, tabBarReservedHeight: tabBarReservedHeight)
                .environmentObject(stackViewModel)
                .tag(1)

            ReviewBinView()
                .environmentObject(stackViewModel)
                .tag(2)
        }
        .ignoresSafeArea()
        .onAppear { UITabBar.appearance().isHidden = true }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlassmorphicTabBar(
                selectedTab: $selectedTab,
                reviewBinCount: stackViewModel.reviewBin.count
            )
            .opacity(stackViewModel.isCardZooming ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: stackViewModel.isCardZooming)
            .padding(.bottom, 8)
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

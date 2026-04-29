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
    
    var body: some View {
        mainTabView
            .onAppear {
                checkPhotoLibraryAuthorization()
            }
            .onReceive(NotificationCenter.default.publisher(for: .notificationNavigate)) { note in
                if let tab = note.object as? Int {
                    withAnimation { selectedTab = tab }
                }
            }
    }
    
    // MARK: - Main Tab View
    
    private var mainTabView: some View {
        VStack(alignment: .center) {
            TabView(selection: $selectedTab) {
                SmartFiltersView(selectedTab: $selectedTab)
                    .environmentObject(stackViewModel)
                    .tag(0)

                SwipeStackView(selectedTab: $selectedTab)
                    .environmentObject(stackViewModel)
                    .tag(1)

                ReviewBinView()
                    .environmentObject(stackViewModel)
                    .tag(2)
            }
            .ignoresSafeArea()
            .onAppear {
                UITabBar.appearance().isHidden = true
            }
            
            GlassmorphicTabBar(
                selectedTab: $selectedTab,
                reviewBinCount: stackViewModel.reviewBin.count
            )
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

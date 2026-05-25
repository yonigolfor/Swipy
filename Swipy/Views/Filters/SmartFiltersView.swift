//
//  SmartFiltersView.swift
//  CleanSwipe
//
//  מסך Smart Filters - "Easy Targets"
//

import SwiftUI

struct SmartFiltersView: View {
    @EnvironmentObject var stackViewModel: PhotoStackViewModel
    @Binding var selectedTab: Int
    #if DEBUG
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("shakeHintSwipeCount") private var shakeHintSwipeCount = 0
    @AppStorage("hasSeenShakeHint") private var hasSeenShakeHint = false
    #endif

    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(FilterCategory.allCases) { category in
                        if (category != .blurryPhotos){
                            filterRow(for: category)
                        }
                    }
                } header: {
                                    Text(String(localized: "filters.section_header"))
                                } footer: {
                                    Text(String(localized: "filters.section_footer"))
                                }
            }
            .navigationTitle(String(localized: "filters.title"))
            .navigationBarTitleDisplayMode(.large)
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        hasCompletedOnboarding = false
                        shakeHintSwipeCount = 0
                        hasSeenShakeHint = false
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.orange)
                    }
                }
            }
            #endif
            .task {
                // .task is lifecycle-aware: it cancels automatically if the
                // user leaves the screen before counting finishes.
                // Only runs if counts have never been loaded.
                if stackViewModel.categoryCounts.isEmpty {
                    stackViewModel.refreshCategoryCounts()
                }
            }
            .refreshable {
                stackViewModel.refreshCategoryCounts()
            }
        }
    }
    
    // MARK: - Filter Row
    
    private func filterRow(for category: FilterCategory) -> some View {
        let count = stackViewModel.categoryCounts[category] ?? 0
        let isEmpty = stackViewModel.categoryCounts[category] != nil && count == 0

        return Button {
            guard !isEmpty else { return }
            stackViewModel.loadPhotos(filter: category)
            selectedTab = 1
        } label: {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(category.color.opacity(0.15))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: category.icon)
                        .font(.title3)
                        .foregroundColor(category.color)
                }
                
                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(category.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Count badge
                let cachedCount = stackViewModel.categoryCounts[category]
                let isRecalculating = category == .largeVideos && stackViewModel.isCountingLargeVideos

                if cachedCount == nil {
                    // No data at all yet — show full shimmer placeholder.
                    ShimmerView()
                } else if let count = cachedCount {
                    HStack(spacing: 6) {
                        if count > 0 {
                            Text(count >= 100 && category != .all ? "99+" : "\(count)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(category.color))
                                .contentTransition(.numericText())
                                // Dim while Phase 2 is verifying — shows stale value
                                // is present but being refreshed.
                                .opacity(isRecalculating ? 0.5 : 1.0)
                        } else {
                            Text(String(localized: "filters.empty"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        // Subtle spinner while Phase 2 runs in background.
                        if isRecalculating {
                            ProgressView()
                                .scaleEffect(0.65)
                        }
                    }
                }

                // Chevron — hidden when empty
                if (stackViewModel.categoryCounts[category] ?? 0) > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 8)
            .opacity((stackViewModel.categoryCounts[category] == 0 && stackViewModel.categoryCounts[category] != nil) ? 0.4 : 1.0)
        }
    }
    

}

/// A horizontal shimmer animation used as a placeholder while
/// expensive counts are being calculated in the background.
struct ShimmerView: View {
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.secondary.opacity(0.2),
                            Color.secondary.opacity(0.5),
                            Color.secondary.opacity(0.2)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(x: geo.size.width * phase)
                .animation(
                    .linear(duration: 1.2).repeatForever(autoreverses: false),
                    value: phase
                )
                .onAppear { phase = 1 }
        }
        .frame(width: 48, height: 16)
        .clipShape(Capsule())
    }
}

#Preview {
    SmartFiltersView(selectedTab: .constant(1))
        .environmentObject(PhotoStackViewModel())
}

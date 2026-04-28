//
//  ReviewBinView.swift
//  CleanSwipe
//
//  מסך Review Bin עם גריד של תמונות
//

import SwiftUI
import Photos
import AVKit

struct ReviewBinView: View {
    @EnvironmentObject var stackViewModel: PhotoStackViewModel
    @StateObject private var viewModel = ReviewBinViewModel()

    // Celebration state
    @State private var celebrationSpace: String? = nil
    @State private var celebrationCount: Int = 0

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationView {
            ZStack {
                // ── Content ──────────────────────────────────────────────
                VStack(spacing: 0) {
                    if stackViewModel.reviewBin.isEmpty {
    LifetimeSavingsView(text: stackViewModel.lifetimeSpaceSavedText)
        .padding(.top, 20)
} else {
    DopamineMeter(
        spaceSaved: stackViewModel.spaceSavedText,
        itemCount: stackViewModel.reviewBin.count
    )
    .padding(.top, 8)
}

                    if stackViewModel.reviewBin.isEmpty {
                        EmptyStateView.emptyBin
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(stackViewModel.reviewBin) { item in
                                    ReviewGridItemView(item: item)
                                        .onTapGesture {
                                            viewModel.selectItem(item)
                                        }
                                        .contextMenu {
                                            Button {
                                                stackViewModel.restoreFromBin(item)
                                            } label: {
                                                Label(String(localized: "bin.restore"), systemImage: "arrow.uturn.backward")
                                            }
                                        }
                                }
                            }
                            .padding()
                        }
                    }
                }

                // ── Celebration overlay ───────────────────────────────────
                if let spaceSaved = celebrationSpace {
                    TrashCelebrationView(
                        spaceSaved: spaceSaved,
                        itemCount: celebrationCount,
                        onDismiss: { celebrationSpace = nil }
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .navigationTitle(String(localized: "bin.title"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if !stackViewModel.reviewBin.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            viewModel.showDeleteConfirmation()
                        } label: {
                            Label(String(localized: "bin.empty_trash"), systemImage: "trash")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .alert(String(localized: "bin.alert_title"), isPresented: $viewModel.isShowingDeleteConfirmation) {
                            Button(String(localized: "cancel"), role: .cancel) {}
                            Button(String(format: String(localized: "bin.delete_button"), stackViewModel.reviewBin.count), role: .destructive) {
                    // Capture BEFORE emptyTrash zeroes it out
                    let savedText  = stackViewModel.spaceSavedText
                    let savedCount = stackViewModel.reviewBin.count
                    Task {
                        try? await stackViewModel.emptyTrash()
                        // Show celebration with the captured values
                        withAnimation {
                            celebrationCount = savedCount
                            celebrationSpace = savedText
                        }
                    }
                }
            } message: {
                Text(String(format: String(localized: "bin.alert_message"), stackViewModel.reviewBin.count))
            }
            .fullScreenCover(item: $viewModel.selectedItem) { item in
                FullScreenMediaView(
                    item: item,
                    onClose: { viewModel.deselectItem() },
                    onRestore: {
                        stackViewModel.restoreFromBin(item)
                        viewModel.deselectItem()
                    }
                )
            }
        }
    }

    // MARK: - Lifetime Savings View

    private var lifetimeSavingsView: some View {
        VStack(spacing: 8) {
            Text("Total Storage Freed")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundColor(.blue)

                Text(stackViewModel.lifetimeSpaceSavedText)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
    }
}

// MARK: - Full-screen media viewer (image or video)

struct FullScreenMediaView: View {
    let item: PhotoItem
    let onClose: () -> Void
    let onRestore: () -> Void

    @State private var image: UIImage?
    @State private var player: AVPlayer?
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if item.isVideo {
                if let player = player {
                    VideoPlayer(player: player)
                        .ignoresSafeArea()
                } else if isLoading {
                    ProgressView().tint(.white)
                }
            } else {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .ignoresSafeArea()
                } else if isLoading {
                    ProgressView().tint(.white)
                }
            }

            // Toolbar overlay
            VStack {
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white, .white.opacity(0.3))
                    }
                    .padding()

                    Spacer()

                    Button(action: onRestore) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.uturn.backward")
                            Text(String(localized: "bin.restore"))
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white.opacity(0.25)))
                    }
                    .padding()
                }
                Spacer()
            }
        }
        .onAppear { load() }
        .onDisappear { player?.pause() }
    }

    private func load() {
        if item.isVideo {
            let options = PHVideoRequestOptions()
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestPlayerItem(forVideo: item.asset, options: options) { playerItem, _ in
                guard let playerItem = playerItem else {
                    DispatchQueue.main.async { isLoading = false }
                    return
                }
                DispatchQueue.main.async {
                    self.player = AVPlayer(playerItem: playerItem)
                    self.player?.play()
                    self.isLoading = false
                }
            }
        } else {
            PhotoLibraryService.shared.loadImage(
                for: item.asset,
                targetSize: PHImageManagerMaximumSize
            ) { loaded in
                withAnimation { self.image = loaded; self.isLoading = false }
            }
        }
    }
}

#Preview {
    ReviewBinView()
        .environmentObject(PhotoStackViewModel())
}

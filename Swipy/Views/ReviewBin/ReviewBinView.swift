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

    // Restore animation — set to the item ID being restored so the matching
    // cell can run its poof animation before the data is removed.
    @State private var restoringItemID: String? = nil

    // Layout constants — single source of truth for both the grid and pre-caching.
    // GridItem spacing must be explicit so thumbnailPixelSize stays pixel-exact.
    private static let columnSpacing: CGFloat = 8
    private static let horizontalPadding: CGFloat = 16

    /// Pixel size used for both startCachingImages and loadThumbnail.
    /// Identical values guarantee a PHCachingImageManager cache hit on every cell render.
    static var thumbnailPixelSize: CGSize {
        let ptW = (UIScreen.main.bounds.width
                   - 2 * horizontalPadding
                   - 2 * columnSpacing) / 3
        let scale = UIScreen.main.scale
        return CGSize(width: ptW * scale, height: ptW * 0.75 * scale)
    }

    private let columns = [
        GridItem(.flexible(), spacing: columnSpacing),
        GridItem(.flexible(), spacing: columnSpacing),
        GridItem(.flexible(), spacing: columnSpacing)
    ]

    var body: some View {
        NavigationStack {
            contentView
                .toolbar {
                    if !stackViewModel.reviewBin.isEmpty {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button { viewModel.showDeleteConfirmation() } label: {
                                Label(String(localized: "bin.empty_trash"), systemImage: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .alert(String(localized: "bin.alert_title"), isPresented: $viewModel.isShowingDeleteConfirmation) {
                    Button(String(localized: "cancel"), role: .cancel) {}
                    Button(String(format: String(localized: "bin.delete_button"), stackViewModel.reviewBin.count), role: .destructive) {
                        let savedText  = stackViewModel.spaceSavedText
                        let savedCount = stackViewModel.reviewBin.count
                        Task {
                            do {
                                try await stackViewModel.emptyTrash()
                                withAnimation {
                                    celebrationCount = savedCount
                                    celebrationSpace = savedText
                                }
                            } catch {}
                        }
                    }
                } message: {
                    Text(String(format: String(localized: "bin.alert_message"), stackViewModel.reviewBin.count))
                }
                .fullScreenCover(item: $viewModel.selectedMedia) { media in
                    FullScreenMediaView(
                        item: media.item,
                        thumbnail: media.thumbnail,
                        onClose: { viewModel.deselectItem() },
                        onRestore: {
                            let id = media.item.id
                            viewModel.deselectItem()
                            Task { @MainActor in
                                // Wait for fullScreenCover dismiss (~420ms) before
                                // triggering the poof on the matching grid cell.
                                try? await Task.sleep(for: .milliseconds(420))
                                restoringItemID = id
                            }
                        }
                    )
                }
                .overlay {
                    if let spaceSaved = celebrationSpace {
                        TrashCelebrationView(
                            spaceSaved: spaceSaved,
                            itemCount: celebrationCount,
                            onDismiss: { celebrationSpace = nil }
                        )
                        .transition(.opacity)
                    }
                }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
        if stackViewModel.reviewBin.isEmpty {
            VStack(spacing: 0) {
                LifetimeSavingsView(text: stackViewModel.lifetimeSpaceSavedText)
                    .padding(.top, 20)
                EmptyStateView.emptyBin
            }
            .navigationTitle(String(localized: "bin.title"))
            .navigationBarTitleDisplayMode(.large)
        } else {
            ScrollView {
                DopamineMeter(
                    spaceSaved: stackViewModel.spaceSavedText,
                    itemCount: stackViewModel.reviewBin.count
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(stackViewModel.reviewBin) { item in
                        ReviewGridItemView(
                            item: item,
                            thumbnailPixelSize: Self.thumbnailPixelSize,
                            onRestore: {
                                restoringItemID = nil
                                stackViewModel.restoreFromBin(item)
                            },
                            onTap: { thumbnail in viewModel.selectItem(item, thumbnail: thumbnail) },
                            isBeingRestored: restoringItemID == item.id
                        )
                    }
                }
                .padding()
            }
            .navigationTitle(String(localized: "bin.title"))
            .navigationBarTitleDisplayMode(.large)
            .onAppear { startCachingBin() }
            .onDisappear { PhotoLibraryService.shared.stopCachingAllImages() }
            .onChange(of: stackViewModel.reviewBin.count) { startCachingBin() }
        }
    }

    // MARK: - Pre-caching

    /// Pre-warms PHCachingImageManager for every item in the bin so cells render
    /// near-instantly as they scroll into view. Idempotent — PHKit skips already-cached assets.
    private func startCachingBin() {
        PhotoLibraryService.shared.startCaching(for: stackViewModel.reviewBin,
                                                targetSize: Self.thumbnailPixelSize)
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

    /// Seeded from the grid cell's already-decoded thumbnail (see init) so this view
    /// never opens on a blank black screen — it shows that immediately, then `load()`
    /// silently upgrades it to a screen-resolution image. Doubles as the video poster
    /// frame while the AVPlayer is still preparing.
    @State private var image: UIImage?
    @State private var player: AVPlayer?

    init(item: PhotoItem, thumbnail: UIImage?, onClose: @escaping () -> Void, onRestore: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        self.onRestore = onRestore
        _image = State(initialValue: thumbnail)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if item.isVideo, let player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .ignoresSafeArea()
                if item.isVideo {
                    // Poster frame is up; player is still preparing behind it.
                    ProgressView().tint(.white)
                }
            } else {
                ProgressView().tint(.white)
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
                guard let playerItem else { return }
                DispatchQueue.main.async {
                    self.player = AVPlayer(playerItem: playerItem)
                    self.player?.play()
                }
            }
        } else {
            // Screen-resolution target, not PHImageManagerMaximumSize — a 12MP+ original
            // takes multiple seconds to decode for a view nobody can zoom into. Opportunistic
            // delivery lands a fast frame almost immediately, upgrading in place; the initial
            // thumbnail placeholder means there's nothing to wait on regardless.
            let scale = UIScreen.main.scale
            let targetSize = CGSize(
                width: UIScreen.main.bounds.width * scale,
                height: UIScreen.main.bounds.height * scale
            )
            PhotoLibraryService.shared.loadFullScreenImage(for: item.asset, targetSize: targetSize) { loaded in
                withAnimation(.easeInOut(duration: 0.2)) { self.image = loaded }
            }
        }
    }
}

#Preview {
    ReviewBinView()
        .environmentObject(PhotoStackViewModel())
}

//
//  PhotoCardView.swift
//  CleanSwipe
//
//  קלף בודד עם תמונה / וידאו מתנגן
//

import SwiftUI
import Photos
import AVKit

extension Notification.Name {
    static let stopCurrentVideo = Notification.Name("stopCurrentVideo")
    static let resumeVideoObserver = Notification.Name("resumeVideoObserver")
    /// Posted by SwipeStackView when a drag gesture is cancelled (card returns to centre).
    /// Top-card video players re-sync play state in response.
    static let resumeTopCardVideo = Notification.Name("resumeTopCardVideo")
}

struct PhotoCardView: View {
    let item: PhotoItem
    let isTopCard: Bool
    static var globalMute = false

    @State private var image: UIImage?
    @State private var isLoading: Bool
    @State private var player: AVPlayer?
    @State private var isMuted = false

    // Thumbnail Gate state
    /// Low-res placeholder shown immediately while full-res / AVPlayer loads.
    @State private var thumbnailImage: UIImage?
    /// True once the AVPlayer has had 50 ms to render its first frame.
    /// Thumbnail is visible until this flips.
    @State private var isVideoPlayerReady = false

    /// Pass a pre-loaded image from the ViewModel cache to display it instantly,
    /// skipping the async load path entirely and preventing any ProgressView flash.
    init(item: PhotoItem, isTopCard: Bool, cachedImage: UIImage? = nil) {
        self.item = item
        self.isTopCard = isTopCard
        _image = State(initialValue: cachedImage)
        // For images: skip loading if we already have the pixels.
        // For videos: pool check happens in loadVideoPlayer(), keep loading=true.
        _isLoading = State(initialValue: item.isVideo ? true : cachedImage == nil)
    }

    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.cardBackground)

            if item.isVideo {
                // ── VIDEO ──────────────────────────────────────────────
                // Thumbnail is shown immediately (loaded via loadThumbnail in onAppear).
                // The player fades in after its first frame is ready (50 ms post-assignment).
                ZStack {
                    if let thumb = thumbnailImage {
                        imageContentView(thumb)
                            .opacity(isVideoPlayerReady ? 0 : 1)
                            .animation(.easeIn(duration: 0.2), value: isVideoPlayerReady)
                    } else if isLoading, !isVideoPlayerReady {
                        ProgressView().scaleEffect(1.5)
                    }

                    if let player = player {
                        let isPortrait = item.asset.pixelHeight >= item.asset.pixelWidth
                        GeometryReader { geo in
                            ZStack {
                                if !isPortrait {
                                    VideoPlayerView(player: player, gravity: .resizeAspectFill)
                                        .frame(width: geo.size.width, height: geo.size.height)
                                        .blur(radius: 25)
                                        .scaleEffect(1.1)
                                        .clipped()
                                }
                                VideoPlayerView(player: player, gravity: isPortrait ? .resizeAspectFill : .resizeAspect)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                                    .onTapGesture {
                                        isMuted.toggle()
                                        PhotoCardView.globalMute = isMuted
                                        player.isMuted = isMuted
                                    }
                                VStack {
                                    HStack {
                                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                            .font(.caption)
                                            .foregroundColor(.white)
                                            .padding(6)
                                            .background(Circle().fill(.black.opacity(0.6)))
                                            .padding(8)
                                        Spacer()
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .opacity(isVideoPlayerReady ? 1 : 0)
                        .animation(.easeIn(duration: 0.2), value: isVideoPlayerReady)
                    }
                }

                // Bottom bar: progress + duration
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        if let player = player, isVideoPlayerReady {
                            VideoProgressBar(player: player, duration: item.duration)
                                .padding(.horizontal, 16)
                        }
                        HStack {
                            Image(systemName: "video.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                            Text(item.durationString)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                    .background(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
            } else {
                // ── IMAGE ──────────────────────────────────────────────
                // thumbnailImage (low-res) appears immediately as the base layer.
                // Full-res image cross-fades on top when it arrives.
                // If the asset was already in NSCache, image is set at init and no
                // thumbnail is ever loaded — zero round-trips.
                ZStack {
                    if let thumb = thumbnailImage {
                        imageContentView(thumb)
                    }
                    if let full = image {
                        imageContentView(full)
                            .transition(.opacity)
                    }
                    if image == nil, thumbnailImage == nil {
                        if isLoading {
                            ProgressView().scaleEffect(1.5)
                        } else {
                            Image(systemName: "photo.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            // ── File size + Favorite badge (top-right) ─────────────────
VStack {
    HStack {
        Spacer()
        HStack(spacing: 6) {
            if item.asset.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundColor(.pink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
            }
            Text(item.fileSizeString)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.6)))
        }
        .padding()
    }
    Spacer()
}

            // ── Screenshot / Recording badge (top-left) ────────────────
            if item.isScreenshot || item.isScreenRecording {
                VStack {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: item.isScreenshot ? "camera.viewfinder" : "record.circle")
                                .font(.caption)
                            Text(item.isScreenshot ? String(localized: "badge.screenshot") : String(localized: "badge.recording"))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.blue.opacity(0.8)))
                        .padding()

                        Spacer()
                    }
                    Spacer()
                }
            }

            // ── iCloud badge (bottom-left) — shown when offline mode is active
            // and this card hasn't been downloaded to the device yet. ───────────
            if item.isCloudOnly {
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "icloud.slash.fill")
                                .font(.system(size: 10, weight: .medium))
                            Text("iCloud")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule().fill(Color.black.opacity(0.45)))
                        )
                        .padding(.leading, 12)
                        .padding(.bottom, item.isVideo ? 56 : 12)

                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .cardShadow()
        .onAppear {
            if item.isVideo {
                isMuted = PhotoCardView.globalMute
                loadVideoThumbnail()
                loadVideoPlayer()
            } else if image == nil {
                // Cache hit at init already set image — skip the async round-trip.
                loadImage()
            }
        }
        .onDisappear {
            stopPlayer()
            isVideoPlayerReady = false
            thumbnailImage = nil
            if item.isVideo {
                Task { await VideoPlayerPool.shared.release(for: item.asset) }
            }
        }
        .onChange(of: isTopCard) { _, nowTop in
    if nowTop {
        player?.seek(to: .zero)
        player?.play()
        NotificationCenter.default.post(name: .resumeVideoObserver, object: nil)
    } else {
        stopPlayer()
    }
}
        .onReceive(NotificationCenter.default.publisher(for: .stopCurrentVideo)) { _ in
            stopPlayer()
        }
        .onReceive(NotificationCenter.default.publisher(for: .resumeTopCardVideo)) { _ in
            // Gesture was cancelled — re-sync play state if the player was
            // interrupted mid-drag (e.g. pool warm-up touched the current item).
            guard isTopCard, let p = player, p.currentItem != nil else { return }
            if p.timeControlStatus != .playing { p.play() }
        }
    }

    // MARK: - Stop Player

    private func stopPlayer() {
        player?.pause()
        player?.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: - Shared Image Layout Helper

    /// Renders a UIImage in the card's portrait/landscape layout.
    /// Used for both full-res images and low-res thumbnails so the two layers
    /// are visually identical and cross-fades look seamless.
    @ViewBuilder
    private func imageContentView(_ uiImage: UIImage) -> some View {
        let isPortrait = item.asset.pixelHeight >= item.asset.pixelWidth
        GeometryReader { geo in
            ZStack {
                if !isPortrait {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 25)
                        .scaleEffect(1.1)
                        .clipped()
                }
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: isPortrait ? .fill : .fit)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
        }
    }

    // MARK: - Image Loading

    private func loadImage() {
        // Disk cache hit — asset was pre-fetched while on WiFi. Serve instantly.
        if let diskCached = OfflineCacheService.shared.retrieve(for: item.id) {
            self.image = diskCached
            self.isLoading = false
            return
        }

        // Pass 1 — instant local thumbnail, never touches iCloud.
        PhotoLibraryService.shared.loadThumbnail(
            for: item.asset,
            targetSize: CGSize(width: 300, height: 400)
        ) { thumb in
            guard let thumb, self.image == nil else { return }
            self.thumbnailImage = thumb
            self.isLoading = false
        }

        // Pass 2 — full-res. Respects isOfflineMode via PhotoLibraryService.
        // In offline mode: .opportunistic + no network → returns best local quality.
        PhotoLibraryService.shared.loadImage(
            for: item.asset,
            targetSize: CGSize(width: 600, height: 800)
        ) { fullRes in
            guard let fullRes else { return }
            if self.thumbnailImage != nil {
                withAnimation(.easeIn(duration: 0.18)) { self.image = fullRes }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.thumbnailImage = nil
                }
            } else {
                self.image = fullRes
            }
            self.isLoading = false
        }
    }

    // MARK: - Video Loading

    /// Loads a fast local thumbnail to show immediately while the AVPlayer warms up.
    private func loadVideoThumbnail() {
        PhotoLibraryService.shared.loadThumbnail(for: item.asset) { thumb in
            guard self.thumbnailImage == nil else { return }
            self.thumbnailImage = thumb
        }
    }

    /// Flips `isVideoPlayerReady` after a 50 ms delay (allows AVLayer to render
    /// its first frame), then releases the thumbnail once the fade completes.
    private func markVideoReady() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            withAnimation(.easeIn(duration: 0.2)) { isVideoPlayerReady = true }
            try? await Task.sleep(nanoseconds: 250_000_000)
            thumbnailImage = nil
        }
    }

    private func loadVideoPlayer() {
        Task { @MainActor in
            // 1. Pool hit — instant, no I/O.
            if let pooled = VideoPlayerPool.shared.player(for: item.asset) {
                await activatePlayer(pooled)
                return
            }

            // 2. In-flight — pool is already loading this asset; wait rather than
            //    firing a competing PHImageManager request (the first-video freeze fix).
            if let pooled = await VideoPlayerPool.shared.awaitPlayer(for: item.asset, timeout: 0.5) {
                await activatePlayer(pooled)
                return
            }

            // 3. True miss — asset is outside the pool's warm-up window (e.g. fast
            //    swiper who outruns the pool). Load directly as a safety net.
            let options = PHVideoRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = !PhotoLibraryService.shared.isOfflineMode

            PHImageManager.default().requestPlayerItem(forVideo: item.asset, options: options) { playerItem, _ in
                guard let playerItem else {
                    DispatchQueue.main.async { self.isLoading = false }
                    return
                }
                DispatchQueue.main.async {
                    let avPlayer = AVPlayer(playerItem: playerItem)
                    NotificationCenter.default.addObserver(
                        forName: .AVPlayerItemDidPlayToEndTime,
                        object: playerItem,
                        queue: .main
                    ) { [weak avPlayer] _ in
                        guard let avPlayer, avPlayer.currentItem != nil else { return }
                        avPlayer.seek(to: .zero)
                        avPlayer.play()
                    }
                    avPlayer.isMuted = PhotoCardView.globalMute
                    self.player = avPlayer
                    self.isLoading = false
                    if self.isTopCard { avPlayer.play() }
                    self.markVideoReady()
                }
            }
        }
    }

    /// Configures a pooled AVPlayer as the active player for this card.
    @MainActor
    private func activatePlayer(_ avPlayer: AVPlayer) async {
        avPlayer.isMuted = PhotoCardView.globalMute
        self.player = avPlayer
        self.isLoading = false
        if self.isTopCard {
            await avPlayer.seek(to: .zero)
            avPlayer.play()
        }
        markVideoReady()
    }
}

// MARK: - UIViewRepresentable wrapper for AVPlayer

struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerUIView {
        PlayerUIView(player: player, gravity: gravity)
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
    }
}

class PlayerUIView: UIView {
    var player: AVPlayer? {
        didSet { playerLayer.player = player }
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    init(player: AVPlayer, gravity: AVLayerVideoGravity = .resizeAspect) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = gravity
    }

    required init?(coder: NSCoder) { fatalError() }
}

//#Preview {
//    Text("Photo Card Preview")
//        .frame(width: 300, height: 500)
//    PhotoCardView(item: PhotoItem(asset: PHAsset()), isTopCard: true)
//}

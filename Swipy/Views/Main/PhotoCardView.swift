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
    @State private var isSharing = false
    @State private var player: AVPlayer?
    @State private var isMuted = false

    // Thumbnail Gate state
    /// Low-res placeholder shown immediately while full-res / AVPlayer loads.
    @State private var thumbnailImage: UIImage?
    /// True once the AVPlayer has had 50 ms to render its first frame.
    /// Thumbnail is visible until this flips.
    @State private var isVideoPlayerReady = false

    @State private var showImageSpinner = false
    @State private var showLoadingSpinner = false
    @State private var isBufferingStall = false
    @State private var playerItemFailed = false
    @State private var timeControlObserver: NSKeyValueObservation?
    @State private var playerItemStatusObserver: NSKeyValueObservation?
    @State private var videoEndObserver: (any NSObjectProtocol)?
    @State private var videoSpinnerTask: Task<Void, Never>?
    @State private var imageSpinnerTask: Task<Void, Never>?

    /// 1–10 aesthetic match score. Nil while persona is building or for videos.
    let aestheticScore: Int?

    /// True when `cachedImage` is the fully-resolved version — no further
    /// PHImageManager callbacks will arrive for this asset. The View skips
    /// the reload dance and spinner entirely when this is set.
    let isCachedImageFinal: Bool

    let onShare: ((@escaping () -> Void) -> Void)?

    /// Pass a pre-loaded image from the ViewModel cache to display it instantly,
    /// skipping the async load path entirely and preventing any ProgressView flash.
    init(item: PhotoItem, isTopCard: Bool, cachedImage: UIImage? = nil, isCachedImageFinal: Bool = false, aestheticScore: Int? = nil, onShare: ((@escaping () -> Void) -> Void)? = nil) {
        self.item = item
        self.isTopCard = isTopCard
        self.isCachedImageFinal = isCachedImageFinal
        self.aestheticScore = aestheticScore
        self.onShare = onShare
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
                                VideoPlayerView(
                                    player: player,
                                    gravity: isPortrait ? .resizeAspectFill : .resizeAspect,
                                    onReadyForDisplay: {
                                        withAnimation(.easeIn(duration: 0.2)) {
                                            isVideoPlayerReady = true
                                            showLoadingSpinner = false
                                        }
                                        Task { @MainActor in
                                            try? await Task.sleep(nanoseconds: 300_000_000)
                                            thumbnailImage = nil
                                        }
                                    }
                                )
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                                .onTapGesture {
                                    isMuted.toggle()
                                    PhotoCardView.globalMute = isMuted
                                    player.isMuted = isMuted
                                    AudioSessionManager.shared.configure(muted: isMuted)
                                }
                            }
                        }
                        .opacity(isVideoPlayerReady ? 1 : 0)
                        .animation(.easeIn(duration: 0.2), value: isVideoPlayerReady)
                    }

                    loadingSpinnerOverlay(visible: (showLoadingSpinner && !isVideoPlayerReady) || (isBufferingStall && isVideoPlayerReady))

                    // Error indicator — only for unrecoverable AVPlayerItem failures.
                    if playerItemFailed {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundColor(.white)
                            .shadow(color: .black.opacity(0.5), radius: 6)
                            .transition(.opacity)
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
                    if image == nil, thumbnailImage == nil, !isLoading {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                    }
                    loadingSpinnerOverlay(visible: showImageSpinner && image == nil)
                }
            }

            // ── Top badges row: speaker (left) · snooze · favorite · size · share (right) ──
            VStack {
                HStack(spacing: 6) {
                    if player != nil {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Circle().fill(.black.opacity(0.6)))
                            .allowsHitTesting(false)
                    }
                    Spacer()
                    if item.snoozeCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.caption)
                            Text("×\(item.snoozeCount)")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(Capsule().fill(Color.orange.opacity(0.2)))
                        )
                    }
                    if item.asset.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption)
                            .foregroundColor(.pink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                    }
                    if item.fileSize > 0 {
                        Text(item.fileSizeString)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.black.opacity(0.6)))
                    }
                    Button {
                        guard !isSharing else { return }
                        HapticService.shared.selection()
                        isSharing = true
                        onShare? {
                            Task { @MainActor in isSharing = false }
                        }
                    } label: {
                        ZStack {
                            if isSharing {
                                ProgressView().tint(.white).scaleEffect(0.7)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.caption)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(width: 16, height: 16)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                }
                .animation(.easeIn(duration: 0.3), value: aestheticScore != nil)
                .padding(.horizontal, 8)
                .padding(.vertical, 16)
                Spacer()
            }

            // ── Screenshot / Recording / Burst Best badge (top-left) ─────
            if item.isScreenshot || item.isScreenRecording || item.isBurstBest {
                VStack {
                    HStack {
                        HStack(spacing: 6) {
                            if item.isBurstBest {
                                Text("⭐️")
                                    .font(.caption)
                                Text(String(localized: "badge.burst_best"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            } else {
                                Image(systemName: item.isScreenshot ? "camera.viewfinder" : "record.circle")
                                    .font(.caption)
                                Text(item.isScreenshot ? String(localized: "badge.screenshot") : String(localized: "badge.recording"))
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(item.isBurstBest ? Color.green.opacity(0.85) : Color.blue.opacity(0.8)))
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
                videoSpinnerTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    guard !Task.isCancelled, !isVideoPlayerReady else { return }
                    withAnimation(.easeIn(duration: 0.2)) { showLoadingSpinner = true }
                }
            } else {
                if isCachedImageFinal, image != nil {
                    // Image is the confirmed final version — no reload or spinner needed.
                    isLoading = false
                } else {
                    // Demote cached image to thumbnail while the HQ version loads behind it.
                    // (Cached image may be a degraded fast-format intermediate.)
                    if image != nil && thumbnailImage == nil {
                        thumbnailImage = image
                        image = nil
                        isLoading = true
                    }
                    Task { @MainActor in
                        if let diskCached = await OfflineCacheService.shared.retrieveAsync(for: item.id) {
                            image = diskCached
                            isLoading = false
                        } else {
                            loadImage()
                        }
                    }
                    // Skip the spinner for isCachedImageFinal cards with nil image:
                    // the asset is locally unavailable in offline mode — no point waiting.
                    if !isCachedImageFinal {
                        imageSpinnerTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            guard !Task.isCancelled, image == nil else { return }
                            withAnimation(.easeIn(duration: 0.2)) { showImageSpinner = true }
                        }
                    }
                }
            }
        }
        .onDisappear {
            stopPlayer()
            // isVideoPlayerReady is intentionally NOT reset here.
            // On tab switch the pool player stays warm — keeping isVideoPlayerReady=true
            // means the video resumes instantly on return without a loading gate.
            // Pool lifecycle is managed by warmUp() stale eviction and rewarmVideoPool(),
            // not by the View. Only the slow-path in loadVideoPlayer() resets this flag.
            thumbnailImage = nil
            videoSpinnerTask?.cancel()
            imageSpinnerTask?.cancel()
            videoSpinnerTask = nil
            imageSpinnerTask = nil
            showImageSpinner = false
            showLoadingSpinner = false
            isBufferingStall = false
            playerItemFailed = false
            timeControlObserver = nil
            playerItemStatusObserver = nil
            if let obs = videoEndObserver { NotificationCenter.default.removeObserver(obs) }
            videoEndObserver = nil
        }
        .onChange(of: isTopCard) { _, nowTop in
            if nowTop {
                if let p = player {
                    AudioSessionManager.shared.configure(muted: PhotoCardView.globalMute)
                    p.seek(to: .zero)
                    p.play()
                }
                NotificationCenter.default.post(name: .resumeVideoObserver, object: nil)
            } else {
                // Relax audio exclusivity when an unmuted video card is swiped away so
                // background audio isn't silenced indefinitely by a stale session state.
                if player != nil && !isMuted {
                    AudioSessionManager.shared.configure(muted: true)
                }
                stopPlayer()
            }
        }
        .onChange(of: player) {
            timeControlObserver = nil
            playerItemStatusObserver = nil
            isBufferingStall = false
            playerItemFailed = false
            guard let currentPlayer = player else { return }

            timeControlObserver = currentPlayer.observe(\.timeControlStatus, options: [.new]) { p, _ in
                let stalling = p.timeControlStatus == .waitingToPlayAtSpecifiedRate
                Task { @MainActor in
                    guard stalling != isBufferingStall else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { isBufferingStall = stalling }
                }
            }

            if let currentItem = currentPlayer.currentItem {
                playerItemStatusObserver = currentItem.observe(\.status, options: [.new]) { item, _ in
                    guard item.status == .failed else { return }
                    Task { @MainActor in
                        withAnimation(.easeIn(duration: 0.2)) { playerItemFailed = true }
                    }
                }
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
        GeometryReader { geo in
            ZStack {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .blur(radius: 25)
                    .scaleEffect(1.1)
                    .clipped()
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    // MARK: - Image Loading

    private func loadImage() {
        // Pass 1 — instant local thumbnail, never touches iCloud.
        // Skip if onAppear already set a thumbnailImage (demoted cached image).
        PhotoLibraryService.shared.loadThumbnail(
            for: item.asset,
            targetSize: CGSize(width: 300, height: 400)
        ) { thumb in
            guard let thumb, self.image == nil, self.thumbnailImage == nil else { return }
            self.thumbnailImage = thumb
            self.isLoading = false
        }

        // Pass 2 — full-res at retina card dimensions. Respects isOfflineMode via PhotoLibraryService.
        PhotoLibraryService.shared.loadImage(
            for: item.asset,
            targetSize: PhotoLibraryService.shared.cardTargetSize
        ) { fullRes in
            guard let fullRes else {
                // Asset missing or corrupt — stop the spinner so the card
                // shows the error placeholder instead of loading forever (Bug #1 fix).
                self.isLoading = false
                return
            }
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

    /// Loads a sharp full-card thumbnail to show immediately while the AVPlayer warms up.
    private func loadVideoThumbnail() {
        PhotoLibraryService.shared.loadThumbnail(
            for: item.asset,
            targetSize: CGSize(width: 600, height: 800)
        ) { thumb in
            guard self.thumbnailImage == nil else { return }
            self.thumbnailImage = thumb
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

            // 3. True miss — asset is outside the pool's warm-up window (e.g. fast swiper
            //    who outruns the pool, or memory-pressure pool eviction between tab switches).
            //    Reset the ready gate so the loading state shows while the new player buffers.
            isVideoPlayerReady = false
            let isOffline = PhotoLibraryService.shared.isOfflineMode
            let options = PHVideoRequestOptions()
            // Mirror the pool's delivery policy: full quality offline, fast online.
            options.deliveryMode = isOffline ? .highQualityFormat : .fastFormat
            options.isNetworkAccessAllowed = !isOffline

            PHImageManager.default().requestPlayerItem(forVideo: item.asset, options: options) { playerItem, _ in
                guard let playerItem else {
                    DispatchQueue.main.async {
                        self.isLoading = false
                        self.showLoadingSpinner = false   // prevent infinite spinner
                        if isOffline { self.playerItemFailed = true }  // show error icon
                    }
                    return
                }
                DispatchQueue.main.async {
                    let avPlayer = AVPlayer(playerItem: playerItem)
                    self.videoEndObserver = NotificationCenter.default.addObserver(
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
                    if self.isTopCard {
                        AudioSessionManager.shared.configure(muted: PhotoCardView.globalMute)
                        avPlayer.play()
                    }
                    // isVideoPlayerReady is set by AVPlayerLayer.isReadyForDisplay KVO in PlayerUIView
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
            AudioSessionManager.shared.configure(muted: PhotoCardView.globalMute)
            await avPlayer.seek(to: .zero)
            avPlayer.play()
        }
        // isVideoPlayerReady is set by AVPlayerLayer.isReadyForDisplay KVO in PlayerUIView
    }

    // MARK: - Loading Spinner

    @ViewBuilder
    private func loadingSpinnerOverlay(visible: Bool) -> some View {
        if visible {
            Circle()
                .fill(.black.opacity(0.5))
                .frame(width: 56, height: 56)
                .overlay(ProgressView().tint(.white).scaleEffect(1.3))
                .transition(.opacity)
        }
    }

    private func aestheticScoreColor(_ score: Int) -> Color {
        switch score {
        case 8...10: return .swipeGreen
        case 5...7:  return .white
        default:     return .orange
        }
    }

    private func scoreBadgeView(_ score: Int) -> some View {
        let color = aestheticScoreColor(score)
        return HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundColor(color)
            Text("\(score)/10")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(color.opacity(0.15)))
        )
    }
}

// MARK: - UIViewRepresentable wrapper for AVPlayer

struct VideoPlayerView: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect
    var onReadyForDisplay: (() -> Void)? = nil

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView(player: player, gravity: gravity)
        view.onReadyForDisplay = onReadyForDisplay
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.player = player
        uiView.onReadyForDisplay = onReadyForDisplay
    }
}

class PlayerUIView: UIView {
    var player: AVPlayer? {
        didSet {
            // Reset flag so the callback can fire again for the new player.
            // The observation is on playerLayer (always the same instance), so it
            // keeps listening correctly through any player replacement.
            hasCalledReadyCallback = false
            playerLayer.player = player
            // Fast path: same pooled player reassigned after a tab switch — layer is
            // already displaying, KVO won't fire (value unchanged), so fire immediately.
            if playerLayer.isReadyForDisplay {
                hasCalledReadyCallback = true
                DispatchQueue.main.async { self.onReadyForDisplay?() }
            }
        }
    }
    var onReadyForDisplay: (() -> Void)?

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    private var readyObservation: NSKeyValueObservation?
    private var hasCalledReadyCallback = false

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    init(player: AVPlayer, gravity: AVLayerVideoGravity = .resizeAspect) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = gravity
        // Fire once when AVPlayerLayer has its first decoded frame ready to display.
        // .initial fires immediately if the layer is already ready (pre-warmed pool hit).
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] _, change in
            guard change.newValue == true, let self, !self.hasCalledReadyCallback else { return }
            self.hasCalledReadyCallback = true
            DispatchQueue.main.async { self.onReadyForDisplay?() }
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}

//#Preview {
//    Text("Photo Card Preview")
//        .frame(width: 300, height: 500)
//    PhotoCardView(item: PhotoItem(asset: PHAsset()), isTopCard: true)
//}

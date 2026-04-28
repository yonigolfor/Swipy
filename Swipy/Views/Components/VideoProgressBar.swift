//
//  VideoProgressBar.swift
//  CleanSwipe
//

import SwiftUI
import AVKit

struct VideoProgressBar: View {
    let player: AVPlayer
    let duration: TimeInterval

    @State private var progress: Double = 0
    @State private var isDragging = false
    @StateObject private var coordinator = PlayerCoordinator()
    private let haptic = UISelectionFeedbackGenerator()

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: isDragging ? 6 : 4)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: geo.size.width * progress, height: isDragging ? 6 : 4)

                    Circle()
                        .fill(Color.white)
                        .frame(width: isDragging ? 16 : 10, height: isDragging ? 16 : 10)
                        .offset(x: max(0, geo.size.width * progress - (isDragging ? 8 : 5)))
                        .shadow(radius: 2)
                }
                .animation(.easeInOut(duration: 0.15), value: isDragging)
                .contentShape(Rectangle())
                .environment(\.layoutDirection, .leftToRight)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            isDragging = true
                            coordinator.stopObserving()
                            let newProgress = min(max(value.location.x / geo.size.width, 0), 1)
                 progress = newProgress
                            haptic.selectionChanged()
                            let seekTime = CMTime(
                                seconds: newProgress * duration,
                                preferredTimescale: 600
                            )
                            player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
                        }
                        .onEnded { _ in
                            isDragging = false
                            coordinator.startObserving(player: player) { time in
                                guard !isDragging, duration > 0 else { return }
                                let current = time.seconds
                                guard current.isFinite else { return }
                                progress = min(max(current / duration, 0), 1)
                            }
                        }
                )
            }
            .frame(height: 36)

            HStack {
                Text(formatTime(progress * duration))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(formatTime(duration))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .onAppear {
            haptic.prepare()
            progress = 0
            startObserving()
        }
        .onDisappear {
            coordinator.stopObserving()
        }
//        .onReceive(NotificationCenter.default.publisher(for: .stopCurrentVideo)) { _ in
//            coordinator.stopObserving()
//        }
//        .onReceive(NotificationCenter.default.publisher(for: .resumeVideoObserver)) { _ in
//            progress = 0
//            startObserving()
//        }
    }

    private func startObserving() {
        coordinator.startObserving(player: player) { time in
            guard !isDragging, duration > 0 else { return }
            let current = time.seconds
            guard current.isFinite else { return }
            progress = min(max(current / duration, 0), 1)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - PlayerCoordinator
private class PlayerCoordinator: ObservableObject {
    private weak var observedPlayer: AVPlayer?
    private var timeObserver: Any?

    func startObserving(player: AVPlayer, onTick: @escaping (CMTime) -> Void) {
        stopObserving()
        observedPlayer = player
        let interval = CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { time in
            onTick(time)
        }
    }

    func stopObserving() {
        guard let observer = timeObserver,
              let player = observedPlayer else {
            timeObserver = nil
            observedPlayer = nil
            return
        }
        player.removeTimeObserver(observer)
        timeObserver = nil
        observedPlayer = nil
    }

    deinit {
        stopObserving()
    }
}

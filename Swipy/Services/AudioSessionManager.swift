import AVFoundation

/// Controls AVAudioSession category around video playback so background audio
/// (Spotify, Podcasts, etc.) is never interrupted by a muted video.
///
/// Rule:
///   muted video   → .playback + .mixWithOthers  — background audio keeps playing
///   unmuted video → .playback                   — background audio pauses
///
/// Deactivation is intentionally deferred to tab-switch (pauseVideoPool) rather
/// than fired on every card swipe, which would cause an audible "blip" as
/// background audio briefly resumes then stops again between consecutive cards.
final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private init() {}

    /// Call before every video play() and on every mute-state change.
    func configure(muted: Bool) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: muted ? .mixWithOthers : [])
            try session.setActive(true)
        } catch {}
    }

    /// Call only when all video playback ceases (tab switch, app background).
    /// notifyOthersOnDeactivation signals background audio apps to resume.
    func deactivate() {
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
    }
}

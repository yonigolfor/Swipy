package com.swipy.core.designsystem.haptics

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Android port of iOS `HapticService` — see root `HAPTICS.md` "Swipe Actions" for the exact
 * event map this mirrors. iOS distinguishes swipe actions by *generator style* (light/heavy)
 * independently of its 0-1 intensity scalar; `VibrationEffect.createOneShot` has no separate
 * "style" concept, so style is approximated here via duration/amplitude shape instead:
 * [keep] and [snooze] share iOS's `.light` style (same short duration, differ only by
 * amplitude — 1.0 vs 0.6, exactly mirroring iOS), while [delete] gets both a higher amplitude
 * (iOS's 0.8) *and* a longer, double-pulse waveform for a "heavy" feel iOS's `.heavy` generator
 * gets for free from its own distinct waveform shape.
 *
 * [thresholdCrossed] has no iOS equivalent on the real card stack — iOS's `.soft` drag haptic
 * only exists on the onboarding demo card (`OnboardingView.swift`'s `softHaptic`), not
 * `PhotoStackViewModel`'s real swipe-commit haptics (confirmed against `HAPTICS.md`, which has
 * no drag-threshold entry). This is a deliberate Android-only addition, not a literal port.
 */
@Singleton
class HapticManager @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    private val vibrator: Vibrator by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            manager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
    }

    /** Swipe right — light, full-intensity single tap (HAPTICS.md: light / ~1.0). */
    fun keep() = oneShot(durationMs = 15, amplitude = 255)

    /** Swipe left — heavier and noticeably more felt than [keep] (HAPTICS.md's stated design
     * intent: "the asymmetry reinforces that deletion is a weightier action"). A double-pulse
     * waveform, not iOS's single tap — an intentional Android enhancement for extra distinctness. */
    fun delete() = doublePulse(pulseDurationMs = 30, gapMs = 40, amplitude = 204)

    /** Swipe up — light, lightest of the three (HAPTICS.md: light / 0.6), "signalling deferral
     * rather than decision." Same duration as [keep], lower amplitude only — mirrors iOS
     * exactly, since both are the same `.light` generator style there too. */
    fun snooze() = oneShot(durationMs = 15, amplitude = 153)

    /** Drag crossed the direction-lock threshold — a light hint, lower amplitude than any
     * commit haptic. Android-only, see class doc. */
    fun thresholdCrossed() = oneShot(durationMs = 10, amplitude = 76)

    /** iOS's `.medium` `UIImpactFeedbackGenerator` — "all CTA taps" (root `CLAUDE.md`
     * "Haptics"). Wired into [com.swipy.core.designsystem.component.GoldCapsuleButton] itself
     * (the one shared CTA component every onboarding step — and any future screen — already
     * uses), matching iOS's own single-generator-instance-for-every-CTA architecture rather
     * than needing a call at each of the 6+ individual button call sites. */
    fun mediumTap() = oneShot(durationMs = 20, amplitude = 200)

    /** iOS's `.soft` `UIImpactFeedbackGenerator` — used only for the onboarding demo cards'
     * drag feedback (`OnboardingView.swift`'s `softHaptic`, root `CLAUDE.md`: "SwipeDemo drag
     * changes"), not the real card stack. Deliberately fired only on direction-state
     * transitions (mirrors [thresholdCrossed]'s own once-per-crossing discipline), not on every
     * raw `onDrag` callback the way iOS's literal per-frame `softHaptic.impactOccurred()` call
     * does — UIKit's taptic engine internally coalesces rapid repeats, `Vibrator.vibrate()` has
     * no equivalent protection, so calling this unthrottled would be a genuinely different
     * (worse) feel on Android, not a faithful port. */
    fun softTick() = oneShot(durationMs = 8, amplitude = 100)

    /** `UISelectionFeedbackGenerator.selectionChanged()` — Filter category tap
     * (`HAPTICS.md` "UI Actions"). Crisper/lighter than [thresholdCrossed] in spirit even
     * though the two share a similar physical shape — kept as its own named method rather than
     * reused, since the two are semantically unrelated events that could tune independently. */
    fun selectionTick() = oneShot(durationMs = 6, amplitude = 90)

    /** `UINotificationFeedbackGenerator(.success)` — used for both the Undo action (the
     * Android-native trigger point in place of iOS's shake gesture, which has no Android
     * equivalent built) and completing a page-load (`HAPTICS.md` "UI Actions": `success()`).
     * A short soft tick followed by a firmer tap — approximates iOS's rising two-stage success
     * pattern; [error] is the deliberately distinct negative counterpart. */
    fun success() {
        if (!vibrator.hasVibrator()) return
        vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(15, 40, 25), intArrayOf(130, 0, 220), -1))
    }

    /** `UINotificationFeedbackGenerator(.error)` — Photos access denied, both at the initial
     * onboarding prompt and mid-session if revoked (`HAPTICS.md` "Permissions"). Two equal,
     * punchier pulses close together — a sharper, more "negative"-reading shape than [success]'s
     * softer rising pattern, not just the same waveform played louder. */
    fun error() {
        if (!vibrator.hasVibrator()) return
        vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(35, 50, 35), intArrayOf(255, 0, 255), -1))
    }

    /** Shuffle FAB tap (`HAPTICS.md`: light / 0.7). Fires at tap time, distinct from
     * [shuffleLand] which fires once the fly-out/land-in transition actually completes. */
    fun shuffleActivate() = oneShot(durationMs = 15, amplitude = 178)

    /** Shuffled cards land (`HAPTICS.md`: light 0.5 → 120ms delay → light 0.35) — a settling
     * two-beat "thud, then a lighter echo" landing feel. */
    fun shuffleLand() {
        if (!vibrator.hasVibrator()) return
        vibrator.vibrate(VibrationEffect.createWaveform(longArrayOf(15, 120, 15), intArrayOf(128, 0, 89), -1))
    }

    /**
     * GB milestone 6-beat crescendo (`HAPTICS.md` "Gamified Top Bar"). iOS builds this by
     * manually sequencing 6 separate `UIImpactFeedbackGenerator.impactOccurred()` calls with
     * `DispatchQueue.asyncAfter` delays between each, because a single `UIImpactFeedbackGenerator`
     * call can't express a multi-beat pattern on its own — that's the reason `HAPTICS.md` calls
     * out `SessionSavingsBarView` as the one exception allowed to bypass `HapticService` and
     * drive generators directly. Android's `VibrationEffect.createWaveform` has no such
     * limitation — it natively expresses an arbitrary multi-stage timing/amplitude sequence as
     * one atomic effect — so the whole crescendo is a single call here, a more idiomatic
     * Android primitive for this exact shape rather than a manual-delay port of iOS's own
     * workaround. Amplitudes map iOS's per-beat intensity scalars (0.7/0.9/1.0/0.8/1.0)
     * directly to `0-255`; the 6th beat (iOS's `.success` notification, not another impact) gets
     * a distinctly longer pulse so it still reads as a different *kind* of beat, not just
     * another tap in the run.
     */
    fun milestoneBurst() {
        if (!vibrator.hasVibrator()) return
        val timings = longArrayOf(25, 85, 25, 85, 25, 90, 25, 95, 25, 70, 40)
        val amplitudes = intArrayOf(178, 0, 229, 0, 255, 0, 204, 0, 255, 0, 220)
        vibrator.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
    }

    /** Empty Trash — triple-heavy at full intensity (`HAPTICS.md`: "the strongest feedback in
     * the app, matching the finality of permanent deletion"). Same single-atomic-waveform
     * reasoning as [milestoneBurst]. */
    fun emptyTrashBurst() {
        if (!vibrator.hasVibrator()) return
        val timings = longArrayOf(30, 100, 30, 200, 30)
        val amplitudes = intArrayOf(255, 0, 255, 0, 255)
        vibrator.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
    }

    private fun oneShot(durationMs: Long, amplitude: Int) {
        if (!vibrator.hasVibrator()) return
        vibrator.vibrate(VibrationEffect.createOneShot(durationMs, amplitude))
    }

    private fun doublePulse(pulseDurationMs: Long, gapMs: Long, amplitude: Int) {
        if (!vibrator.hasVibrator()) return
        val timings = longArrayOf(0, pulseDurationMs, gapMs, pulseDurationMs)
        val amplitudes = intArrayOf(0, amplitude, 0, amplitude)
        vibrator.vibrate(VibrationEffect.createWaveform(timings, amplitudes, -1))
    }
}

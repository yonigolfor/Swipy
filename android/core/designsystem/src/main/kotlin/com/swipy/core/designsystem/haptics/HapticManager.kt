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

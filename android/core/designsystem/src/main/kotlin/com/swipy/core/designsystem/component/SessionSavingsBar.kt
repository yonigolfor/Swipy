package com.swipy.core.designsystem.component

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.swipy.core.designsystem.R
import com.swipy.core.designsystem.theme.LavaGradientBottom
import com.swipy.core.designsystem.theme.LavaGradientTop
import com.swipy.core.designsystem.theme.SavingsBarGradientEnd
import com.swipy.core.designsystem.theme.SavingsBarGradientStart
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Gamified top bar showing space saved in the current session — Compose port of
 * SessionSavingsBarView.swift. [sessionSpaceSavedMB] is cumulative and monotonically
 * increasing; crossing [milestoneThresholdMB] plays the star "lava-fill" celebration.
 *
 * [milestoneUnitLabel]/[spaceUnitLabel] default to bare SI unit abbreviations ("GB"/"MB"),
 * deliberately not localized — unit abbreviations are conventionally left untranslated.
 * [spaceSavedLabel] defaults to a real localized string ([R.string.designsystem_space_saved])
 * since the only current call site (SwipeStackScreen) never overrides it — this default is the
 * actual production value, not just a decorative fallback.
 */
@Composable
fun SessionSavingsBar(
    sessionSpaceSavedMB: Double,
    modifier: Modifier = Modifier,
    milestoneThresholdMB: Double = 1000.0,
    milestoneUnitLabel: String = "GB",
    spaceUnitLabel: String = "MB",
    spaceSavedLabel: String = stringResource(R.string.designsystem_space_saved),
    onMilestoneReached: () -> Unit = {},
) {
    val progressFraction = ((sessionSpaceSavedMB % milestoneThresholdMB) / milestoneThresholdMB).toFloat()
    val milestoneCount = (sessionSpaceSavedMB / milestoneThresholdMB).toInt()
    val currentMB = sessionSpaceSavedMB % milestoneThresholdMB

    val animatedProgress = remember { Animatable(progressFraction) }
    val starFill = remember { Animatable(progressFraction) }
    var isCelebrating by remember { mutableStateOf(false) }
    var lastMilestone by remember { mutableIntStateOf(milestoneCount) }
    var celebrationTrigger by remember { mutableIntStateOf(0) }

    LaunchedEffect(milestoneCount) {
        if (milestoneCount <= lastMilestone) {
            lastMilestone = milestoneCount
            return@LaunchedEffect
        }
        lastMilestone = milestoneCount
        isCelebrating = true

        // Step 1: fill bar + star to 100%.
        coroutineScope {
            launch { animatedProgress.animateTo(1f, spring(dampingRatio = 0.82f, stiffness = 210f)) }
            starFill.animateTo(1f, spring(dampingRatio = 0.82f, stiffness = 210f))
        }

        // Step 2: star celebration (see StarSection's own LaunchedEffect(celebrationTrigger)).
        delay(360)
        celebrationTrigger++
        onMilestoneReached()

        // Step 3: after the star's full windup/spin/settle cycle, snap bar to the remainder
        // and drain the star.
        delay(CELEBRATION_CYCLE_MS)
        animatedProgress.snapTo(0f)
        coroutineScope {
            launch { animatedProgress.animateTo(progressFraction, spring(dampingRatio = 0.65f, stiffness = 180f)) }
            starFill.animateTo(0f, tween(650, easing = LinearOutSlowInEasing))
        }
        delay(680)
        starFill.animateTo(progressFraction, spring(dampingRatio = 0.7f, stiffness = 220f))
        isCelebrating = false
    }

    LaunchedEffect(progressFraction, isCelebrating) {
        if (isCelebrating) return@LaunchedEffect
        coroutineScope {
            launch { animatedProgress.animateTo(progressFraction, spring(dampingRatio = 0.65f, stiffness = 180f)) }
            starFill.animateTo(progressFraction, spring(dampingRatio = 0.65f, stiffness = 180f))
        }
    }

    Row(
        modifier = modifier.padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        ProgressSection(
            currentMB = currentMB,
            spaceUnitLabel = spaceUnitLabel,
            spaceSavedLabel = spaceSavedLabel,
            animatedProgress = animatedProgress.value,
            modifier = Modifier.weight(1f),
        )
        StarSection(
            milestoneCount = milestoneCount,
            milestoneUnitLabel = milestoneUnitLabel,
            starFill = starFill.value,
            celebrationTrigger = celebrationTrigger,
        )
    }
}

@Composable
private fun ProgressSection(
    currentMB: Double,
    spaceUnitLabel: String,
    spaceSavedLabel: String,
    animatedProgress: Float,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(5.dp)) {
        Text(
            text = "${currentMB.roundToInt()} $spaceUnitLabel",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.Bold,
        )

        BoxWithConstraints(
            modifier = Modifier
                .fillMaxWidth()
                .height(12.dp),
        ) {
            val fillWidth = maxOf(6.dp, maxWidth * animatedProgress)
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f),
                        shape = CircleShape,
                    ),
            )
            Box(
                modifier = Modifier
                    .width(fillWidth)
                    .fillMaxHeight()
                    .background(
                        brush = Brush.horizontalGradient(listOf(SavingsBarGradientStart, SavingsBarGradientEnd)),
                        shape = CircleShape,
                    ),
            )
        }

        Text(
            text = spaceSavedLabel + " 🌿", // trailing leaf glyph — no icon dependency needed for one glyph
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun StarSection(
    milestoneCount: Int,
    milestoneUnitLabel: String,
    starFill: Float,
    celebrationTrigger: Int,
    modifier: Modifier = Modifier,
) {
    val isDark = isSystemInDarkTheme()
    val starTrackColor = if (isDark) Color.White.copy(alpha = 0.7f) else Color.Black.copy(alpha = 0.13f)

    val rotation = remember { Animatable(0f) }
    val scale = remember { Animatable(1f) }
    var showArms by remember { mutableStateOf(false) }

    val infiniteTransition = rememberInfiniteTransition(label = "lavaWavePhase")
    val wavePhase by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = (2 * PI).toFloat(),
        animationSpec = infiniteRepeatable(tween(2200, easing = LinearEasing)),
        label = "lavaWavePhase",
    )

    LaunchedEffect(celebrationTrigger) {
        if (celebrationTrigger == 0) return@LaunchedEffect
        // windup
        rotation.animateTo(8f, tween(100, easing = LinearOutSlowInEasing))
        // spin — full 360° left spin, waving-hand arms visible
        showArms = true
        coroutineScope {
            launch { rotation.animateTo(-352f, tween(420, easing = FastOutSlowInEasing)) }
            scale.animateTo(1.25f, tween(420, easing = FastOutSlowInEasing))
        }
        showArms = false
        // settle — underdamped spring back to rest
        coroutineScope {
            launch { rotation.animateTo(0f, spring(dampingRatio = 0.58f, stiffness = 260f)) }
            scale.animateTo(1f, spring(dampingRatio = 0.58f, stiffness = 260f))
        }
    }

    Box(
        modifier = modifier.size(width = 92.dp, height = 76.dp),
        contentAlignment = Alignment.Center,
    ) {
        if (showArms) {
            Text(
                text = "👋",
                fontSize = 14.sp,
                modifier = Modifier
                    .offset((-44).dp, 10.dp)
                    .graphicsLayer { rotationZ = -30f },
            )
            Text(
                text = "👋",
                fontSize = 14.sp,
                modifier = Modifier
                    .offset(44.dp, 10.dp)
                    .graphicsLayer { rotationZ = 30f; scaleX = -1f },
            )
        }

        Box(
            modifier = Modifier
                .size(68.dp)
                .graphicsLayer {
                    rotationZ = rotation.value
                    scaleX = scale.value
                    scaleY = scale.value
                },
            contentAlignment = Alignment.Center,
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val starPath = chubbyStarPath(size)
                drawPath(starPath, color = starTrackColor)
                clipPath(starPath) {
                    val wavePath = lavaWavePath(size, fillFraction = starFill, wavePhase = wavePhase)
                    drawPath(
                        wavePath,
                        brush = Brush.verticalGradient(listOf(LavaGradientTop, LavaGradientBottom)),
                    )
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = "$milestoneCount", fontSize = 19.sp, fontWeight = FontWeight.Black, color = Color.Black)
                Text(text = milestoneUnitLabel, fontSize = 10.sp, fontWeight = FontWeight.Black, color = Color.Black.copy(alpha = 0.8f))
            }
        }
    }
}

/** 5-point star, fat inner radius + rounded tips — port of iOS ChubbyStarShape. */
private fun chubbyStarPath(size: Size, innerRatio: Float = 0.50f, tipRounding: Float = 0.26f): Path {
    val cx = size.width / 2f
    val cy = size.height / 2f
    val outerR = min(size.width, size.height) / 2f
    val innerR = outerR * innerRatio
    val n = 5

    fun pointAt(index: Int, radius: Float, phaseOffset: Double): Offset {
        val angle = index * (2 * PI / n) - PI / 2 + phaseOffset
        return Offset(cx + radius * cos(angle).toFloat(), cy + radius * sin(angle).toFloat())
    }
    fun lerp(a: Offset, b: Offset, t: Float) = Offset(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t)

    val path = Path()
    for (i in 0 until n) {
        val outer = pointAt(i, outerR, 0.0)
        val innerPrev = pointAt((i + n - 1) % n, innerR, PI / n)
        val innerCurr = pointAt(i, innerR, PI / n)
        val a1 = lerp(innerPrev, outer, 1 - tipRounding)
        val a2 = lerp(innerCurr, outer, 1 - tipRounding)
        if (i == 0) path.moveTo(innerPrev.x, innerPrev.y)
        path.lineTo(a1.x, a1.y)
        path.quadraticBezierTo(outer.x, outer.y, a2.x, a2.y)
        path.lineTo(innerCurr.x, innerCurr.y)
    }
    path.close()
    return path
}

/** Bottom-up fill with a two-phase sine-wave top edge — port of iOS LavaWaveShape. */
private fun lavaWavePath(size: Size, fillFraction: Float, wavePhase: Float): Path {
    val path = Path()
    if (fillFraction <= 0.004f) return path

    val fade = minOf(fillFraction * 7f, (1f - fillFraction) * 7f, 1f)
    val amplitude = size.height * 0.11f * fade
    val baseY = size.height * (1f - fillFraction)
    val w = size.width
    val h = size.height
    val pi = PI.toFloat()

    fun waveY(t: Float): Float = baseY +
        amplitude * 0.62f * sin(t * pi * 3f + wavePhase) +
        amplitude * 0.38f * sin(t * pi * 5f - wavePhase * 1.35f)

    val steps = 90
    path.moveTo(0f, h)
    path.lineTo(w, h)
    path.lineTo(w, waveY(1f))
    for (i in steps - 1 downTo 0) {
        val t = i / steps.toFloat()
        path.lineTo(w * t, waveY(t))
    }
    path.close()
    return path
}

/** windup(100) + spin(420) + settle(~560, underdamped spring) — approximates iOS CelebrationPhase.totalDurationMS. */
private const val CELEBRATION_CYCLE_MS = 1080L

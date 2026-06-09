// android/app/src/main/kotlin/hust/appchat/bubble/BubbleAnimationHelper.kt
package hust.appchat.bubble

import android.animation.*
import android.view.View
import android.view.animation.*
import androidx.core.animation.doOnEnd
import androidx.interpolator.view.animation.FastOutSlowInInterpolator
import androidx.interpolator.view.animation.LinearOutSlowInInterpolator

/**
 * BubbleAnimationHelper — factory for reusable bubble system animations.
 *
 * All methods return the started [Animator] so callers can cancel or
 * chain animations.  The helper never holds references to Views; it is
 * safe to call from any thread as long as the animations are started on
 * the main thread (they always are, because ValueAnimator.start() is
 * main-thread-only).
 *
 * Spring physics baseline
 * ────────────────────────
 * Android's built-in SpringForce is in the DynamicAnimation library.
 * This helper uses ValueAnimator + OvershootInterpolator as a lighter
 * alternative that doesn't require the extra dependency, while still
 * producing the characteristic "overshoot → settle" feel.
 *
 * Usage
 * ──────
 * ```kotlin
 * BubbleAnimationHelper.popIn(bubbleView)
 * BubbleAnimationHelper.shake(bubbleView) { /* after shake */ }
 * BubbleAnimationHelper.morphSendButton(btnView, sending = true)
 * ```
 */
object BubbleAnimationHelper {

    // ─── Interpolators ────────────────────────────────────────────────────
    val OVERSHOOT_1 : Interpolator = OvershootInterpolator(1.2f)
    val OVERSHOOT_2 : Interpolator = OvershootInterpolator(2.0f)
    val OVERSHOOT_3 : Interpolator = OvershootInterpolator(3.0f)
    val EASE_OUT    : Interpolator = DecelerateInterpolator(2f)
    val EASE_IN_OUT : Interpolator = FastOutSlowInInterpolator()
    val EASE_OUT_LINEAR: Interpolator = LinearOutSlowInInterpolator()
    val BOUNCE      : Interpolator = BounceInterpolator()
    val ANTICIPATE  : Interpolator = AnticipateInterpolator(1.5f)
    val ANT_OVER    : Interpolator = AnticipateOvershootInterpolator(1.5f)

    // ─────────────────────────────────────────────────────────────────────
    // ENTRANCE
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Scale-from-zero with overshoot — used when a new bubble first appears.
     * Duration: 380 ms
     */
    fun popIn(
        view         : View,
        durationMs   : Long          = 380,
        interpolator : Interpolator  = OVERSHOOT_2,
        onEnd        : (() -> Unit)? = null,
    ): AnimatorSet {
        view.scaleX = 0f; view.scaleY = 0f; view.alpha = 0f
        val sx = ObjectAnimator.ofFloat(view, View.SCALE_X, 0f, 1f)
        val sy = ObjectAnimator.ofFloat(view, View.SCALE_Y, 0f, 1f)
        val fa = ObjectAnimator.ofFloat(view, View.ALPHA,   0f, 1f)
        fa.duration = (durationMs * 0.5).toLong()

        return AnimatorSet().apply {
            playTogether(sx, sy, fa)
            duration          = durationMs
            this.interpolator = interpolator
            onEnd?.let { doOnEnd { it() } }
            start()
        }
    }

    /**
     * Fade + translateY-up entrance — for header or message bubbles.
     */
    fun slideInUp(
        view     : View,
        fromDpY  : Float = 24f,
        durationMs: Long = 280,
        onEnd    : (() -> Unit)? = null,
    ): AnimatorSet {
        val density = view.resources.displayMetrics.density
        val fromPx  = fromDpY * density
        view.translationY = fromPx; view.alpha = 0f

        val ty = ObjectAnimator.ofFloat(view, View.TRANSLATION_Y, fromPx, 0f)
        val fa = ObjectAnimator.ofFloat(view, View.ALPHA, 0f, 1f)

        return AnimatorSet().apply {
            playTogether(ty, fa)
            duration    = durationMs
            interpolator = EASE_OUT
            onEnd?.let { doOnEnd { it() } }
            start()
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // EXIT
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Scale-to-zero with rotation — used when a bubble is deleted.
     * Calls [onEnd] when complete so the caller can remove the view.
     */
    fun deleteExit(
        view    : View,
        onEnd   : () -> Unit,
    ): AnimatorSet {
        val sx   = ObjectAnimator.ofFloat(view, View.SCALE_X,   1f, 0f)
        val sy   = ObjectAnimator.ofFloat(view, View.SCALE_Y,   1f, 0f)
        val fa   = ObjectAnimator.ofFloat(view, View.ALPHA,     1f, 0f)
        val rot  = ObjectAnimator.ofFloat(view, View.ROTATION,  0f, 180f)

        return AnimatorSet().apply {
            playTogether(sx, sy, fa, rot)
            duration     = 300
            interpolator = EASE_IN_OUT
            doOnEnd { onEnd() }
            start()
        }
    }

    /** Simple fade-out. */
    fun fadeOut(
        view      : View,
        durationMs: Long         = 200,
        onEnd     : (() -> Unit)? = null,
    ): ObjectAnimator =
        ObjectAnimator.ofFloat(view, View.ALPHA, view.alpha, 0f).apply {
            duration    = durationMs
            interpolator = EASE_IN_OUT
            onEnd?.let { doOnEnd { it() } }
            start()
        }

    // ─────────────────────────────────────────────────────────────────────
    // ATTENTION / FEEDBACK
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Horizontal shake — used to indicate an error or boundary hit.
     * 3 cycles, decaying amplitude.
     */
    fun shake(
        view    : View,
        amplDp  : Float          = 8f,
        onEnd   : (() -> Unit)?  = null,
    ): ValueAnimator {
        val ampl = amplDp * view.resources.displayMetrics.density
        val anim = ValueAnimator.ofFloat(0f, 1f).apply {
            duration     = 320
            interpolator = LinearInterpolator()
            addUpdateListener { a ->
                val t   = a.animatedFraction
                val dec = 1f - t                 // decaying envelope
                view.translationX = ampl * dec * kotlin.math.sin(t * Math.PI.toFloat() * 6f)
            }
            doOnEnd {
                view.translationX = 0f
                onEnd?.invoke()
            }
            start()
        }
        return anim
    }

    /**
     * Pulse scale — draws attention to a view (e.g. unread badge increment).
     */
    fun pulse(
        view         : View,
        peakScale    : Float = 1.35f,
        durationMs   : Long  = 260,
        onEnd        : (() -> Unit)? = null,
    ): AnimatorSet {
        val scaleUp   = ObjectAnimator.ofPropertyValuesHolder(view,
            PropertyValuesHolder.ofFloat(View.SCALE_X, 1f, peakScale),
            PropertyValuesHolder.ofFloat(View.SCALE_Y, 1f, peakScale))
        val scaleDown = ObjectAnimator.ofPropertyValuesHolder(view,
            PropertyValuesHolder.ofFloat(View.SCALE_X, peakScale, 1f),
            PropertyValuesHolder.ofFloat(View.SCALE_Y, peakScale, 1f))

        scaleUp.duration   = durationMs / 2
        scaleDown.duration = durationMs / 2
        scaleUp.interpolator   = OVERSHOOT_1
        scaleDown.interpolator = EASE_OUT

        return AnimatorSet().apply {
            playSequentially(scaleUp, scaleDown)
            onEnd?.let { doOnEnd { it() } }
            start()
        }
    }

    /**
     * Ring ripple — expands a circular "ring" view outward from a centre point.
     * Used for the online-indicator pulse in BubbleView.
     */
    fun rippleExpand(
        ring         : View,
        fromScale    : Float = 0.6f,
        toScale      : Float = 2.4f,
        durationMs   : Long  = 1_000,
    ): ObjectAnimator {
        ring.scaleX = fromScale; ring.scaleY = fromScale; ring.alpha = 0.8f
        return ObjectAnimator.ofPropertyValuesHolder(
            ring,
            PropertyValuesHolder.ofFloat(View.SCALE_X, fromScale, toScale),
            PropertyValuesHolder.ofFloat(View.SCALE_Y, fromScale, toScale),
            PropertyValuesHolder.ofFloat(View.ALPHA,   0.8f,      0f),
        ).apply {
            duration     = durationMs
            interpolator = EASE_OUT
            repeatCount  = ValueAnimator.INFINITE
            start()
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // TYPING DOTS
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Staggers a vertical bounce across [dots].
     * Returns a list of animators so the caller can cancel all at once.
     */
    fun typingBounce(
        dots        : List<View>,
        amplitude   : Float = 8f,
        periodMs    : Long  = 500,
    ): List<ObjectAnimator> {
        val density = dots.firstOrNull()?.resources?.displayMetrics?.density ?: 1f
        val amp     = amplitude * density

        return dots.mapIndexed { i, dot ->
            ObjectAnimator.ofFloat(dot, View.TRANSLATION_Y, 0f, -amp, 0f).apply {
                duration     = periodMs
                repeatCount  = ValueAnimator.INFINITE
                interpolator = EASE_IN_OUT
                startDelay   = (i * periodMs / dots.size)
                start()
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // SEND BUTTON MORPH
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Morphs the send button between "idle" and "sending" states via
     * a quick scale-down → swap content → scale-up sequence.
     */
    fun morphSendButton(
        view     : View,
        sending  : Boolean,
        onSwap   : () -> Unit,
    ) {
        val scaleDown = ObjectAnimator.ofPropertyValuesHolder(view,
            PropertyValuesHolder.ofFloat(View.SCALE_X, 1f, 0f),
            PropertyValuesHolder.ofFloat(View.SCALE_Y, 1f, 0f)).apply {
            duration     = 100
            interpolator = ANTICIPATE
        }
        val scaleUp = ObjectAnimator.ofPropertyValuesHolder(view,
            PropertyValuesHolder.ofFloat(View.SCALE_X, 0f, 1f),
            PropertyValuesHolder.ofFloat(View.SCALE_Y, 0f, 1f)).apply {
            duration     = 180
            interpolator = OVERSHOOT_2
        }
        AnimatorSet().apply {
            playSequentially(scaleDown, scaleUp)
            addListener(object : AnimatorListenerAdapter() {
                override fun onAnimationEnd(a: Animator) {}
                override fun onAnimationRepeat(a: Animator) {}
                override fun onAnimationStart(a: Animator) {}
                // Swap the icon at the mid-point (after scale-down)
            })
            scaleDown.doOnEnd { onSwap() }
            start()
        }
    }

    // ─────────────────────────────────────────────────────────────────────
    // SNAP TO EDGE
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Animates a bubble's X position to [targetX] with spring overshoot.
     * Used by BubbleOverlayService after drag-end.
     */
    fun snapToEdge(
        view        : View,
        currentX    : Int,
        targetX     : Int,
        updateLayout: (Int) -> Unit,
        durationMs  : Long = 340,
    ): ValueAnimator = ValueAnimator.ofInt(currentX, targetX).apply {
        duration     = durationMs
        interpolator = OvershootInterpolator(1.4f)
        addUpdateListener { a ->
            updateLayout(a.animatedValue as Int)
        }
        start()
    }

    // ─────────────────────────────────────────────────────────────────────
    // COLOUR TRANSITION
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Smooth background colour transition — used when the bubble header
     * morphs between BubbleModes.
     */
    fun transitionBackground(
        view       : View,
        fromColor  : Int,
        toColor    : Int,
        durationMs : Long = 360,
    ): ValueAnimator = ValueAnimator.ofObject(ArgbEvaluator(), fromColor, toColor)
        .apply {
            duration = durationMs
            addUpdateListener { a ->
                view.setBackgroundColor(a.animatedValue as Int)
            }
            start()
        }

    // ─────────────────────────────────────────────────────────────────────
    // CANCEL HELPERS
    // ─────────────────────────────────────────────────────────────────────

    fun cancelAll(vararg animators: Animator?) {
        animators.forEach { it?.cancel() }
    }

    fun cancelAll(animators: List<Animator?>) {
        animators.forEach { it?.cancel() }
    }
}
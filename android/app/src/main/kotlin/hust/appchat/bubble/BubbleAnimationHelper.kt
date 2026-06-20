// android/app/src/main/kotlin/hust/appchat/bubble/BubbleAnimationHelper.kt
package hust.appchat.bubble

import android.animation.*
import android.view.View
import android.view.animation.*
import androidx.core.animation.doOnEnd
import androidx.dynamicanimation.animation.DynamicAnimation
import androidx.dynamicanimation.animation.SpringAnimation
import androidx.dynamicanimation.animation.SpringForce
import androidx.interpolator.view.animation.FastOutSlowInInterpolator
import androidx.interpolator.view.animation.LinearOutSlowInInterpolator

/**
 * BubbleAnimationHelper — factory for reusable bubble system animations.
 *
 * * [SỬA LỖI P1]: Đã chuyển đổi sang mô hình vật lý SpringAnimation chuẩn của Android
 * (thông qua thư viện DynamicAnimation) cho các hiệu ứng xuất hiện và tương tác.
 * * [DỌN DẸP]: Đã loại bỏ các hàm liên quan đến WindowManager cũ (như snapToEdge).
 */
object BubbleAnimationHelper {

    // ─── Interpolators ────────────────────────────────────────────────────
    val EASE_OUT       : Interpolator = DecelerateInterpolator(2f)
    val EASE_IN_OUT    : Interpolator = FastOutSlowInInterpolator()
    val EASE_OUT_LINEAR: Interpolator = LinearOutSlowInInterpolator()
    val ANTICIPATE     : Interpolator = AnticipateInterpolator(1.5f)

    // ─────────────────────────────────────────────────────────────────────
    // ENTRANCE
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Scale-from-zero with natural Spring physics — used when a new view first appears.
     */
    fun popIn(
        view: View,
        onEnd: (() -> Unit)? = null,
    ) {
        view.scaleX = 0f; view.scaleY = 0f; view.alpha = 0f

        val alphaAnim = ObjectAnimator.ofFloat(view, View.ALPHA, 0f, 1f)
        alphaAnim.duration = 200

        val springX = SpringAnimation(view, DynamicAnimation.SCALE_X, 1f)
        val springY = SpringAnimation(view, DynamicAnimation.SCALE_Y, 1f)

        val force = SpringForce(1f).apply {
            stiffness = SpringForce.STIFFNESS_MEDIUM
            dampingRatio = SpringForce.DAMPING_RATIO_MEDIUM_BOUNCY
        }
        springX.spring = force
        springY.spring = force

        var isEndCalled = false
        springX.addEndListener { _, _, _, _ ->
            if (!isEndCalled) {
                isEndCalled = true
                onEnd?.invoke()
            }
        }

        alphaAnim.start()
        springX.start()
        springY.start()
    }

    /**
     * Fade + translateY-up entrance — for header or message bubbles.
     */
    fun slideInUp(
        view      : View,
        fromDpY   : Float = 24f,
        durationMs: Long  = 280,
        onEnd     : (() -> Unit)? = null,
    ): AnimatorSet {
        val density = view.resources.displayMetrics.density
        val fromPx  = fromDpY * density
        view.translationY = fromPx; view.alpha = 0f

        val ty = ObjectAnimator.ofFloat(view, View.TRANSLATION_Y, fromPx, 0f)
        val fa = ObjectAnimator.ofFloat(view, View.ALPHA, 0f, 1f)

        return AnimatorSet().apply {
            playTogether(ty, fa)
            duration     = durationMs
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

    fun fadeOut(
        view      : View,
        durationMs: Long          = 200,
        onEnd     : (() -> Unit)? = null,
    ): ObjectAnimator =
        ObjectAnimator.ofFloat(view, View.ALPHA, view.alpha, 0f).apply {
            duration     = durationMs
            interpolator = EASE_IN_OUT
            onEnd?.let { doOnEnd { it() } }
            start()
        }

    // ─────────────────────────────────────────────────────────────────────
    // ATTENTION / FEEDBACK
    // ─────────────────────────────────────────────────────────────────────

    /**
     * Horizontal shake — used to indicate an error or boundary hit.
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
        onEnd        : (() -> Unit)? = null,
    ) {
        val springX = SpringAnimation(view, DynamicAnimation.SCALE_X, peakScale)
        val springY = SpringAnimation(view, DynamicAnimation.SCALE_Y, peakScale)

        val forceUp = SpringForce(peakScale).apply {
            stiffness    = SpringForce.STIFFNESS_MEDIUM
            dampingRatio = SpringForce.DAMPING_RATIO_MEDIUM_BOUNCY
        }
        springX.spring = forceUp
        springY.spring = forceUp

        springX.addEndListener { _, _, _, _ ->
            val downX = SpringAnimation(view, DynamicAnimation.SCALE_X, 1f)
            val downY = SpringAnimation(view, DynamicAnimation.SCALE_Y, 1f)

            val forceDown = SpringForce(1f).apply {
                stiffness    = SpringForce.STIFFNESS_MEDIUM
                dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
            }
            downX.spring = forceDown
            downY.spring = forceDown

            var isEndCalled = false
            downX.addEndListener { _, _, _, _ ->
                if (!isEndCalled) {
                    isEndCalled = true
                    onEnd?.invoke()
                }
            }
            downX.start()
            downY.start()
        }

        springX.start()
        springY.start()
    }

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
        val scaleDownX = SpringAnimation(view, DynamicAnimation.SCALE_X, 0f)
        val scaleDownY = SpringAnimation(view, DynamicAnimation.SCALE_Y, 0f)

        val forceDown = SpringForce(0f).apply {
            stiffness    = SpringForce.STIFFNESS_HIGH
            dampingRatio = SpringForce.DAMPING_RATIO_NO_BOUNCY
        }
        scaleDownX.spring = forceDown
        scaleDownY.spring = forceDown

        scaleDownX.addEndListener { _, _, _, _ ->
            onSwap()

            val scaleUpX = SpringAnimation(view, DynamicAnimation.SCALE_X, 1f)
            val scaleUpY = SpringAnimation(view, DynamicAnimation.SCALE_Y, 1f)

            val forceUp = SpringForce(1f).apply {
                stiffness    = SpringForce.STIFFNESS_MEDIUM
                dampingRatio = SpringForce.DAMPING_RATIO_MEDIUM_BOUNCY
            }
            scaleUpX.spring = forceUp
            scaleUpY.spring = forceUp

            scaleUpX.start()
            scaleUpY.start()
        }

        scaleDownX.start()
        scaleDownY.start()
    }

    // ─────────────────────────────────────────────────────────────────────
    // COLOUR TRANSITION
    // ─────────────────────────────────────────────────────────────────────

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

    fun cancelAllSprings(vararg springs: DynamicAnimation<*>?) {
        springs.forEach { it?.cancel() }
    }
}
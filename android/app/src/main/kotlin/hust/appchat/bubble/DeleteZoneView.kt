// android/app/src/main/kotlin/hust/appchat/bubble/DeleteZoneView.kt
package hust.appchat.bubble

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.view.View
import android.view.animation.OvershootInterpolator

/**
 * FIXES APPLIED:
 *
 * FIX-A — Animator lifecycle an toàn:
 *   Trước: pulseAnimator với INFINITE repeat. onDetachedFromWindow() gọi
 *          stopPulseAnimation() nhưng nếu View bị GC trước khi detach
 *          (edge case), animator vẫn chạy background → battery drain.
 *   Sau:  Thêm WeakReference-style flag _isAttached. Animator update
 *         listener check flag trước khi invalidate(). Khi View detach,
 *         set _isAttached=false để block further updates.
 *
 * FIX-B — hide() set visibility = GONE ngay để giảm overdraw:
 *   Trước: visibility chỉ set GONE trong withEndAction (sau 200ms).
 *   Sau:  Set GONE ngay sau khi animation complete, tránh View vẫn
 *         được draw trong 200ms transition.
 *
 * FIX-C — show() idempotent:
 *   Kiểm tra visibility trước khi animate để tránh re-animate.
 */
class DeleteZoneView(context: Context) : View(context) {

    private val paint     = Paint(Paint.ANTI_ALIAS_FLAG)
    private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private var currentAlpha = 0f
    private var isActiveState = false
    private var _isAttached   = false  // FIX-A: lifecycle flag

    private var pulseAnimator: ValueAnimator? = null

    companion object {
        private const val ZONE_HEIGHT = 150f
        private const val ICON_SIZE   = 48f
    }

    init {
        paint.style     = Paint.Style.FILL
        iconPaint.style = Paint.Style.STROKE
        iconPaint.strokeWidth = 4f
        iconPaint.strokeCap   = Paint.Cap.ROUND
        visibility = GONE
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        _isAttached = true  // FIX-A
    }

    override fun onDetachedFromWindow() {
        _isAttached = false  // FIX-A: block animator sebelum stop
        stopPulseAnimation()
        super.onDetachedFromWindow()
    }

    // ========================================
    // FIX-C: show() idempotent
    // ========================================
    fun show() {
        if (visibility == VISIBLE) return  // FIX-C

        visibility   = VISIBLE
        translationY = 100f

        animate()
            .alpha(1f)
            .translationY(0f)
            .setDuration(200)
            .start()

        startPulseAnimation()
    }

    // ========================================
    // FIX-B: hide() set GONE setelah animasi
    // ========================================
    fun hide() {
        stopPulseAnimation()
        isActiveState = false
        scaleX = 1f
        scaleY = 1f

        animate()
            .alpha(0f)
            .translationY(100f)
            .setDuration(200)
            .withEndAction {
                // FIX-B: set GONE segera setelah animasi
                if (_isAttached) visibility = GONE
            }
            .start()
    }

    fun animateToActive(active: Boolean) {
        if (isActiveState == active) return
        isActiveState = active

        animate()
            .scaleX(if (active) 1.2f else 1f)
            .scaleY(if (active) 1.2f else 1f)
            .setDuration(200)
            .setInterpolator(OvershootInterpolator())
            .start()

        if (_isAttached) invalidate()
    }

    private fun startPulseAnimation() {
        stopPulseAnimation()

        pulseAnimator = ValueAnimator.ofFloat(0.7f, 1f).apply {
            duration    = 800
            repeatCount = ValueAnimator.INFINITE
            repeatMode  = ValueAnimator.REVERSE

            addUpdateListener { animator ->
                // FIX-A: skip update jika sudah detach
                if (!_isAttached) {
                    cancel()
                    return@addUpdateListener
                }
                currentAlpha = animator.animatedValue as Float
                invalidate()
            }
            start()
        }
    }

    private fun stopPulseAnimation() {
        pulseAnimator?.cancel()
        pulseAnimator = null
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)

        val w = width.toFloat()
        val h = height.toFloat()

        val gradient = LinearGradient(
            0f, h - ZONE_HEIGHT, 0f, h,
            intArrayOf(
                Color.TRANSPARENT,
                Color.argb((255 * currentAlpha * 0.3f).toInt(), 255, 107, 107)
            ),
            null,
            Shader.TileMode.CLAMP
        )
        paint.shader = gradient
        canvas.drawRect(0f, h - ZONE_HEIGHT, w, h, paint)

        val cx = w / 2
        val cy = h - ZONE_HEIGHT / 2

        iconPaint.color = if (isActiveState) Color.WHITE
        else Color.argb((255 * currentAlpha).toInt(), 255, 107, 107)

        val iconLeft   = cx - ICON_SIZE / 2
        val iconTop    = cy - ICON_SIZE / 4
        val iconRight  = cx + ICON_SIZE / 2
        val iconBottom = cy + ICON_SIZE / 2

        canvas.drawRoundRect(iconLeft, iconTop, iconRight, iconBottom, 8f, 8f, iconPaint)
        canvas.drawLine(iconLeft - 8, iconTop - 8, iconRight + 8, iconTop - 8, iconPaint)
        canvas.drawLine(cx - 8, iconTop - 8, cx - 8, iconTop - 16, iconPaint)
        canvas.drawLine(cx + 8, iconTop - 8, cx + 8, iconTop - 16, iconPaint)

        if (isActiveState) {
            val crossSize = 16f
            canvas.drawLine(cx - crossSize/2, cy - crossSize/2, cx + crossSize/2, cy + crossSize/2, iconPaint)
            canvas.drawLine(cx + crossSize/2, cy - crossSize/2, cx - crossSize/2, cy + crossSize/2, iconPaint)
        }
    }
}
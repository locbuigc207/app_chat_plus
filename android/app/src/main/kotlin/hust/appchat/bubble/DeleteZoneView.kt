package hust.appchat.bubble

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.view.View
import android.view.animation.OvershootInterpolator

/**
 * ✅ Delete Zone Indicator - Hiện ở bottom của màn hình khi drag bubble
 */
class DeleteZoneView(context: Context) : View(context) {

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    private var currentAlpha = 0f
    private var isActiveState = false

    private var pulseAnimator: ValueAnimator? = null

    companion object {
        private const val ZONE_HEIGHT = 150f
        private const val ICON_SIZE = 48f
    }

    init {
        paint.style = Paint.Style.FILL
        iconPaint.style = Paint.Style.STROKE
        iconPaint.strokeWidth = 4f
        iconPaint.strokeCap = Paint.Cap.ROUND

        visibility = GONE
    }

    fun show() {
        if (visibility == VISIBLE) return

        visibility = VISIBLE
        // Bắt đầu từ dưới màn hình
        translationY = 100f

        animate()
            .alpha(1f)
            .translationY(0f)
            .setDuration(200)
            .start()

        startPulseAnimation()
    }

    fun hide() {
        stopPulseAnimation()

        // Đặt lại trạng thái Active khi ẩn
        isActiveState = false
        scaleX = 1f
        scaleY = 1f

        animate()
            .alpha(0f)
            .translationY(100f) // Trượt xuống để ẩn
            .setDuration(200)
            .withEndAction {
                visibility = GONE
            }
            .start()
    }

    /**
     * ✅ FIX: Đổi tên từ setActive thành animateToActive để khớp với BubbleOverlayService.kt
     */
    fun animateToActive(active: Boolean) {
        if (isActiveState == active) return
        isActiveState = active

        animate()
            .scaleX(if (active) 1.2f else 1f)
            .scaleY(if (active) 1.2f else 1f)
            .setDuration(200)
            .setInterpolator(OvershootInterpolator())
            .start()

        // Yêu cầu vẽ lại để cập nhật màu sắc/icon của thùng rác
        invalidate()
    }

    private fun startPulseAnimation() {
        pulseAnimator?.cancel()

        pulseAnimator = ValueAnimator.ofFloat(0.7f, 1f).apply {
            duration = 800
            repeatCount = ValueAnimator.INFINITE
            repeatMode = ValueAnimator.REVERSE

            addUpdateListener {
                currentAlpha = it.animatedValue as Float
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

        val width = width.toFloat()
        val height = height.toFloat()

        // Background gradient
        val gradient = LinearGradient(
            0f, height - ZONE_HEIGHT,
            0f, height,
            intArrayOf(
                Color.TRANSPARENT,
                // Điều chỉnh độ trong suốt của màu đỏ dựa trên currentAlpha (cho hiệu ứng pulse)
                Color.argb((255 * currentAlpha * 0.3f).toInt(), 255, 107, 107)
            ),
            null,
            Shader.TileMode.CLAMP
        )
        paint.shader = gradient
        canvas.drawRect(0f, height - ZONE_HEIGHT, width, height, paint)

        // Delete icon (trash can)
        val centerX = width / 2
        val centerY = height - ZONE_HEIGHT / 2

        iconPaint.color = if (isActiveState) {
            Color.WHITE // Trắng khi Active
        } else {
            // Màu đỏ nhạt hơn, pulse theo currentAlpha
            Color.argb((255 * currentAlpha).toInt(), 255, 107, 107)
        }

        // Trash can body
        val iconLeft = centerX - ICON_SIZE / 2
        val iconTop = centerY - ICON_SIZE / 4
        val iconRight = centerX + ICON_SIZE / 2
        val iconBottom = centerY + ICON_SIZE / 2

        // Vẽ thùng rác (body)
        canvas.drawRoundRect(
            iconLeft, iconTop, iconRight, iconBottom,
            8f, 8f, iconPaint
        )

        // Trash can lid (nắp thùng rác)
        canvas.drawLine(
            iconLeft - 8, iconTop - 8,
            iconRight + 8, iconTop - 8,
            iconPaint
        )

        // Handle (tay cầm)
        canvas.drawLine(
            centerX - 8, iconTop - 8,
            centerX - 8, iconTop - 16,
            iconPaint
        )
        canvas.drawLine(
            centerX + 8, iconTop - 8,
            centerX + 8, iconTop - 16,
            iconPaint
        )

        // X marks inside (Active state visual)
        if (isActiveState) {
            val crossSize = 16f
            canvas.drawLine(
                centerX - crossSize / 2, centerY - crossSize / 2,
                centerX + crossSize / 2, centerY + crossSize / 2,
                iconPaint
            )
            canvas.drawLine(
                centerX + crossSize / 2, centerY - crossSize / 2,
                centerX - crossSize / 2, centerY + crossSize / 2,
                iconPaint
            )
        }
    }

    override fun onDetachedFromWindow() {
        stopPulseAnimation()
        super.onDetachedFromWindow()
    }
}
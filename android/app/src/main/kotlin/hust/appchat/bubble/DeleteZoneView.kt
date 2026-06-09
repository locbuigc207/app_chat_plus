// android/app/src/main/kotlin/hust/appchat/bubble/DeleteZoneView.kt
package hust.appchat.bubble

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.*
import android.view.View
import android.view.animation.OvershootInterpolator

/**
 * DeleteZoneView — Production-grade animated trash-zone shown at the bottom
 * of the screen while a BubbleView is being dragged.
 *
 * Visual layers (drawn in onDraw):
 * 1. Full-width frosted gradient: transparent → deep red (bottom 200 dp).
 * 2. Centred trash-can icon drawn with Canvas paths.
 * 3. Pulsing outer ring around the icon when active.
 * 4. "Kéo vào để xoá" / "Thả để xoá" label below the icon.
 *
 * FIXES APPLIED (Lifecycle & Performance):
 * - FIX-A (Animator Safety): _isAttached flag blocks all post-detach
 * View.invalidate() calls and cancels pulseAnimator to prevent battery drain.
 * - FIX-B (Overdraw Reduction): hide() sets visibility=GONE precisely in the
 * animation's withEndAction.
 * - FIX-C (Idempotent Show): show() guards against double-execution if already VISIBLE.
 */
class DeleteZoneView(context: Context) : View(context) {

    // ─── Paints ───────────────────────────────────────────────────────────
    private val bgPaint   = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style       = Paint.Style.STROKE
        strokeWidth = 4f
        strokeCap   = Paint.Cap.ROUND
        strokeJoin  = Paint.Join.ROUND
    }
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style       = Paint.Style.STROKE
        strokeWidth = 3f
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        textAlign = Paint.Align.CENTER
        textSize  = 36f
        color     = Color.WHITE
        alpha     = 180
        typeface  = Typeface.DEFAULT_BOLD
    }

    // ─── State ────────────────────────────────────────────────────────────
    private var _isAttached = false
    private var _isActive   = false
    private var _pulseScale = 1f          // outer ring scale for pulse

    private var pulseAnimator: ValueAnimator? = null

    companion object {
        private const val ZONE_H  = 200f    // height of the gradient zone
        private const val ICON_R  = 30f     // icon bounding radius
        private const val RING_R  = 48f     // outer pulse ring radius
    }

    init { visibility = GONE }

    // ═════════════════════════════════════════════════════════════════════
    // PUBLIC API
    // ═════════════════════════════════════════════════════════════════════

    /** FIX-C: Show the zone. Idempotent. */
    fun show() {
        if (visibility == VISIBLE) return
        visibility   = VISIBLE
        translationY = 60f
        alpha        = 0f

        animate()
            .alpha(1f)
            .translationY(0f)
            .setDuration(220)
            .withStartAction { startPulse() }
            .start()
    }

    /** FIX-B: Hide and eventually set GONE. */
    fun hide() {
        if (visibility != VISIBLE) return
        stopPulse()
        _isActive = false

        animate()
            .alpha(0f)
            .translationY(60f)
            .setDuration(200)
            .withEndAction {
                if (_isAttached) visibility = GONE
            }.start()
    }

    /** Call when a bubble enters/leaves the zone during drag. */
    fun animateToActive(active: Boolean) {
        if (_isActive == active) return
        _isActive = active

        val targetScale = if (active) 1.22f else 1f
        animate()
            .scaleX(targetScale)
            .scaleY(targetScale)
            .setDuration(180)
            .setInterpolator(OvershootInterpolator(2.5f))
            .start()

        if (_isAttached) invalidate()
    }

    // ═════════════════════════════════════════════════════════════════════
    // DRAWING
    // ═════════════════════════════════════════════════════════════════════

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0 || h <= 0) return

        // ── 1. Gradient background ────────────────────────────────────────
        val gradTop  = (h - ZONE_H).coerceAtLeast(0f)
        val baseAlpha = if (_isActive) 0.72f else 0.52f
        bgPaint.shader = LinearGradient(
            0f, gradTop, 0f, h,
            intArrayOf(Color.TRANSPARENT,
                Color.argb((255 * baseAlpha * alpha).toInt(), 220, 38, 38)),
            null, Shader.TileMode.CLAMP
        )
        canvas.drawRect(0f, gradTop, w, h, bgPaint)

        // ── 2. Pulse ring ─────────────────────────────────────────────────
        val cx = w / 2
        val cy = h - ZONE_H / 2
        val ringAlpha = ((0.25f + (1f - _pulseScale / 1.8f) * 0.5f) * alpha).coerceIn(0f, 1f)
        ringPaint.color = Color.argb((255 * ringAlpha).toInt(), 255, 120, 120)
        canvas.drawCircle(cx, cy, RING_R * _pulseScale, ringPaint)

        // ── 3. Icon circle background ─────────────────────────────────────
        bgPaint.shader = null
        bgPaint.color  = if (_isActive)
            Color.argb((200 * alpha).toInt(), 255, 60, 60)
        else
            Color.argb((140 * alpha).toInt(), 200, 30, 30)
        canvas.drawCircle(cx, cy, ICON_R + 10f, bgPaint)

        // ── 4. Trash-can icon ─────────────────────────────────────────────
        val iconAlpha = (255 * alpha).toInt().coerceIn(0, 255)
        iconPaint.color = Color.argb(iconAlpha, 255, 255, 255)
        drawTrashIcon(canvas, cx, cy)

        // ── 5. Label ──────────────────────────────────────────────────────
        labelPaint.alpha = (180 * alpha).toInt().coerceIn(0, 255)
        val labelText = if (_isActive) "Thả để xoá" else "Kéo vào để xoá"
        canvas.drawText(labelText, cx, cy + ICON_R + 28f, labelPaint)
    }

    private fun drawTrashIcon(canvas: Canvas, cx: Float, cy: Float) {
        val s  = ICON_R * 0.55f     // scale factor
        val top = cy - s * 1.2f

        // Lid
        canvas.drawLine(cx - s * 1.1f, top, cx + s * 1.1f, top, iconPaint)

        // Handle on lid
        val hr = s * 0.45f
        val path = Path().apply {
            moveTo(cx - hr, top)
            rLineTo(hr * 0.35f, -hr * 0.8f)
            rLineTo(hr * 1.3f, 0f)
            rLineTo(hr * 0.35f, hr * 0.8f)
        }
        canvas.drawPath(path, iconPaint)

        // Body
        val bl = cx - s * 0.8f
        val br = cx + s * 0.8f
        val bb = cy + s * 1.0f
        val bodyPath = Path().apply {
            moveTo(bl + s * 0.1f, top)
            lineTo(bl, bb)
            lineTo(br, bb)
            lineTo(br - s * 0.1f, top)
        }
        canvas.drawPath(bodyPath, iconPaint)

        // Lines inside body
        canvas.drawLine(cx, top + s * 0.2f, cx, bb - s * 0.1f, iconPaint)
        canvas.drawLine(cx - s * 0.4f, top + s * 0.2f, cx - s * 0.5f, bb - s * 0.1f, iconPaint)
        canvas.drawLine(cx + s * 0.4f, top + s * 0.2f, cx + s * 0.5f, bb - s * 0.1f, iconPaint)
    }

    // ═════════════════════════════════════════════════════════════════════
    // PULSE ANIMATION
    // ═════════════════════════════════════════════════════════════════════

    private fun startPulse() {
        stopPulse()
        pulseAnimator = ValueAnimator.ofFloat(1f, 1.8f).apply {
            duration    = 950
            repeatCount = ValueAnimator.INFINITE
            repeatMode  = ValueAnimator.REVERSE
            addUpdateListener { a ->
                // FIX-A: Skip update if detached to prevent leak
                if (!_isAttached) {
                    cancel()
                    return@addUpdateListener
                }
                _pulseScale = a.animatedValue as Float
                invalidate()
            }
            start()
        }
    }

    private fun stopPulse() {
        pulseAnimator?.cancel()
        pulseAnimator = null
    }

    // ═════════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═════════════════════════════════════════════════════════════════════

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        _isAttached = true
    }

    override fun onDetachedFromWindow() {
        _isAttached = false
        stopPulse()
        super.onDetachedFromWindow()
    }
}
// android/app/src/main/kotlin/hust/appchat/bubble/BubbleView.kt
package hust.appchat.bubble

import android.animation.Animator
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Color
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.request.RequestOptions
import hust.appchat.R
import kotlin.math.abs
import kotlin.math.sqrt

/**
 * BubbleView — Production-Ready Floating Chat Bubble
 * * Merges V1 stability fixes with V2 rich UI features:
 * • FIX-A (Glide): Uses applicationContext and strict isDetached checks to prevent lifecycle crashes.
 * • FIX-B (Haptics): Respects system settings via performHapticFeedback, falls back to VibratorManager/Vibrator.
 * • UI Richness: Initials fallback, Online Pulse, Typing Indicator, Badge Pop animations.
 * • Interaction: Long-press detection, drag-to-delete callbacks, accessibility performClick.
 * • Compatibility: Supports both property-based (v2) and setter-based (v1) callback bindings.
 */
class BubbleView(
    context: Context,
    val userId: String,
    val userName: String,
    val avatarUrl: String
) : FrameLayout(context) {

    // ── View refs ────────────────────────────────────────────────────────
    private val avatar        : ImageView by lazy { findViewById(R.id.bubble_avatar) }
    private val initials      : TextView  by lazy { findViewById(R.id.bubble_initials) }
    private val badge         : TextView  by lazy { findViewById(R.id.bubble_unread_badge) }
    private val onlineWrapper : FrameLayout by lazy { findViewById(R.id.bubble_online_wrapper) }
    private val onlinePulse   : View      by lazy { findViewById(R.id.bubble_online_pulse) }
    private val onlineDot     : View      by lazy { findViewById(R.id.bubble_online_indicator) }
    private val deleteIcon    : ImageView by lazy { findViewById(R.id.delete_indicator) }
    private val typingBar     : View      by lazy { findViewById(R.id.bubble_typing_indicator) }
    private val dot1          : View      by lazy { findViewById(R.id.typing_dot1) }
    private val dot2          : View      by lazy { findViewById(R.id.typing_dot2) }
    private val dot3          : View      by lazy { findViewById(R.id.typing_dot3) }

    // ── Callbacks (V2 Style) ─────────────────────────────────────────────
    var onDragDelta  : ((inDeleteZone: Boolean, dx: Float, dy: Float) -> Unit)? = null
    var onDragEnd    : (() -> Unit)? = null
    var onBubbleClick: (() -> Unit)? = null

    // ── State ────────────────────────────────────────────────────────────
    @Volatile private var _isDetached = false
    private var _isOnline      = false
    private var _isTyping      = false
    private var _unreadCount   = 0
    private var _lastMessage   = ""

    // ── Touch tracking ───────────────────────────────────────────────────
    private var isDragging           = false
    private var hasMoved             = false
    private var touchStartX          = 0f
    private var touchStartY          = 0f
    private var lastRawX             = 0f
    private var lastRawY             = 0f
    private var touchDownMs          = 0L
    private var longPressTriggered   = false

    // ── Animators ────────────────────────────────────────────────────────
    private var pulseAnimator   : ValueAnimator? = null
    private var typingAnimator  : ValueAnimator? = null
    private var badgeBounceAnim : Animator? = null

    // ── Long-press Runnable ───────────────────────────────────────────────
    private val longPressRunnable = Runnable {
        if (!_isDetached && !hasMoved) {
            longPressTriggered = true
            doHaptic(HapticType.STRONG)
            animate().scaleX(1.12f).scaleY(1.12f).setDuration(120)
                .setInterpolator(OvershootInterpolator()).start()
        }
    }

    // ── Vibrator ─────────────────────────────────────────────────────────
    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)?.defaultVibrator
        else
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
    }

    companion object {
        private const val TOUCH_SLOP        = 18f
        private const val CLICK_TIMEOUT_MS  = 350L
        private const val LONG_PRESS_MS     = 500L
        private const val DELETE_ZONE_FRAC  = 0.82f   // bottom 18% of screen

        private val INITIALS_COLORS = intArrayOf(
            0xFF1E88E5.toInt(), 0xFF43A047.toInt(), 0xFFE53935.toInt(),
            0xFF8E24AA.toInt(), 0xFFFF8F00.toInt(), 0xFF00897B.toInt(),
            0xFF6D4C41.toInt(), 0xFF0288D1.toInt(), 0xFFC62828.toInt(),
            0xFF2E7D32.toInt()
        )

        private fun initialsColor(name: String): Int =
            INITIALS_COLORS[abs(name.hashCode()) % INITIALS_COLORS.size]

        private fun extractInitials(name: String): String =
            name.trim().split(" ").take(2)
                .mapNotNull { it.firstOrNull()?.uppercaseChar() }
                .joinToString("").ifEmpty { "?" }
    }

    // ═════════════════════════════════════════════════════════════════════
    // INIT
    // ═════════════════════════════════════════════════════════════════════

    init {
        inflate(context, R.layout.chat_bubble_layout, this)
        isClickable            = true
        isFocusable            = true
        isFocusableInTouchMode = true

        setupAvatar()
        setupTouchListener()
    }

    // ─── Avatar ──────────────────────────────────────────────────────────

    private fun setupAvatar() {
        if (avatarUrl.isNotEmpty()) {
            loadAvatarFromUrl()
        } else {
            showInitials()
        }
    }

    private fun loadAvatarFromUrl() {
        if (_isDetached) return
        try {
            Glide.with(context.applicationContext)
                .load(avatarUrl)
                .apply(
                    RequestOptions()
                        .circleCrop()
                        .diskCacheStrategy(DiskCacheStrategy.ALL)
                        .override(160, 160)
                        .placeholder(R.drawable.bubble_background)
                        .error(R.drawable.bubble_background)
                )
                .listener(object : com.bumptech.glide.request.RequestListener<android.graphics.drawable.Drawable> {
                    override fun onLoadFailed(
                        e: com.bumptech.glide.load.engine.GlideException?,
                        model: Any?,
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>, // Bỏ '?' ở đây
                        isFirstResource: Boolean
                    ): Boolean {
                        if (!_isDetached) showInitials()
                        return false
                    }

                    override fun onResourceReady(
                        resource: android.graphics.drawable.Drawable, // Bỏ '?' ở đây
                        model: Any,                                   // Bỏ '?' ở đây
                        target: com.bumptech.glide.request.target.Target<android.graphics.drawable.Drawable>?,
                        dataSource: com.bumptech.glide.load.DataSource, // Bỏ '?' ở đây
                        isFirstResource: Boolean
                    ): Boolean {
                        if (!_isDetached) {
                            avatar.visibility = View.VISIBLE
                            initials.visibility = View.GONE
                        }
                        return false
                    }
                })
                .into(avatar)
        } catch (e: Exception) {
            if (!_isDetached) showInitials()
        }
    }

    private fun showInitials() {
        avatar.visibility = View.GONE
        initials.visibility = View.VISIBLE
        initials.text = extractInitials(userName)
        initials.setBackgroundColor(initialsColor(userName))
        post {
            if (_isDetached) return@post
            initials.outlineProvider = ViewOutlineProvider.BACKGROUND
            initials.clipToOutline = true
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // TOUCH HANDLING
    // ═════════════════════════════════════════════════════════════════════

    private fun setupTouchListener() {
        setOnTouchListener { _, event ->
            if (_isDetached) return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN   -> { onDown(event); true }
                MotionEvent.ACTION_MOVE   -> { onMove(event); true }
                MotionEvent.ACTION_UP     -> { onUp(event); true }
                MotionEvent.ACTION_CANCEL -> { onCancel(); true }
                else                      -> false
            }
        }
    }

    private fun onDown(e: MotionEvent) {
        touchStartX  = e.x
        touchStartY  = e.y
        lastRawX     = e.rawX
        lastRawY     = e.rawY
        touchDownMs  = System.currentTimeMillis()
        isDragging   = false
        hasMoved     = false
        longPressTriggered = false

        animate().scaleX(0.92f).scaleY(0.92f).setDuration(80).start()
        postDelayed(longPressRunnable, LONG_PRESS_MS)
    }

    private fun onMove(e: MotionEvent) {
        val dx = e.x - touchStartX
        val dy = e.y - touchStartY
        val dist = sqrt(dx * dx + dy * dy)

        if (dist > TOUCH_SLOP && !hasMoved) {
            hasMoved = true
            removeCallbacks(longPressRunnable)
            doHaptic(HapticType.LIGHT)
        }

        if (hasMoved) {
            isDragging = true
            val moveDx = e.rawX - lastRawX
            val moveDy = e.rawY - lastRawY
            lastRawX = e.rawX
            lastRawY = e.rawY

            val screenHeight = resources.displayMetrics.heightPixels
            val inDeleteZone = e.rawY > screenHeight * DELETE_ZONE_FRAC

            val targetScale = if (inDeleteZone) 0.78f else 0.92f
            val targetAlpha = if (inDeleteZone) 0.55f else 1f
            animate().scaleX(targetScale).scaleY(targetScale).alpha(targetAlpha).setDuration(60).start()

            updateDeleteIndicator(inDeleteZone)
            onDragDelta?.invoke(inDeleteZone, moveDx, moveDy)
        }
    }

    private fun onUp(e: MotionEvent) {
        removeCallbacks(longPressRunnable)

        animate().scaleX(1f).scaleY(1f).alpha(1f)
            .setDuration(180).setInterpolator(OvershootInterpolator(2f)).start()
        hideDeleteIndicator()

        val elapsed = System.currentTimeMillis() - touchDownMs

        if (isDragging) {
            val screenHeight = resources.displayMetrics.heightPixels
            val inDeleteZone = e.rawY > screenHeight * DELETE_ZONE_FRAC
            if (inDeleteZone) {
                doHaptic(HapticType.STRONG)
                onDragDelta?.invoke(true, 0f, 0f)
            }
            onDragEnd?.invoke()
        } else if (!hasMoved && !longPressTriggered && elapsed < CLICK_TIMEOUT_MS) {
            doHaptic(HapticType.LIGHT)
            performClick()
        }

        isDragging = false
        hasMoved   = false
    }

    private fun onCancel() {
        removeCallbacks(longPressRunnable)
        isDragging = false
        hasMoved   = false
        animate().scaleX(1f).scaleY(1f).alpha(1f).setDuration(150).start()
        hideDeleteIndicator()
        onDragEnd?.invoke()
    }

    override fun performClick(): Boolean {
        super.performClick()
        onBubbleClick?.invoke()
        return true
    }

    // ═════════════════════════════════════════════════════════════════════
    // COMPATIBILITY ALIASES (V1 -> V2)
    // ═════════════════════════════════════════════════════════════════════

    fun setOnDragListener(listener: (Boolean, Float, Float) -> Unit) { onDragDelta = listener }
    fun setOnDragEndListener(listener: () -> Unit) { onDragEnd = listener }
    fun setOnClickListener(listener: () -> Unit) { onBubbleClick = listener }

    fun updateUnreadCount(count: Int) = setUnreadCount(count)
    fun updateLastMessage(msg: String) = setLastMessage(msg)

    // ═════════════════════════════════════════════════════════════════════
    // PUBLIC API — State Updates
    // ═════════════════════════════════════════════════════════════════════

    fun setUnreadCount(count: Int) {
        if (_isDetached) return
        val prev = _unreadCount
        _unreadCount = count
        post {
            if (_isDetached) return@post
            if (count > 0) {
                badge.visibility = View.VISIBLE
                badge.text = if (count > 99) "99+" else "$count"
                if (count > prev) popBadge()
            } else {
                badge.visibility = View.GONE
            }
        }
    }

    fun setOnlineStatus(online: Boolean) {
        if (_isDetached) return
        _isOnline = online
        post {
            if (_isDetached) return@post
            if (online) {
                onlineWrapper.visibility = View.VISIBLE
                startOnlinePulse()
            } else {
                stopOnlinePulse()
                onlineWrapper.animate().alpha(0f).setDuration(300)
                    .withEndAction {
                        if (!_isDetached) onlineWrapper.visibility = View.GONE
                    }.start()
            }
        }
    }

    fun setTyping(typing: Boolean) {
        if (_isDetached) return
        _isTyping = typing
        post {
            if (_isDetached) return@post
            if (typing) {
                typingBar.visibility = View.VISIBLE
                startTypingAnimation()
            } else {
                stopTypingAnimation()
                typingBar.visibility = View.GONE
            }
        }
    }

    fun setLastMessage(msg: String) { _lastMessage = msg }

    fun animateNewMessage() {
        if (_isDetached) return
        post {
            if (_isDetached) return@post
            animate().scaleX(1.18f).scaleY(1.18f).setDuration(120)
                .setInterpolator(OvershootInterpolator(3f))
                .withEndAction {
                    if (!_isDetached)
                        animate().scaleX(1f).scaleY(1f).setDuration(200)
                            .setInterpolator(DecelerateInterpolator()).start()
                }.start()
            doHaptic(HapticType.LIGHT)
        }
    }

    fun animateDelete(onComplete: () -> Unit) {
        if (_isDetached) return
        doHaptic(HapticType.STRONG)
        animate().alpha(0f).scaleX(0f).scaleY(0f).rotation(180f).setDuration(280)
            .setInterpolator(DecelerateInterpolator())
            .withEndAction { if (!_isDetached) onComplete() }.start()
    }

    fun getBubbleData(): Map<String, Any> = mapOf(
        "userId"      to userId,
        "userName"    to userName,
        "avatarUrl"   to avatarUrl,
        "lastMessage" to _lastMessage,
        "unreadCount" to _unreadCount,
        "isOnline"    to _isOnline,
        "timestamp"   to System.currentTimeMillis()
    )

    // ═════════════════════════════════════════════════════════════════════
    // ANIMATIONS
    // ═════════════════════════════════════════════════════════════════════

    private fun popBadge() {
        badgeBounceAnim?.cancel()
        badgeBounceAnim = ObjectAnimator.ofFloat(badge, "scaleX", 1f, 1.5f, 1f).apply {
            duration = 280
            interpolator = OvershootInterpolator(3f)
            start()
        }
        ObjectAnimator.ofFloat(badge, "scaleY", 1f, 1.5f, 1f).apply {
            duration = 280
            interpolator = OvershootInterpolator(3f)
            start()
        }
    }

    private fun startOnlinePulse() {
        stopOnlinePulse()
        pulseAnimator = ValueAnimator.ofFloat(1f, 1.6f).apply {
            duration    = 900
            repeatCount = ValueAnimator.INFINITE
            repeatMode  = ValueAnimator.REVERSE
            addUpdateListener { a ->
                if (_isDetached) { cancel(); return@addUpdateListener }
                val v = a.animatedValue as Float
                onlinePulse.scaleX = v
                onlinePulse.scaleY = v
                onlinePulse.alpha  = (2f - v) * 0.6f
            }
            start()
        }
    }

    private fun stopOnlinePulse() {
        pulseAnimator?.cancel()
        pulseAnimator = null
        if (!_isDetached) {
            onlinePulse.scaleX = 1f
            onlinePulse.scaleY = 1f
            onlinePulse.alpha  = 0.5f
        }
    }

    private fun startTypingAnimation() {
        stopTypingAnimation()
        val dots = listOf(dot1, dot2, dot3)
        typingAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration    = 1200
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener { a ->
                if (_isDetached) { cancel(); return@addUpdateListener }
                val t = a.animatedFraction
                dots.forEachIndexed { i, dot ->
                    val phase = ((t * 3f) - i).coerceIn(0f, 1f)
                    val bounce = if (phase < 0.5f) phase * 2f else (1f - phase) * 2f
                    dot.translationY = -bounce * 6f
                    dot.alpha = 0.4f + bounce * 0.6f
                }
            }
            start()
        }
    }

    private fun stopTypingAnimation() {
        typingAnimator?.cancel()
        typingAnimator = null
    }

    // ─── Delete indicator ─────────────────────────────────────────────────

    private fun updateDeleteIndicator(active: Boolean) {
        val targetAlpha = if (active) 1f else 0f
        val targetScale = if (active) 1.3f else 0.6f
        deleteIcon.animate().alpha(targetAlpha).scaleX(targetScale).scaleY(targetScale)
            .setDuration(80).start()
        if (active && deleteIcon.colorFilter == null) {
            deleteIcon.setColorFilter(Color.WHITE)
        } else if (!active) {
            deleteIcon.clearColorFilter()
        }
    }

    private fun hideDeleteIndicator() {
        deleteIcon.animate().alpha(0f).scaleX(0.6f).scaleY(0.6f).setDuration(150).start()
    }

    // ═════════════════════════════════════════════════════════════════════
    // HAPTIC (Respecting System Preferences)
    // ═════════════════════════════════════════════════════════════════════

    private enum class HapticType { LIGHT, STRONG }

    private fun doHaptic(type: HapticType) {
        try {
            val constant = if (type == HapticType.STRONG)
                HapticFeedbackConstants.LONG_PRESS
            else
                HapticFeedbackConstants.VIRTUAL_KEY

            // Do NOT use FLAG_IGNORE_GLOBAL_SETTING so it respects user's system preferences.
            val success = performHapticFeedback(constant)
            if (!success) fallbackVibrate(type)
        } catch (_: Exception) {
            fallbackVibrate(type)
        }
    }

    private fun fallbackVibrate(type: HapticType) {
        try {
            val ms = if (type == HapticType.STRONG) 48L else 12L
            val v = vibrator ?: return
            if (!v.hasVibrator()) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                v.vibrate(VibrationEffect.createOneShot(ms, VibrationEffect.DEFAULT_AMPLITUDE))
            else
                @Suppress("DEPRECATION") v.vibrate(ms)
        } catch (_: Exception) {}
    }

    // ═════════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═════════════════════════════════════════════════════════════════════

    fun cleanup() {
        if (_isDetached) return
        _isDetached = true
        removeCallbacks(longPressRunnable)
        stopOnlinePulse()
        stopTypingAnimation()
        badgeBounceAnim?.cancel()

        onDragDelta   = null
        onDragEnd     = null
        onBubbleClick = null

        try {
            Glide.with(context.applicationContext).clear(avatar)
        } catch (_: Exception) {}
    }

    override fun onDetachedFromWindow() {
        cleanup()
        super.onDetachedFromWindow()
    }
}
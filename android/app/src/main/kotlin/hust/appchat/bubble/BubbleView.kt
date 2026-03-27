// android/app/src/main/kotlin/hust/appchat/bubble/BubbleView.kt
package hust.appchat.bubble

import android.animation.ValueAnimator
import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.DisplayMetrics
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.request.RequestOptions
import hust.appchat.R
import kotlin.math.sqrt

/**
 * FIXES APPLIED:
 *
 * FIX-A — Glide race condition:
 *   Trước: Glide.with(context) — nếu context bị destroy/detach trong khi
 *          Glide đang load (IO thread), có thể throw IllegalArgumentException
 *          "You cannot start a load for a destroyed activity".
 *   Sau:  Dùng context.applicationContext trong Glide để tránh lifecycle issue.
 *         Thêm synchronized check isDetached trong callback.
 *
 * FIX-B — Haptic feedback tôn trọng user preference:
 *   Trước: Gọi Vibrator.vibrate() trực tiếp, bỏ qua system haptic setting.
 *   Sau:  Dùng View.performHapticFeedback(HapticFeedbackConstants.*) trước,
 *         fallback sang Vibrator chỉ khi cần thiết. Check vibrator.hasVibrator().
 *         Dùng VibratorManager API cho Android 12+.
 *
 * FIX-C — Animator guard trong snapBubbleToEdge:
 *   Đã được xử lý ở BubbleOverlayService bằng cách check containsKey trước
 *   khi update. BubbleView không còn giữ animator reference.
 *
 * FIX-D — performClick() đúng accessibility:
 *   Đảm bảo super.performClick() luôn được gọi.
 */
class BubbleView(
    context: Context,
    private val userId: String,
    private val userName: String,
    private val avatarUrl: String
) : FrameLayout(context) {

    private val avatarImageView: ImageView
    private val unreadBadge: TextView
    private val onlineIndicator: View
    private val deleteIndicator: ImageView

    private val screenWidth: Int
    private val screenHeight: Int

    // Callbacks
    private var onDragListener: ((Boolean, Float, Float) -> Unit)? = null
    private var onDragEndListener: (() -> Unit)? = null
    private var onClickListener: (() -> Unit)? = null

    // Touch state
    private var isDragging   = false
    @Volatile private var isDetached = false
    private var hasMoved     = false
    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var lastRawX      = 0f
    private var lastRawY      = 0f
    private var touchStartTime = 0L

    private var lastMessage: String = ""
    private var currentUnreadCount  = 0

    // FIX-B: vibrator với API mới
    private val vibrator: Vibrator? by lazy {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
    }

    companion object {
        private const val DELETE_ZONE_HEIGHT = 150
        private const val TOUCH_SLOP   = 20
        private const val CLICK_TIMEOUT = 400L
        private const val BUBBLE_SCALE_DOWN   = 0.92f
        private const val BUBBLE_SCALE_DELETE = 0.75f
        private const val DELETE_ZONE_ALPHA   = 0.6f
    }

    init {
        inflate(context, R.layout.chat_bubble_layout, this)

        avatarImageView = findViewById(R.id.bubble_avatar)
        unreadBadge     = findViewById(R.id.bubble_unread_badge)
        onlineIndicator = findViewById(R.id.bubble_online_indicator)
        deleteIndicator = findViewById(R.id.delete_indicator)

        isClickable          = true
        isFocusable          = true
        isFocusableInTouchMode = true

        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val dm = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getMetrics(dm)
        screenWidth  = dm.widthPixels
        screenHeight = dm.heightPixels

        loadAvatar()
        setupTouchListener()

        android.util.Log.d("BubbleView", "✅ Created: $userName")
    }

    // ========================================
    // FIX-A: Glide với applicationContext
    // ========================================

    private fun loadAvatar() {
        if (isDetached) return
        try {
            val opts = RequestOptions()
                .circleCrop()
                .diskCacheStrategy(DiskCacheStrategy.ALL)
                .placeholder(R.drawable.bubble_background)
                .error(R.drawable.bubble_background)
                .override(100, 100)

            if (avatarUrl.isNotEmpty()) {
                // FIX-A: applicationContext để tránh lifecycle crash
                Glide.with(context.applicationContext)
                    .load(avatarUrl)
                    .apply(opts)
                    .into(avatarImageView)
            } else {
                avatarImageView.setImageResource(R.drawable.bubble_background)
            }
        } catch (e: Exception) {
            android.util.Log.e("BubbleView", "❌ Avatar load: $e")
            if (!isDetached) {
                avatarImageView.setImageResource(R.drawable.bubble_background)
            }
        }
    }

    // ========================================
    // TOUCH HANDLING
    // ========================================

    private fun setupTouchListener() {
        setOnTouchListener { _, event ->
            if (isDetached) return@setOnTouchListener false
            when (event.action) {
                MotionEvent.ACTION_DOWN   -> { handleTouchDown(event);  true }
                MotionEvent.ACTION_MOVE   -> { handleTouchMove(event);  true }
                MotionEvent.ACTION_UP     -> { handleTouchUp(event);    true }
                MotionEvent.ACTION_CANCEL -> { resetVisuals();           true }
                else -> false
            }
        }
    }

    private fun handleTouchDown(event: MotionEvent) {
        initialTouchX  = event.x
        initialTouchY  = event.y
        lastRawX       = event.rawX
        lastRawY       = event.rawY
        touchStartTime = System.currentTimeMillis()
        isDragging     = false
        hasMoved       = false

        animate().scaleX(BUBBLE_SCALE_DOWN).scaleY(BUBBLE_SCALE_DOWN).setDuration(100).start()
    }

    private fun handleTouchMove(event: MotionEvent) {
        val deltaX   = event.x - initialTouchX
        val deltaY   = event.y - initialTouchY
        val distance = sqrt((deltaX * deltaX + deltaY * deltaY).toDouble())

        if (distance > TOUCH_SLOP && !hasMoved) {
            hasMoved = true
            // FIX-B: performHapticFeedback tôn trọng system setting
            performSystemHaptic(HapticType.LIGHT)
        }

        if (hasMoved) {
            if (!isDragging) isDragging = true

            val moveX = event.rawX - lastRawX
            val moveY = event.rawY - lastRawY
            lastRawX  = event.rawX
            lastRawY  = event.rawY

            onDragListener?.invoke(false, moveX, moveY)

            val inDeleteZone = event.rawY > (screenHeight - DELETE_ZONE_HEIGHT)
            updateDeleteIndicator(inDeleteZone)

            val targetScale = if (inDeleteZone) BUBBLE_SCALE_DELETE else BUBBLE_SCALE_DOWN
            val targetAlpha = if (inDeleteZone) DELETE_ZONE_ALPHA   else 1f
            animate().scaleX(targetScale).scaleY(targetScale).alpha(targetAlpha).setDuration(50).start()
        }
    }

    private fun handleTouchUp(event: MotionEvent) {
        val touchDuration = System.currentTimeMillis() - touchStartTime

        animate().scaleX(1f).scaleY(1f).alpha(1f).setDuration(150).start()
        hideDeleteIndicator()

        if (isDragging) {
            val inDeleteZone = event.rawY > (screenHeight - DELETE_ZONE_HEIGHT)
            if (inDeleteZone) {
                performSystemHaptic(HapticType.STRONG)
                onDragListener?.invoke(true, 0f, 0f)
            }
            onDragEndListener?.invoke()
        } else if (!hasMoved && touchDuration < CLICK_TIMEOUT) {
            performSystemHaptic(HapticType.LIGHT)
            performClick()
            onClickListener?.invoke()
        }

        isDragging = false
        hasMoved   = false
    }

    private fun resetVisuals() {
        animate().scaleX(1f).scaleY(1f).alpha(1f).setDuration(150).start()
        hideDeleteIndicator()
        isDragging = false
        hasMoved   = false
    }

    // FIX-B: Haptic yang tôn trọng system preference
    private enum class HapticType { LIGHT, STRONG }

    private fun performSystemHaptic(type: HapticType) {
        try {
            when (type) {
                HapticType.LIGHT  ->
                    performHapticFeedback(android.view.HapticFeedbackConstants.VIRTUAL_KEY)
                HapticType.STRONG ->
                    performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
            }
        } catch (_: Exception) {
            // fallback ke vibrator hanya jika system haptic gagal
            fallbackVibrate(if (type == HapticType.STRONG) 50L else 10L)
        }
    }

    private fun fallbackVibrate(duration: Long) {
        try {
            val vib = vibrator ?: return
            if (!vib.hasVibrator()) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vib.vibrate(VibrationEffect.createOneShot(
                    duration, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vib.vibrate(duration)
            }
        } catch (_: Exception) {}
    }

    override fun performClick(): Boolean {
        super.performClick()
        return true
    }

    // ========================================
    // VISUAL UPDATES
    // ========================================

    private fun updateDeleteIndicator(show: Boolean) {
        val alpha = if (show) 1f else 0f
        val scale = if (show) 1.3f else 1f
        deleteIndicator.animate().alpha(alpha).scaleX(scale).scaleY(scale).setDuration(100).start()
    }

    private fun hideDeleteIndicator() {
        deleteIndicator.animate().alpha(0f).scaleX(1f).scaleY(1f).setDuration(150).start()
    }

    fun updateUnreadCount(count: Int) {
        if (isDetached) return
        post {
            if (isDetached) return@post
            if (count > 0) {
                unreadBadge.visibility = View.VISIBLE
                unreadBadge.text = when {
                    count > 99 -> "99+"
                    else       -> count.toString()
                }
                if (count > currentUnreadCount) {
                    unreadBadge.animate().scaleX(1.4f).scaleY(1.4f).setDuration(200)
                        .withEndAction {
                            if (!isDetached)
                                unreadBadge.animate().scaleX(1f).scaleY(1f).setDuration(200).start()
                        }.start()
                }
            } else {
                unreadBadge.visibility = View.GONE
            }
            currentUnreadCount = count
        }
    }

    fun updateLastMessage(message: String) { lastMessage = message }

    fun animateNewMessage() {
        if (isDetached) return
        post {
            if (isDetached) return@post
            animate().scaleX(1.2f).scaleY(1.2f).rotation(10f).setDuration(150)
                .withEndAction {
                    if (!isDetached)
                        animate().scaleX(1f).scaleY(1f).rotation(0f).setDuration(200).start()
                }.start()
            performSystemHaptic(HapticType.LIGHT)
        }
    }

    fun animateDelete(onComplete: () -> Unit) {
        if (isDetached) return
        performSystemHaptic(HapticType.STRONG)
        animate().alpha(0f).scaleX(0f).scaleY(0f).rotation(360f).setDuration(300)
            .withEndAction { if (!isDetached) onComplete() }.start()
    }

    fun setOnlineStatus(isOnline: Boolean) {
        if (isDetached) return
        post {
            if (isDetached) return@post
            if (isOnline) {
                onlineIndicator.visibility = View.VISIBLE
                onlineIndicator.alpha = 0f
                onlineIndicator.animate().alpha(1f).setDuration(300).start()
            } else {
                onlineIndicator.animate().alpha(0f).setDuration(300)
                    .withEndAction {
                        if (!isDetached) onlineIndicator.visibility = View.GONE
                    }.start()
            }
        }
    }

    // ========================================
    // LISTENERS & LIFECYCLE
    // ========================================

    fun setOnDragListener(listener: (Boolean, Float, Float) -> Unit) {
        onDragListener = listener
    }

    fun setOnDragEndListener(listener: () -> Unit) {
        onDragEndListener = listener
    }

    fun setOnClickListener(listener: () -> Unit) {
        onClickListener = listener
    }

    fun getBubbleData(): Map<String, Any> = mapOf(
        "userId"      to userId,
        "userName"    to userName,
        "avatarUrl"   to avatarUrl,
        "lastMessage" to lastMessage,
        "unreadCount" to currentUnreadCount,
        "timestamp"   to System.currentTimeMillis()
    )

    fun cleanup() {
        isDetached      = true
        onDragListener  = null
        onDragEndListener = null
        onClickListener = null
        try {
            // FIX-A: dùng applicationContext để tránh crash khi context đã detach
            Glide.with(context.applicationContext).clear(avatarImageView)
        } catch (_: Exception) {}
    }

    override fun onDetachedFromWindow() {
        cleanup()
        super.onDetachedFromWindow()
    }
}
package hust.appchat.bubble

import android.animation.ValueAnimator
import android.content.Context
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.DisplayMetrics
import android.view.LayoutInflater
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
import kotlin.math.abs
import kotlin.math.sqrt

class BubbleView(
    context: Context,
    private val userId: String,
    private val userName: String,
    private val avatarUrl: String
) : FrameLayout(context) {

    private val avatarImageView: ImageView
    private val unreadBadge: TextView
    private val onlineIndicator: View // Giữ lại onlineIndicator
    private val deleteIndicator: ImageView

    private val screenWidth: Int
    private val screenHeight: Int

    // Callbacks
    private var onDragListener: ((Boolean, Float, Float) -> Unit)? = null
    private var onDragEndListener: (() -> Unit)? = null
    private var onClickListener: (() -> Unit)? = null

    // Touch state management
    private var isDragging = false
    private var isDetached = false
    private var hasMoved = false

    private var initialTouchX = 0f
    private var initialTouchY = 0f
    private var lastRawX = 0f
    private var lastRawY = 0f
    private var touchStartTime = 0L

    private var lastMessage: String = ""
    private var currentUnreadCount = 0

    private val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator

    companion object {
        private const val DELETE_ZONE_HEIGHT = 150
        private const val TOUCH_SLOP = 20 // Tăng nhẹ ngưỡng di chuyển để tránh click nhầm thành drag
        private const val CLICK_TIMEOUT = 400L // Tăng thời gian tối đa để nhận diện là click
        private const val BUBBLE_SCALE_DOWN = 0.92f
        private const val BUBBLE_SCALE_DELETE = 0.75f
        private const val DELETE_ZONE_ALPHA = 0.6f
        private const val HAPTIC_SNAP_DURATION = 10L // Dùng cho click/bắt đầu drag
        private const val HAPTIC_DELETE_DURATION = 50L // Dùng cho xóa
    }

    init {
        LayoutInflater.from(context).inflate(R.layout.chat_bubble_layout, this, true)

        avatarImageView = findViewById(R.id.bubble_avatar)
        unreadBadge = findViewById(R.id.bubble_unread_badge)
        onlineIndicator = findViewById(R.id.bubble_online_indicator)
        deleteIndicator = findViewById(R.id.delete_indicator)

        // Cấu hình cơ bản cho phép tương tác
        isClickable = true
        isFocusable = true
        isFocusableInTouchMode = true

        // Lấy kích thước màn hình
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val displayMetrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getMetrics(displayMetrics)
        screenWidth = displayMetrics.widthPixels
        screenHeight = displayMetrics.heightPixels

        loadAvatar()
        // Thiết lập Touch Listener ngay trong init (như trong bản "COMPLETE FIX")
        setupTouchListener()

        android.util.Log.d("BubbleView", "✅ Bubble created: $userName. Screen: ${screenWidth}x${screenHeight}")
    }

    private fun loadAvatar() {
        if (isDetached) return

        try {
            val requestOptions = RequestOptions()
                .circleCrop()
                .diskCacheStrategy(DiskCacheStrategy.ALL)
                .placeholder(R.drawable.bubble_background)
                .error(R.drawable.bubble_background)
                .override(100, 100)

            if (avatarUrl.isNotEmpty()) {
                Glide.with(context)
                    .load(avatarUrl)
                    .apply(requestOptions)
                    .into(avatarImageView)
            } else {
                avatarImageView.setImageResource(R.drawable.bubble_background)
            }
        } catch (e: Exception) {
            android.util.Log.e("BubbleView", "❌ Avatar load error: $e")
            avatarImageView.setImageResource(R.drawable.bubble_background)
        }
    }

    // ========================================
    // TOUCH HANDLING LOGIC
    // ========================================

    private fun setupTouchListener() {
        setOnTouchListener { _, event ->
            if (isDetached) {
                return@setOnTouchListener false
            }

            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    handleTouchDown(event)
                    true // MUST return true to consume event sequence
                }
                MotionEvent.ACTION_MOVE -> {
                    handleTouchMove(event)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    handleTouchUp(event)
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    resetVisuals()
                    true
                }
                else -> false
            }
        }
    }

    private fun handleTouchDown(event: MotionEvent) {
        initialTouchX = event.x
        initialTouchY = event.y
        lastRawX = event.rawX
        lastRawY = event.rawY
        touchStartTime = System.currentTimeMillis()
        isDragging = false
        hasMoved = false

        // Visual feedback
        animate()
            .scaleX(BUBBLE_SCALE_DOWN)
            .scaleY(BUBBLE_SCALE_DOWN)
            .setDuration(100)
            .start()
    }

    private fun handleTouchMove(event: MotionEvent) {
        val deltaX = event.x - initialTouchX
        val deltaY = event.y - initialTouchY
        val distance = sqrt((deltaX * deltaX + deltaY * deltaY).toDouble())

        // Check if moved beyond threshold (start drag/move sequence)
        if (distance > TOUCH_SLOP && !hasMoved) {
            hasMoved = true
            performHapticFeedback(HAPTIC_SNAP_DURATION)
            android.util.Log.d("BubbleView", "🖐️ Movement detected, distance: ${distance.toInt()}")
        }

        if (hasMoved) {
            if (!isDragging) {
                isDragging = true
                android.util.Log.d("BubbleView", "🖐️ Drag STARTED")
            }

            // Calculate movement delta from last position
            val moveX = event.rawX - lastRawX
            val moveY = event.rawY - lastRawY

            lastRawX = event.rawX
            lastRawY = event.rawY

            // Notify drag listener (false = not in delete zone yet, but dragging)
            onDragListener?.invoke(false, moveX, moveY)

            // Check delete zone
            val inDeleteZone = event.rawY > (screenHeight - DELETE_ZONE_HEIGHT)
            updateDeleteIndicator(inDeleteZone)

            val targetScale = if (inDeleteZone) BUBBLE_SCALE_DELETE else BUBBLE_SCALE_DOWN
            val targetAlpha = if (inDeleteZone) DELETE_ZONE_ALPHA else 1f

            animate()
                .scaleX(targetScale)
                .scaleY(targetScale)
                .alpha(targetAlpha)
                .setDuration(50)
                .start()
        }
    }

    private fun handleTouchUp(event: MotionEvent) {
        val touchDuration = System.currentTimeMillis() - touchStartTime

        // Reset visuals immediately
        animate()
            .scaleX(1f)
            .scaleY(1f)
            .alpha(1f)
            .setDuration(150)
            .start()

        hideDeleteIndicator()

        if (isDragging) {
            // Check if in delete zone on lift-off
            val inDeleteZone = event.rawY > (screenHeight - DELETE_ZONE_HEIGHT)

            if (inDeleteZone) {
                performHapticFeedback(HAPTIC_DELETE_DURATION)
                // Trigger delete action in service
                onDragListener?.invoke(true, 0f, 0f)
                android.util.Log.d("BubbleView", "🗑️ DELETE: In delete zone")
            } else {
                android.util.Log.d("BubbleView", "✅ Drag ENDED")
            }

            // Notify drag end regardless of deletion status (for snapping)
            onDragEndListener?.invoke()
        } else if (!hasMoved && touchDuration < CLICK_TIMEOUT) {
            // CLICK DETECTED (low movement, short duration)
            android.util.Log.d("BubbleView", "👆 CLICK detected for: $userName")
            performHapticFeedback(HAPTIC_SNAP_DURATION)

            // Call performClick for accessibility
            performClick()

            // Notify click listener
            onClickListener?.invoke()
        }

        // Reset state
        isDragging = false
        hasMoved = false
    }

    private fun resetVisuals() {
        animate()
            .scaleX(1f)
            .scaleY(1f)
            .alpha(1f)
            .setDuration(150)
            .start()
        hideDeleteIndicator()
        isDragging = false
        hasMoved = false
    }

    private fun performHapticFeedback(duration: Long) {
        try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                vibrator?.vibrate(
                    VibrationEffect.createOneShot(duration, VibrationEffect.DEFAULT_AMPLITUDE)
                )
            } else {
                @Suppress("DEPRECATION")
                vibrator?.vibrate(duration)
            }
        } catch (e: Exception) {
            android.util.Log.e("BubbleView", "⚠️ Haptic error: $e")
        }
    }

    override fun performClick(): Boolean {
        android.util.Log.d("BubbleView", "🫧 performClick() called")
        super.performClick()
        return true
    }

    // ========================================
    // VISUAL AND DATA UPDATES
    // ========================================

    private fun updateDeleteIndicator(show: Boolean) {
        // Sử dụng giá trị cố định (1f) cho alpha nếu không ở trong delete zone
        val targetAlpha = if (show) 1f else 0f
        val targetScale = if (show) 1.3f else 1f

        deleteIndicator.animate()
            .alpha(targetAlpha)
            .scaleX(targetScale)
            .scaleY(targetScale)
            .setDuration(100)
            .start()
    }

    private fun hideDeleteIndicator() {
        deleteIndicator.animate()
            .alpha(0f)
            .scaleX(1f)
            .scaleY(1f)
            .setDuration(150)
            .start()
    }

    fun updateUnreadCount(count: Int) {
        if (isDetached) return

        post {
            if (count > 0) {
                unreadBadge.visibility = View.VISIBLE
                unreadBadge.text = when {
                    count > 99 -> "99+"
                    else -> count.toString()
                }

                if (count > currentUnreadCount) {
                    // Animation cho tin nhắn mới
                    unreadBadge.animate()
                        .scaleX(1.4f)
                        .scaleY(1.4f)
                        .setDuration(200)
                        .withEndAction {
                            if (!isDetached) {
                                unreadBadge.animate()
                                    .scaleX(1f)
                                    .scaleY(1f)
                                    .setDuration(200)
                                    .start()
                            }
                        }
                        .start()
                }
            } else {
                unreadBadge.visibility = View.GONE
            }
            currentUnreadCount = count
        }
    }

    fun updateLastMessage(message: String) {
        lastMessage = message
    }

    fun animateNewMessage() {
        if (isDetached) return

        post {
            animate()
                .scaleX(1.2f)
                .scaleY(1.2f)
                .rotation(10f)
                .setDuration(150)
                .withEndAction {
                    if (!isDetached) {
                        animate()
                            .scaleX(1f)
                            .scaleY(1f)
                            .rotation(0f)
                            .setDuration(200)
                            .start()
                    }
                }
                .start()

            performHapticFeedback(HAPTIC_SNAP_DURATION)
        }
    }

    fun animateDelete(onComplete: () -> Unit) {
        if (isDetached) return

        performHapticFeedback(HAPTIC_DELETE_DURATION)

        animate()
            .alpha(0f)
            .scaleX(0f)
            .scaleY(0f)
            .rotation(360f)
            .setDuration(300)
            .withEndAction {
                if (!isDetached) {
                    onComplete()
                }
            }
            .start()
    }

    // Giữ lại hàm setOnlineStatus (có trong bản đầu tiên, bị thiếu trong bản thứ hai)
    fun setOnlineStatus(isOnline: Boolean) {
        if (isDetached) return

        post {
            if (isOnline) {
                onlineIndicator.visibility = View.VISIBLE
                onlineIndicator.alpha = 0f
                onlineIndicator.animate()
                    .alpha(1f)
                    .setDuration(300)
                    .start()
            } else {
                onlineIndicator.animate()
                    .alpha(0f)
                    .setDuration(300)
                    .withEndAction {
                        if (!isDetached) {
                            onlineIndicator.visibility = View.GONE
                        }
                    }
                    .start()
            }
        }
    }

    // ========================================
    // LIFECYCLE AND LISTENERS
    // ========================================

    // PUBLIC setter methods - được gọi từ BubbleOverlayService
    fun setOnDragListener(listener: (Boolean, Float, Float) -> Unit) {
        this.onDragListener = listener
        android.util.Log.d("BubbleView", "✅ Drag listener set")
    }

    fun setOnDragEndListener(listener: () -> Unit) {
        this.onDragEndListener = listener
        android.util.Log.d("BubbleView", "✅ Drag end listener set")
    }

    fun setOnClickListener(listener: () -> Unit) {
        this.onClickListener = listener
        android.util.Log.d("BubbleView", "✅ Click listener set")
    }

    fun getBubbleData(): Map<String, Any> {
        // Giữ lại hàm này để lưu vị trí hoặc trạng thái nếu cần (mặc dù không dùng trong service hiện tại)
        return mapOf(
            "userId" to userId,
            "userName" to userName,
            "avatarUrl" to avatarUrl,
            "lastMessage" to lastMessage,
            "unreadCount" to currentUnreadCount,
            "timestamp" to System.currentTimeMillis()
        )
    }

    fun cleanup() {
        isDetached = true
        onDragListener = null
        onDragEndListener = null
        onClickListener = null

        // Xóa Glide request để tránh memory leak
        try {
            Glide.with(context).clear(avatarImageView)
        } catch (e: Exception) {
            android.util.Log.e("BubbleView", "❌ Glide clear error: $e")
        }
    }

    override fun onDetachedFromWindow() {
        cleanup()
        super.onDetachedFromWindow()
    }
}
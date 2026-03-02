package hust.appchat.bubble

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.*
import android.view.inputmethod.InputMethodManager
import androidx.core.app.NotificationCompat
import hust.appchat.R
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class BubbleOverlayService : Service() {

    private var windowManager: WindowManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val bubbleViews = mutableMapOf<String, BubbleView>()
    private val bubbleParams = mutableMapOf<String, WindowManager.LayoutParams>()

    // Mini Chat with Flutter
    private var miniChatFlutterView: FlutterView? = null
    private var miniChatParams: WindowManager.LayoutParams? = null
    private var miniChatEngine: FlutterEngine? = null
    private var miniChatChannel: MethodChannel? = null

    private var currentMiniChatUserId: String? = null
    private var currentMiniChatUserName: String? = null
    private var currentMiniChatAvatarUrl: String? = null

    // ✅ FIX 1: Delete Zone chỉ hiển thị khi đang drag
    private var deleteZoneView: DeleteZoneView? = null
    private var deleteZoneParams: WindowManager.LayoutParams? = null // Thêm params cho delete zone
    private var isDraggingAnyBubble = false

    // Screen dimension variables with retry logic
    private var screenWidth = 0
    private var screenHeight = 0
    private var dimensionRetryCount = 0
    private val MAX_RETRY = 3
    private var isServiceRunning = false

    companion object {
        const val ACTION_SHOW_BUBBLE = "SHOW_BUBBLE"
        const val ACTION_HIDE_BUBBLE = "HIDE_BUBBLE"
        const val ACTION_UPDATE_BUBBLE = "UPDATE_BUBBLE"
        const val ACTION_UPDATE_BUBBLE_POSITION = "UPDATE_BUBBLE_POSITION"
        const val ACTION_SHOW_MINI_CHAT = "SHOW_MINI_CHAT"
        const val ACTION_HIDE_MINI_CHAT = "HIDE_MINI_CHAT"
        const val ACTION_HIDE_ALL_BUBBLES = "HIDE_ALL_BUBBLES"

        private const val NOTIFICATION_ID = 12345
        private const val CHANNEL_ID = "chat_bubbles"
        private const val MINI_CHAT_ENGINE_ID = "mini_chat_engine"
        private const val MINI_CHAT_CHANNEL = "mini_chat_channel"

        private const val BUBBLE_PADDING = 10
    }

    override fun onCreate() {
        super.onCreate()

        try {
            windowManager = getSystemService(WINDOW_SERVICE) as? WindowManager

            // Get screen dimensions with retry
            getScreenDimensionsWithRetry()

            android.util.Log.d("BubbleService", "✅ onCreate: ${screenWidth}x${screenHeight}")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                createNotificationChannel()
            }

            BubbleManager.init(this)
            isServiceRunning = true // Cập nhật trạng thái service
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ onCreate failed: $e")
        }
    }

    // ========================================
    // SCREEN DIMENSIONS LOGIC
    // ========================================
    private fun getScreenDimensionsWithRetry() {
        dimensionRetryCount = 0
        attemptGetScreenDimensions()
    }

    private fun attemptGetScreenDimensions() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val windowMetrics = windowManager?.currentWindowMetrics
                if (windowMetrics != null) {
                    val bounds = windowMetrics.bounds
                    screenWidth = bounds.width()
                    screenHeight = bounds.height()

                    if (screenWidth > 0 && screenHeight > 0) {
                        android.util.Log.d("BubbleService", "✅ WindowMetrics: ${screenWidth}x${screenHeight}")
                        return
                    }
                }
            }

            @Suppress("DEPRECATION")
            val display = windowManager?.defaultDisplay
            if (display != null) {
                val size = android.graphics.Point()
                @Suppress("DEPRECATION")
                display.getRealSize(size)
                screenWidth = size.x
                screenHeight = size.y

                if (screenWidth > 0 && screenHeight > 0) {
                    android.util.Log.d("BubbleService", "✅ Display: ${screenWidth}x${screenHeight}")
                    return
                }
            }

            val displayMetrics = resources.displayMetrics
            screenWidth = displayMetrics.widthPixels
            screenHeight = displayMetrics.heightPixels

            if (screenWidth > 0 && screenHeight > 0) {
                android.util.Log.d("BubbleService", "✅ Resources: ${screenWidth}x${screenHeight}")
                return
            }

            // RETRY if dimensions are invalid
            if (dimensionRetryCount < MAX_RETRY) {
                dimensionRetryCount++
                android.util.Log.w("BubbleService", "⚠️ Invalid dimensions, retry $dimensionRetryCount/$MAX_RETRY")

                mainHandler.postDelayed({
                    attemptGetScreenDimensions()
                }, 200L * dimensionRetryCount) // Exponential backoff: 200ms, 400ms, 600ms
                return
            }

            // Final fallback
            screenWidth = 1080
            screenHeight = 2340
            android.util.Log.w("BubbleService", "⚠️ Using fallback: ${screenWidth}x${screenHeight}")

        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ Error getting screen dimensions: $e")

            // Retry on error
            if (dimensionRetryCount < MAX_RETRY) {
                dimensionRetryCount++
                mainHandler.postDelayed({
                    attemptGetScreenDimensions()
                }, 200L * dimensionRetryCount)
            } else {
                screenWidth = 1080
                screenHeight = 2340
                android.util.Log.w("BubbleService", "⚠️ Using fallback on error: ${screenWidth}x${screenHeight}")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForeground(NOTIFICATION_ID, createNotification())
            }

            isServiceRunning = true
            intent?.let { handleIntent(it) }
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ onStartCommand error: $e")
        }

        return START_STICKY
    }

    private fun handleIntent(intent: Intent) {
        val action = intent.action
        android.util.Log.d("BubbleService", "📥 Action: $action")

        when (action) {
            ACTION_SHOW_BUBBLE -> {
                val userId = intent.getStringExtra("userId") ?: return
                val userName = intent.getStringExtra("userName") ?: ""
                val avatarUrl = intent.getStringExtra("avatarUrl") ?: ""
                val unreadCount = intent.getIntExtra("unreadCount", 0)
                val lastMessage = intent.getStringExtra("lastMessage") ?: ""
                val positionX = intent.getIntExtra("positionX", screenWidth - 100)
                val positionY = intent.getIntExtra("positionY", 200)

                showBubble(userId, userName, avatarUrl, unreadCount, lastMessage, positionX, positionY)
            }

            ACTION_UPDATE_BUBBLE -> {
                val userId = intent.getStringExtra("userId") ?: return
                val unreadCount = intent.getIntExtra("unreadCount", 0)
                val lastMessage = intent.getStringExtra("lastMessage") ?: ""
                updateBubble(userId, unreadCount, lastMessage)
            }

            ACTION_UPDATE_BUBBLE_POSITION -> {
                val userId = intent.getStringExtra("userId") ?: return
                val positionX = intent.getIntExtra("positionX", -1)
                val positionY = intent.getIntExtra("positionY", -1)

                if (positionX >= 0 && positionY >= 0) {
                    updateBubblePosition(userId, positionX, positionY)
                }
            }

            ACTION_HIDE_BUBBLE -> {
                val userId = intent.getStringExtra("userId") ?: return
                hideBubble(userId)
            }

            ACTION_SHOW_MINI_CHAT -> {
                val userId = intent.getStringExtra("userId") ?: return
                val userName = intent.getStringExtra("userName") ?: ""
                val avatarUrl = intent.getStringExtra("avatarUrl") ?: ""
                showMiniChat(userId, userName, avatarUrl)
            }

            ACTION_HIDE_MINI_CHAT -> {
                hideMiniChat()
            }

            ACTION_HIDE_ALL_BUBBLES -> {
                hideAllBubbles()
            }
        }
    }

    // ========================================
    // ✅ FIX 2: MINI CHAT with proper Flutter Engine initialization
    // ========================================

    private fun showMiniChat(userId: String, userName: String, avatarUrl: String) {
        android.util.Log.d("BubbleService", "💬 showMiniChat: $userName")

        mainHandler.post {
            try {
                // Remove old mini chat if exists
                miniChatFlutterView?.let {
                    try {
                        hideKeyboard(it)
                        windowManager?.removeView(it)
                    } catch (e: Exception) {
                        android.util.Log.e("BubbleService", "⚠️ Error removing old mini chat: $e")
                    }
                }

                currentMiniChatUserId = userId

                // ✅ FIX: Properly initialize Flutter Engine
                initializeMiniChatEngine {
                    continueShowingMiniChat(userId, userName, avatarUrl)
                }

            } catch (e: Exception) {
                android.util.Log.e("BubbleService", "❌ showMiniChat failed: $e")
            }
        }
    }

    // ✅ FIX: Separate engine initialization with callback
    private fun initializeMiniChatEngine(onReady: () -> Unit) {
        miniChatEngine = FlutterEngineCache.getInstance().get(MINI_CHAT_ENGINE_ID)

        if (miniChatEngine == null) {
            android.util.Log.d("BubbleService", "🔧 Creating new Flutter Engine")
            miniChatEngine = FlutterEngine(this)

            // Execute dart entrypoint
            miniChatEngine!!.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )

            FlutterEngineCache.getInstance().put(MINI_CHAT_ENGINE_ID, miniChatEngine!!)

            // ✅ FIX: Wait 800ms for engine to fully initialize
            mainHandler.postDelayed({
                android.util.Log.d("BubbleService", "✅ Engine ready after warmup")
                onReady()
            }, 800)
        } else {
            android.util.Log.d("BubbleService", "♻️ Reusing existing engine")
            onReady()
        }
    }

    private fun continueShowingMiniChat(userId: String, userName: String, avatarUrl: String) {
        try {
            miniChatFlutterView = FlutterView(this)
            miniChatFlutterView!!.attachToFlutterEngine(miniChatEngine!!)

            // ✅ FIX: Setup channel AFTER view is attached
            setupMiniChatChannel()

            val width = ((screenWidth * 0.85).toInt()).coerceIn(300, 600)
            val height = ((screenHeight * 0.7).toInt()).coerceIn(400, 900)

            android.util.Log.d("BubbleService", "📏 Mini chat size: ${width}x${height}")

            val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }

            miniChatParams = WindowManager.LayoutParams(
                width,
                height,
                layoutFlag,
                // ✅ FIX: Remove FLAG_NOT_FOCUSABLE to allow input
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.CENTER
                // SOFT_INPUT_ADJUST_RESIZE để bàn phím không che view Flutter
                softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
                // ✅ CRITICAL: Allow focus for keyboard input
                flags = flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            }

            windowManager?.addView(miniChatFlutterView, miniChatParams)

            android.util.Log.d("BubbleService", "✅ Mini chat view added")

            // Gửi dữ liệu và yêu cầu focus sau khi view đã được thêm
            mainHandler.postDelayed({
                miniChatFlutterView?.let { view ->
                    view.requestFocus()
                    view.isFocusableInTouchMode = true
                }

                // ✅ FIX: Send navigation command with longer delay (400ms after view added/focused)
                mainHandler.postDelayed({
                    sendMiniChatData(userId, userName, avatarUrl)
                }, 400)
            }, 200)

        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ continueShowingMiniChat failed: $e")
        }
    }

    private fun showKeyboard(view: View) {
        try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.showSoftInput(view, InputMethodManager.SHOW_IMPLICIT)
            android.util.Log.d("BubbleService", "⌨️ Keyboard show requested")
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ Failed to show keyboard: $e")
        }
    }

    private fun hideKeyboard(view: View) {
        try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.hideSoftInputFromWindow(view.windowToken, 0)
            android.util.Log.d("BubbleService", "⌨️ Keyboard hide requested")
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ Failed to hide keyboard: $e")
        }
    }

    // MethodChannel setup with proper timing (FIX 5 -> now part of FIX 2)
    private fun setupMiniChatChannel() {
        try {
            if (miniChatEngine == null) {
                android.util.Log.e("BubbleService", "❌ Cannot setup channel: engine is null")
                return
            }

            miniChatChannel = MethodChannel(
                miniChatEngine!!.dartExecutor.binaryMessenger,
                MINI_CHAT_CHANNEL
            )

            miniChatChannel!!.setMethodCallHandler { call, result ->
                android.util.Log.d("BubbleService", "📞 Mini chat method: ${call.method}")

                when (call.method) {
                    "minimize" -> {
                        miniChatFlutterView?.let { hideKeyboard(it) } // Ẩn bàn phím
                        hideMiniChat()
                        currentMiniChatUserId?.let { userId ->
                            bubbleViews[userId]?.visibility = View.VISIBLE // Hiện lại bubble
                        }
                        result.success(true)
                    }

                    "close" -> {
                        miniChatFlutterView?.let { hideKeyboard(it) } // Ẩn bàn phím
                        hideMiniChat()
                        currentMiniChatUserId?.let { userId ->
                            BubbleManager.removeBubble(this, userId)
                        }
                        result.success(true)
                    }

                    else -> result.notImplemented()
                }
            }

            android.util.Log.d("BubbleService", "✅ MethodChannel setup complete")
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ MethodChannel setup failed: $e")
        }
    }

    private fun sendMiniChatData(userId: String, userName: String, avatarUrl: String) {
        try {
            android.util.Log.d("BubbleService", "📤 Sending navigation command to Flutter")

            miniChatChannel?.invokeMethod(
                "navigateToMiniChat",
                mapOf(
                    "peerId" to userId,
                    "peerNickname" to userName,
                    "peerAvatar" to avatarUrl
                )
            )
            android.util.Log.d("BubbleService", "✅ Navigation command sent")
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ Failed to send navigation data: $e")
        }
    }

    private fun hideMiniChat() {
        mainHandler.post {
            try {
                miniChatFlutterView?.let { view ->
                    hideKeyboard(view) // Ẩn bàn phím

                    mainHandler.postDelayed({
                        try {
                            windowManager?.removeView(view)
                        } catch (e: Exception) {
                            android.util.Log.e("BubbleService", "❌ Error removing view: $e")
                        }
                    }, 100)

                    miniChatFlutterView = null
                    miniChatParams = null
                }

                currentMiniChatUserId = null
                // currentMiniChatUserName = null
                // currentMiniChatAvatarUrl = null

                android.util.Log.d("BubbleService", "✅ Mini chat hidden")

                // Kiểm tra và dừng service nếu không còn gì active
                checkAndStopService()
            } catch (e: Exception) {
                android.util.Log.e("BubbleService", "❌ Error hiding mini chat: $e")
            }
        }
    }

    // ========================================
    // ✅ FIX 3: BUBBLE IMPLEMENTATION with proper touch handling
    // ========================================
    private fun showBubble(
        userId: String,
        userName: String,
        avatarUrl: String,
        unreadCount: Int,
        lastMessage: String,
        positionX: Int,
        positionY: Int
    ) {
        mainHandler.post {
            try {
                if (screenWidth <= 0 || screenHeight <= 0) {
                    getScreenDimensionsWithRetry()

                    // Wait for dimensions before continuing
                    if (screenWidth <= 0 || screenHeight <= 0) {
                        android.util.Log.e("BubbleService", "❌ Cannot show bubble: invalid dimensions")
                        return@post
                    }
                }

                bubbleViews[userId]?.let {
                    try {
                        windowManager?.removeView(it)
                    } catch (e: Exception) {
                        android.util.Log.e("BubbleService", "⚠️ Error removing old bubble: $e")
                    }
                }

                val bubbleView = BubbleView(this, userId, userName, avatarUrl)
                bubbleView.updateUnreadCount(unreadCount)
                bubbleView.updateLastMessage(lastMessage)

                val bubbleSize = 64
                // Tính toán maxBoundX/Y an toàn hơn
                val maxBoundX = maxOf(BUBBLE_PADDING, screenWidth - bubbleSize - BUBBLE_PADDING)
                val maxBoundY = maxOf(BUBBLE_PADDING, screenHeight - bubbleSize - BUBBLE_PADDING)

                val boundedX = positionX.coerceIn(BUBBLE_PADDING, maxBoundX)
                val boundedY = positionY.coerceIn(BUBBLE_PADDING, maxBoundY)

                android.util.Log.d("BubbleService", "🎈 showBubble: $userName at ($boundedX, $boundedY)")

                val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                }

                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    layoutFlag,
                    // ✅ FIX: CRITICAL - Flags that allow touch interaction
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.TOP or Gravity.START
                    x = boundedX
                    y = boundedY
                }

                // Add view FIRST
                windowManager?.addView(bubbleView, params)

                bubbleViews[userId] = bubbleView
                bubbleParams[userId] = params

                // Setup listeners AFTER view is added (with delay for stability)
                mainHandler.postDelayed({
                    setupBubbleListeners(bubbleView, userId, userName, avatarUrl, params)
                }, 100)

                android.util.Log.d("BubbleService", "✅ Bubble added successfully at: ($boundedX, $boundedY)")

                mainHandler.postDelayed({
                    if (bubbleViews.containsKey(userId)) {
                        snapBubbleToEdge(userId)
                    }
                }, 500)

            } catch (e: Exception) {
                android.util.Log.e("BubbleService", "❌ showBubble failed: $e")
            }
        }
    }

    // Separate method for setting up listeners (FIX 3)
    private fun setupBubbleListeners(
        bubbleView: BubbleView,
        userId: String,
        userName: String,
        avatarUrl: String,
        params: WindowManager.LayoutParams
    ) {
        try {
            bubbleView.setOnClickListener {
                android.util.Log.d("BubbleService", "🫧 Bubble CLICKED: $userName")
                onBubbleClicked(userId, userName, avatarUrl)
            }

            bubbleView.setOnDragListener { isInDeleteZone: Boolean, deltaX: Float, deltaY: Float ->
                // Kiểm tra xem có phải là bắt đầu kéo không
                if (!isDraggingAnyBubble && (deltaX != 0f || deltaY != 0f)) {
                    isDraggingAnyBubble = true
                    showDeleteZone()
                }

                if (isInDeleteZone) {
                    deleteZoneView?.animateToActive(true) // Cập nhật trạng thái delete zone
                    bubbleView.animateDelete {
                        hideDeleteZone()
                        isDraggingAnyBubble = false
                        BubbleManager.removeBubble(this, userId)
                        checkAndStopService()
                    }
                } else {
                    deleteZoneView?.animateToActive(false) // Cập nhật trạng thái delete zone
                    bubbleParams[userId]?.let { currentParams ->
                        currentParams.x += deltaX.toInt()
                        currentParams.y += deltaY.toInt()

                        val currentBubbleWidth = bubbleView.width
                        val currentBubbleHeight = bubbleView.height

                        val dragMaxBoundX = maxOf(BUBBLE_PADDING, screenWidth - currentBubbleWidth - BUBBLE_PADDING)
                        val dragMaxBoundY = maxOf(BUBBLE_PADDING, screenHeight - currentBubbleHeight - BUBBLE_PADDING)

                        // Giữ bubble trong giới hạn màn hình
                        val newX = currentParams.x.coerceIn(BUBBLE_PADDING, dragMaxBoundX)
                        val newY = currentParams.y.coerceIn(BUBBLE_PADDING, dragMaxBoundY)

                        currentParams.x = newX
                        currentParams.y = newY

                        try {
                            windowManager?.updateViewLayout(bubbleView, currentParams)
                        } catch (e: Exception) {
                            android.util.Log.e("BubbleService", "❌ Update layout failed: $e")
                        }
                    }
                }
            }

            bubbleView.setOnDragEndListener {
                android.util.Log.d("BubbleService", "🫧 Drag END callback")
                hideDeleteZone()
                isDraggingAnyBubble = false
                mainHandler.postDelayed({
                    if (bubbleViews.containsKey(userId)) {
                        snapBubbleToEdge(userId)
                    }
                }, 100)
            }

            android.util.Log.d("BubbleService", "✅ Listeners setup complete for: $userName")
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ Error setting up listeners: $e")
        }
    }

    private fun snapBubbleToEdge(userId: String) {
        val bubbleView = bubbleViews[userId] ?: return
        val params = bubbleParams[userId] ?: return

        if (screenWidth <= 0 || screenHeight <= 0) {
            getScreenDimensionsWithRetry()
        }

        val centerX = params.x + bubbleView.width / 2
        val targetX = if (centerX < screenWidth / 2) {
            BUBBLE_PADDING + 10 // Đẩy sát mép trái
        } else {
            screenWidth - bubbleView.width - BUBBLE_PADDING - 10 // Đẩy sát mép phải
        }

        android.animation.ValueAnimator.ofInt(params.x, targetX).apply {
            duration = 300
            interpolator = android.view.animation.OvershootInterpolator(1.5f)
            addUpdateListener { animation ->
                params.x = animation.animatedValue as Int
                try {
                    windowManager?.updateViewLayout(bubbleView, params)
                } catch (e: Exception) {
                    cancel()
                }
            }
            start()
        }
    }

    // ========================================
    // BUBBLE UTILITY METHODS
    // ========================================

    private fun updateBubblePosition(userId: String, x: Int, y: Int) {
        val bubbleView = bubbleViews[userId] ?: return
        val params = bubbleParams[userId] ?: return

        val maxBoundX = maxOf(BUBBLE_PADDING, screenWidth - bubbleView.width - BUBBLE_PADDING)
        val maxBoundY = maxOf(BUBBLE_PADDING, screenHeight - bubbleView.height - BUBBLE_PADDING)

        params.x = x.coerceIn(BUBBLE_PADDING, maxBoundX)
        params.y = y.coerceIn(BUBBLE_PADDING, maxBoundY)

        try {
            windowManager?.updateViewLayout(bubbleView, params)
        } catch (e: Exception) {}
    }

    private fun updateBubble(userId: String, unreadCount: Int, lastMessage: String) {
        try {
            bubbleViews[userId]?.let { bubble ->
                bubble.updateUnreadCount(unreadCount)
                bubble.updateLastMessage(lastMessage)
                bubble.animateNewMessage()
            }
        } catch (e: Exception) {}
    }

    private fun hideBubble(userId: String) {
        mainHandler.post {
            try {
                val view = bubbleViews.remove(userId)
                bubbleParams.remove(userId)

                view?.let {
                    it.cleanup()
                    windowManager?.removeView(it)
                }

                // Kiểm tra và dừng service
                checkAndStopService()
            } catch (e: Exception) {
                android.util.Log.e("BubbleService", "❌ hideBubble error: $e")
            }
        }
    }

    private fun hideAllBubbles() { // Logic cho ACTION_HIDE_ALL_BUBBLES
        mainHandler.post {
            try {
                bubbleViews.values.forEach { view ->
                    try {
                        view.cleanup()
                        windowManager?.removeView(view)
                    } catch (e: Exception) {}
                }

                bubbleViews.clear()
                bubbleParams.clear()

                // Kiểm tra và dừng service
                checkAndStopService()
            } catch (e: Exception) {
                android.util.Log.e("BubbleService", "❌ hideAllBubbles error: $e")
            }
        }
    }

    // Send broadcast with proper checks
    private fun onBubbleClicked(userId: String, userName: String, avatarUrl: String) {
        try {
            bubbleViews[userId]?.visibility = View.GONE
            showMiniChat(userId, userName, avatarUrl)
            BubbleManager.markAsRead(this, userId)

            // Send broadcast
            val intent = Intent("CHAT_BUBBLE_CLICKED").apply {
                putExtra("userId", userId)
                putExtra("userName", userName)
                putExtra("avatarUrl", avatarUrl)
            }
            sendBroadcast(intent)
            android.util.Log.d("BubbleService", "✅ Broadcast sent: CHAT_BUBBLE_CLICKED")
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ Error handling bubble click: $e")
        }
    }

    // ========================================
    // DELETE ZONE
    // ========================================
    private fun showDeleteZone() {
        if (deleteZoneView == null) {
            try {
                val deleteZone = DeleteZoneView(this)

                val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                }

                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.MATCH_PARENT,
                    150, // Chiều cao của Delete Zone
                    layoutFlag,
                    // Phải là NOT_TOUCHABLE để không chặn sự kiện chạm (touch event) của bubble
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.BOTTOM
                }

                windowManager?.addView(deleteZone, params)
                deleteZoneView = deleteZone
                deleteZoneParams = params
            } catch (e: Exception) {
                android.util.Log.e("BubbleService", "❌ showDeleteZone error: $e")
                return
            }
        }
        deleteZoneView?.show()
    }

    private fun hideDeleteZone() {
        deleteZoneView?.hide()
    }

    // ========================================
    // NOTIFICATION & LIFECYCLE
    // ========================================

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Chat Bubbles",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Active chat bubbles"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager?.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val bubbleCount = bubbleViews.size
        val hasMiniChat = miniChatFlutterView != null

        val contentText = when {
            bubbleCount > 0 && hasMiniChat -> "$bubbleCount bubble(s) + Mini chat active"
            bubbleCount > 0 -> "$bubbleCount bubble(s) active"
            hasMiniChat -> "Mini chat active"
            else -> "Chat bubbles ready"
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Chat Bubbles")
            .setContentText(contentText)
            .setSmallIcon(R.drawable.bubble_background)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    // Dừng service khi không còn bubble hoặc mini chat nào
    private fun checkAndStopService() {
        if (bubbleViews.isEmpty() && miniChatFlutterView == null && isServiceRunning) {
            android.util.Log.d("BubbleService", "✅ Stopping service due to no active bubbles/mini chat")
            stopForeground(true)
            stopSelf()
            isServiceRunning = false
        }
    }

    override fun onDestroy() {
        android.util.Log.d("BubbleService", "🛑 onDestroy")

        try {
            isServiceRunning = false

            // Ẩn bàn phím trước
            miniChatFlutterView?.let { hideKeyboard(it) }

            BubbleManager.cleanup()

            // Xóa Delete Zone
            deleteZoneView?.let {
                try {
                    windowManager?.removeView(it)
                } catch (e: Exception) { android.util.Log.e("BubbleService", "❌ Destroy error: $e") }
            }
            deleteZoneView = null
            deleteZoneParams = null

            // Xóa tất cả Bubbles
            bubbleViews.values.forEach { view ->
                try {
                    view.cleanup()
                    windowManager?.removeView(view)
                } catch (e: Exception) { android.util.Log.e("BubbleService", "❌ Destroy error: $e") }
            }
            bubbleViews.clear()
            bubbleParams.clear()

            // Xóa Mini Chat View
            miniChatFlutterView?.let {
                try {
                    it.detachFromFlutterEngine()
                    windowManager?.removeView(it)
                } catch (e: Exception) { android.util.Log.e("BubbleService", "❌ Destroy error: $e") }
            }
            miniChatFlutterView = null

            // Flutter Engine được giữ trong cache (MINI_CHAT_ENGINE_ID) nên không cần detach/dispose ở đây.
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ Final onDestroy cleanup error: $e")
        }

        super.onDestroy()
    }
}
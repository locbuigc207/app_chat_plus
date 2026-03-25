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
import hust.appchat.BubbleActivity
import hust.appchat.R
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * FIX #2 — Engine ID conflict:
 *   Trước: MINI_CHAT_ENGINE_ID = "mini_chat_engine" — engine riêng biệt
 *          → BubbleActivity + BubbleOverlayService có thể chạy 2 engine đồng thời
 *          → OOM trên thiết bị ít RAM (~150MB mỗi engine).
 *   Sau:  Dùng BubbleActivity.SHARED_ENGINE_ID = "shared_flutter_engine"
 *          → Toàn app chỉ có 1 Flutter engine duy nhất.
 *          → Nếu engine đã được BubbleActivity warm up, service reuse ngay.
 *          → Nếu chưa có, service tạo mới và cache cho các caller sau.
 *
 * NOTE: Khi dùng shared engine, MethodChannel name phải khác nhau giữa
 *       BubbleActivity (bubble_chat_channel) và BubbleOverlayService (mini_chat_channel)
 *       vì cùng engine nhưng khác destination handler.
 */
class BubbleOverlayService : Service() {

    private var windowManager: WindowManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val bubbleViews = mutableMapOf<String, BubbleView>()
    private val bubbleParams = mutableMapOf<String, WindowManager.LayoutParams>()

    // Mini Chat with Flutter — FIX #2: reuse shared engine
    private var miniChatFlutterView: FlutterView? = null
    private var miniChatParams: WindowManager.LayoutParams? = null
    private var miniChatEngine: FlutterEngine? = null  // reference only, không own
    private var miniChatChannel: MethodChannel? = null

    private var currentMiniChatUserId: String? = null

    private var deleteZoneView: DeleteZoneView? = null
    private var deleteZoneParams: WindowManager.LayoutParams? = null
    private var isDraggingAnyBubble = false

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

        // FIX #2: Dùng cùng channel name cho mini chat overlay
        private const val MINI_CHAT_CHANNEL = "mini_chat_channel"

        private const val BUBBLE_PADDING = 10
    }

    override fun onCreate() {
        super.onCreate()
        try {
            windowManager = getSystemService(WINDOW_SERVICE) as? WindowManager
            getScreenDimensionsWithRetry()
            android.util.Log.d("BubbleService", "✅ onCreate: ${screenWidth}x${screenHeight}")

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                createNotificationChannel()
            }

            BubbleManager.init(this)
            isServiceRunning = true
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ onCreate failed: $e")
        }
    }

    // ========================================
    // SCREEN DIMENSIONS
    // ========================================

    private fun getScreenDimensionsWithRetry() {
        dimensionRetryCount = 0
        attemptGetScreenDimensions()
    }

    private fun attemptGetScreenDimensions() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val bounds = windowManager?.currentWindowMetrics?.bounds
                if (bounds != null && bounds.width() > 0 && bounds.height() > 0) {
                    screenWidth = bounds.width()
                    screenHeight = bounds.height()
                    return
                }
            }
            val displayMetrics = resources.displayMetrics
            if (displayMetrics.widthPixels > 0) {
                screenWidth = displayMetrics.widthPixels
                screenHeight = displayMetrics.heightPixels
                return
            }
            if (dimensionRetryCount < MAX_RETRY) {
                dimensionRetryCount++
                mainHandler.postDelayed({ attemptGetScreenDimensions() }, 200L * dimensionRetryCount)
                return
            }
            screenWidth = 1080
            screenHeight = 2340
        } catch (e: Exception) {
            screenWidth = 1080
            screenHeight = 2340
            android.util.Log.e("BubbleService", "❌ Screen dimension error: $e")
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
        when (intent.action) {
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
                updateBubble(userId, intent.getIntExtra("unreadCount", 0), intent.getStringExtra("lastMessage") ?: "")
            }
            ACTION_UPDATE_BUBBLE_POSITION -> {
                val userId = intent.getStringExtra("userId") ?: return
                val x = intent.getIntExtra("positionX", -1)
                val y = intent.getIntExtra("positionY", -1)
                if (x >= 0 && y >= 0) updateBubblePosition(userId, x, y)
            }
            ACTION_HIDE_BUBBLE -> hideBubble(intent.getStringExtra("userId") ?: return)
            ACTION_SHOW_MINI_CHAT -> {
                val userId = intent.getStringExtra("userId") ?: return
                showMiniChat(userId, intent.getStringExtra("userName") ?: "", intent.getStringExtra("avatarUrl") ?: "")
            }
            ACTION_HIDE_MINI_CHAT -> hideMiniChat()
            ACTION_HIDE_ALL_BUBBLES -> hideAllBubbles()
        }
    }

    // ========================================
    // FIX #2: MINI CHAT — shared engine initialization
    // ========================================

    private fun showMiniChat(userId: String, userName: String, avatarUrl: String) {
        android.util.Log.d("BubbleService", "💬 showMiniChat: $userName")
        mainHandler.post {
            try {
                miniChatFlutterView?.let {
                    try { hideKeyboard(it); windowManager?.removeView(it) } catch (e: Exception) { }
                }
                currentMiniChatUserId = userId
                initializeMiniChatEngineShared { continueShowingMiniChat(userId, userName, avatarUrl) }
            } catch (e: Exception) {
                android.util.Log.e("BubbleService", "❌ showMiniChat failed: $e")
            }
        }
    }

    /**
     * FIX #2: Dùng shared engine thay vì tạo engine mới
     * Ưu tiên: lấy từ cache (đã được BubbleActivity warm up)
     * Fallback: tạo mới nếu cache trống (edge case: service start trước BubbleActivity)
     */
    private fun initializeMiniChatEngineShared(onReady: () -> Unit) {
        // FIX #2: Thử lấy shared engine trước
        val cachedEngine = FlutterEngineCache.getInstance().get(BubbleActivity.SHARED_ENGINE_ID)

        if (cachedEngine != null) {
            android.util.Log.d("BubbleService", "♻️ Reusing shared engine for mini chat")
            miniChatEngine = cachedEngine
            // Engine đã ready, không cần warmup delay
            onReady()
        } else {
            // Fallback: tạo engine mới và cache với SHARED_ENGINE_ID
            android.util.Log.d("BubbleService", "🔧 Creating shared engine from service (BubbleActivity not started yet)")
            val engine = FlutterEngine(this)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            FlutterEngineCache.getInstance().put(BubbleActivity.SHARED_ENGINE_ID, engine)
            miniChatEngine = engine

            // Chờ engine warmup
            mainHandler.postDelayed({
                android.util.Log.d("BubbleService", "✅ Shared engine ready (created by service)")
                onReady()
            }, 800)
        }
    }

    private fun continueShowingMiniChat(userId: String, userName: String, avatarUrl: String) {
        val engine = miniChatEngine ?: run {
            android.util.Log.e("BubbleService", "❌ Engine is null in continueShowingMiniChat")
            return
        }

        try {
            miniChatFlutterView = FlutterView(this)
            miniChatFlutterView!!.attachToFlutterEngine(engine)

            setupMiniChatChannel()

            val width = ((screenWidth * 0.85).toInt()).coerceIn(300, 600)
            val height = ((screenHeight * 0.7).toInt()).coerceIn(400, 900)

            val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

            miniChatParams = WindowManager.LayoutParams(
                width, height, layoutFlag,
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity = Gravity.CENTER
                softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
                flags = flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            }

            windowManager?.addView(miniChatFlutterView, miniChatParams)
            android.util.Log.d("BubbleService", "✅ Mini chat view added")

            mainHandler.postDelayed({
                miniChatFlutterView?.let { view ->
                    view.requestFocus()
                    view.isFocusableInTouchMode = true
                }
                mainHandler.postDelayed({ sendMiniChatData(userId, userName, avatarUrl) }, 300)
            }, 150)

        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ continueShowingMiniChat failed: $e")
        }
    }

    private fun setupMiniChatChannel() {
        val engine = miniChatEngine ?: return
        try {
            // FIX #2: Channel name "mini_chat_channel" trên shared engine
            // BubbleActivity dùng "bubble_chat_channel" trên cùng engine → không conflict
            miniChatChannel = MethodChannel(engine.dartExecutor.binaryMessenger, MINI_CHAT_CHANNEL)
            miniChatChannel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "minimize" -> {
                        miniChatFlutterView?.let { hideKeyboard(it) }
                        hideMiniChat()
                        currentMiniChatUserId?.let { bubbleViews[it]?.visibility = android.view.View.VISIBLE }
                        result.success(true)
                    }
                    "close" -> {
                        miniChatFlutterView?.let { hideKeyboard(it) }
                        hideMiniChat()
                        currentMiniChatUserId?.let { BubbleManager.removeBubble(this, it) }
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
            android.util.Log.d("BubbleService", "✅ MiniChat MethodChannel ready on shared engine")
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ MethodChannel setup failed: $e")
        }
    }

    private fun sendMiniChatData(userId: String, userName: String, avatarUrl: String) {
        try {
            miniChatChannel?.invokeMethod(
                "navigateToMiniChat",
                mapOf("peerId" to userId, "peerNickname" to userName, "peerAvatar" to avatarUrl)
            )
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ sendMiniChatData failed: $e")
        }
    }

    private fun hideMiniChat() {
        mainHandler.post {
            try {
                miniChatFlutterView?.let { view ->
                    hideKeyboard(view)
                    mainHandler.postDelayed({
                        try { windowManager?.removeView(view) } catch (e: Exception) { }
                    }, 100)
                }
                // FIX #2: Chỉ null reference, KHÔNG destroy engine
                // Engine vẫn sống trong FlutterEngineCache để reuse
                miniChatFlutterView = null
                miniChatParams = null
                miniChatChannel?.setMethodCallHandler(null)
                miniChatChannel = null
                // miniChatEngine = null — giữ reference null ở đây là ok vì
                // lần sau sẽ get lại từ cache
                miniChatEngine = null
                currentMiniChatUserId = null
                checkAndStopService()
            } catch (e: Exception) {
                android.util.Log.e("BubbleService", "❌ hideMiniChat error: $e")
            }
        }
    }

    private fun showKeyboard(view: android.view.View) {
        try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.showSoftInput(view, InputMethodManager.SHOW_IMPLICIT)
        } catch (e: Exception) { }
    }

    private fun hideKeyboard(view: android.view.View) {
        try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.hideSoftInputFromWindow(view.windowToken, 0)
        } catch (e: Exception) { }
    }

    // ========================================
    // BUBBLE OPERATIONS
    // ========================================

    private fun showBubble(
        userId: String, userName: String, avatarUrl: String,
        unreadCount: Int, lastMessage: String, positionX: Int, positionY: Int
    ) {
        mainHandler.post {
            try {
                if (screenWidth <= 0 || screenHeight <= 0) { getScreenDimensionsWithRetry(); return@post }

                bubbleViews[userId]?.let {
                    try { windowManager?.removeView(it) } catch (e: Exception) { }
                }

                val bubbleView = BubbleView(this, userId, userName, avatarUrl)
                bubbleView.updateUnreadCount(unreadCount)
                bubbleView.updateLastMessage(lastMessage)

                val bubbleSize = 64
                val maxBoundX = maxOf(BUBBLE_PADDING, screenWidth - bubbleSize - BUBBLE_PADDING)
                val maxBoundY = maxOf(BUBBLE_PADDING, screenHeight - bubbleSize - BUBBLE_PADDING)

                val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    layoutFlag,
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.TOP or Gravity.START
                    x = positionX.coerceIn(BUBBLE_PADDING, maxBoundX)
                    y = positionY.coerceIn(BUBBLE_PADDING, maxBoundY)
                }

                windowManager?.addView(bubbleView, params)
                bubbleViews[userId] = bubbleView
                bubbleParams[userId] = params

                mainHandler.postDelayed({ setupBubbleListeners(bubbleView, userId, userName, avatarUrl, params) }, 100)
                mainHandler.postDelayed({ if (bubbleViews.containsKey(userId)) snapBubbleToEdge(userId) }, 500)

            } catch (e: Exception) {
                android.util.Log.e("BubbleService", "❌ showBubble failed: $e")
            }
        }
    }

    private fun setupBubbleListeners(
        bubbleView: BubbleView, userId: String, userName: String,
        avatarUrl: String, params: WindowManager.LayoutParams
    ) {
        try {
            bubbleView.setOnClickListener { onBubbleClicked(userId, userName, avatarUrl) }

            bubbleView.setOnDragListener { isInDeleteZone, deltaX, deltaY ->
                if (!isDraggingAnyBubble && (deltaX != 0f || deltaY != 0f)) {
                    isDraggingAnyBubble = true
                    showDeleteZone()
                }
                if (isInDeleteZone) {
                    deleteZoneView?.animateToActive(true)
                    bubbleView.animateDelete {
                        hideDeleteZone()
                        isDraggingAnyBubble = false
                        BubbleManager.removeBubble(this, userId)
                        checkAndStopService()
                    }
                } else {
                    deleteZoneView?.animateToActive(false)
                    bubbleParams[userId]?.let { p ->
                        p.x += deltaX.toInt()
                        p.y += deltaY.toInt()
                        val maxX = maxOf(BUBBLE_PADDING, screenWidth - bubbleView.width - BUBBLE_PADDING)
                        val maxY = maxOf(BUBBLE_PADDING, screenHeight - bubbleView.height - BUBBLE_PADDING)
                        p.x = p.x.coerceIn(BUBBLE_PADDING, maxX)
                        p.y = p.y.coerceIn(BUBBLE_PADDING, maxY)
                        try { windowManager?.updateViewLayout(bubbleView, p) } catch (e: Exception) { }
                    }
                }
            }

            bubbleView.setOnDragEndListener {
                hideDeleteZone()
                isDraggingAnyBubble = false
                mainHandler.postDelayed({ if (bubbleViews.containsKey(userId)) snapBubbleToEdge(userId) }, 100)
            }
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ Listener setup error: $e")
        }
    }

    private fun snapBubbleToEdge(userId: String) {
        val bubbleView = bubbleViews[userId] ?: return
        val params = bubbleParams[userId] ?: return
        val centerX = params.x + bubbleView.width / 2
        val targetX = if (centerX < screenWidth / 2) BUBBLE_PADDING + 10
        else screenWidth - bubbleView.width - BUBBLE_PADDING - 10

        android.animation.ValueAnimator.ofInt(params.x, targetX).apply {
            duration = 300
            interpolator = android.view.animation.OvershootInterpolator(1.5f)
            addUpdateListener { animation ->
                params.x = animation.animatedValue as Int
                try { windowManager?.updateViewLayout(bubbleView, params) } catch (e: Exception) { cancel() }
            }
            start()
        }
    }

    private fun updateBubblePosition(userId: String, x: Int, y: Int) {
        val bubbleView = bubbleViews[userId] ?: return
        val params = bubbleParams[userId] ?: return
        val maxX = maxOf(BUBBLE_PADDING, screenWidth - bubbleView.width - BUBBLE_PADDING)
        val maxY = maxOf(BUBBLE_PADDING, screenHeight - bubbleView.height - BUBBLE_PADDING)
        params.x = x.coerceIn(BUBBLE_PADDING, maxX)
        params.y = y.coerceIn(BUBBLE_PADDING, maxY)
        try { windowManager?.updateViewLayout(bubbleView, params) } catch (e: Exception) { }
    }

    private fun updateBubble(userId: String, unreadCount: Int, lastMessage: String) {
        try {
            bubbleViews[userId]?.let { it.updateUnreadCount(unreadCount); it.updateLastMessage(lastMessage); it.animateNewMessage() }
        } catch (e: Exception) { }
    }

    private fun hideBubble(userId: String) {
        mainHandler.post {
            try {
                val view = bubbleViews.remove(userId)
                bubbleParams.remove(userId)
                view?.let { it.cleanup(); windowManager?.removeView(it) }
                checkAndStopService()
            } catch (e: Exception) { }
        }
    }

    private fun hideAllBubbles() {
        mainHandler.post {
            try {
                bubbleViews.values.forEach { view -> try { view.cleanup(); windowManager?.removeView(view) } catch (e: Exception) { } }
                bubbleViews.clear()
                bubbleParams.clear()
                checkAndStopService()
            } catch (e: Exception) { }
        }
    }

    private fun onBubbleClicked(userId: String, userName: String, avatarUrl: String) {
        try {
            bubbleViews[userId]?.visibility = android.view.View.GONE
            showMiniChat(userId, userName, avatarUrl)
            BubbleManager.markAsRead(this, userId)
            val intent = Intent("CHAT_BUBBLE_CLICKED").apply {
                putExtra("userId", userId)
                putExtra("userName", userName)
                putExtra("avatarUrl", avatarUrl)
            }
            sendBroadcast(intent)
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ Bubble click error: $e")
        }
    }

    // ========================================
    // DELETE ZONE
    // ========================================

    private fun showDeleteZone() {
        if (deleteZoneView != null) { deleteZoneView?.show(); return }
        try {
            val deleteZone = DeleteZoneView(this)
            val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT, 150, layoutFlag,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                PixelFormat.TRANSLUCENT
            ).apply { gravity = Gravity.BOTTOM }

            windowManager?.addView(deleteZone, params)
            deleteZoneView = deleteZone
            deleteZoneParams = params
            deleteZone.show()
        } catch (e: Exception) { android.util.Log.e("BubbleService", "❌ showDeleteZone error: $e") }
    }

    private fun hideDeleteZone() { deleteZoneView?.hide() }

    // ========================================
    // NOTIFICATION & LIFECYCLE
    // ========================================

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(CHANNEL_ID, "Chat Bubbles", NotificationManager.IMPORTANCE_LOW)
                .apply { description = "Active chat bubbles"; setShowBadge(false) }
            getSystemService(NotificationManager::class.java)?.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val text = when {
            bubbleViews.isNotEmpty() && miniChatFlutterView != null -> "${bubbleViews.size} bubble(s) + Mini chat"
            bubbleViews.isNotEmpty() -> "${bubbleViews.size} bubble(s) active"
            miniChatFlutterView != null -> "Mini chat active"
            else -> "Chat bubbles ready"
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Chat Bubbles").setContentText(text)
            .setSmallIcon(R.drawable.bubble_background)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true).setShowWhen(false).build()
    }

    private fun checkAndStopService() {
        if (bubbleViews.isEmpty() && miniChatFlutterView == null && isServiceRunning) {
            stopForeground(true)
            stopSelf()
            isServiceRunning = false
        }
    }

    override fun onDestroy() {
        android.util.Log.d("BubbleService", "🛑 onDestroy")
        isServiceRunning = false

        miniChatFlutterView?.let { hideKeyboard(it) }
        BubbleManager.cleanup()

        deleteZoneView?.let { try { windowManager?.removeView(it) } catch (e: Exception) { } }
        deleteZoneView = null

        bubbleViews.values.forEach { view -> try { view.cleanup(); windowManager?.removeView(view) } catch (e: Exception) { } }
        bubbleViews.clear()
        bubbleParams.clear()

        miniChatFlutterView?.let {
            try {
                it.detachFromFlutterEngine()
                windowManager?.removeView(it)
            } catch (e: Exception) { }
        }
        miniChatFlutterView = null
        miniChatChannel?.setMethodCallHandler(null)
        miniChatChannel = null

        // FIX #2: Không destroy engine — nó là shared resource
        // Engine sẽ bị GC khi FlutterEngineCache.destroy() được gọi
        // hoặc khi app process bị kill
        miniChatEngine = null
        android.util.Log.d("BubbleService", "ℹ️ Shared engine kept alive (managed by FlutterEngineCache)")

        super.onDestroy()
    }
}
// android/app/src/main/kotlin/hust/appchat/bubble/BubbleOverlayService.kt
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
 * FIXES APPLIED:
 *
 * CRITICAL FIX — FlutterView attach conflict:
 *   Trước: attachToFlutterEngine() gọi trực tiếp mà không check engine có
 *          đang được BubbleActivity dùng không → IllegalStateException crash.
 *   Sau:  Tách riêng miniChatEngine ra khỏi shared engine (dùng ID riêng
 *         "mini_chat_overlay_engine"). MiniChat có engine RIÊNG, không đụng
 *         vào shared engine của BubbleActivity. Hoàn toàn loại bỏ conflict.
 *         Nếu mini_chat_overlay_engine chưa tồn tại, tạo mới và cache.
 *
 * FIX-2 — Engine null/dead guard:
 *   Thêm check engine còn executing dart trước khi attach FlutterView.
 *
 * FIX-3 — detachFromFlutterEngine() an toàn:
 *   Luôn detach FlutterView cũ trước khi attach mới, tránh double-attach.
 *
 * FIX-4 — hideMiniChat() cleanup đúng thứ tự:
 *   Detach FlutterView trước khi remove khỏi WindowManager.
 */
class BubbleOverlayService : Service() {

    private var windowManager: WindowManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val bubbleViews   = mutableMapOf<String, BubbleView>()
    private val bubbleParams  = mutableMapOf<String, WindowManager.LayoutParams>()

    // CRITICAL FIX: MiniChat dùng engine RIÊNG, không share với BubbleActivity
    private var miniChatFlutterView: FlutterView? = null
    private var miniChatParams: WindowManager.LayoutParams? = null
    private var miniChatEngine: FlutterEngine? = null
    private var miniChatChannel: MethodChannel? = null
    private var currentMiniChatUserId: String? = null

    private var deleteZoneView: DeleteZoneView? = null
    private var deleteZoneParams: WindowManager.LayoutParams? = null
    private var isDraggingAnyBubble = false

    private var screenWidth  = 0
    private var screenHeight = 0
    private var dimensionRetryCount = 0
    private val MAX_RETRY = 3
    private var isServiceRunning = false

    companion object {
        const val ACTION_SHOW_BUBBLE           = "SHOW_BUBBLE"
        const val ACTION_HIDE_BUBBLE           = "HIDE_BUBBLE"
        const val ACTION_UPDATE_BUBBLE         = "UPDATE_BUBBLE"
        const val ACTION_UPDATE_BUBBLE_POSITION = "UPDATE_BUBBLE_POSITION"
        const val ACTION_SHOW_MINI_CHAT        = "SHOW_MINI_CHAT"
        const val ACTION_HIDE_MINI_CHAT        = "HIDE_MINI_CHAT"
        const val ACTION_HIDE_ALL_BUBBLES      = "HIDE_ALL_BUBBLES"

        private const val NOTIFICATION_ID = 12345
        private const val CHANNEL_ID      = "chat_bubbles"

        // CRITICAL FIX: Engine ID riêng cho MiniChat — KHÔNG dùng SHARED_ENGINE_ID
        private const val MINI_CHAT_ENGINE_ID = "mini_chat_overlay_engine"
        private const val MINI_CHAT_CHANNEL   = "mini_chat_channel"

        private const val BUBBLE_PADDING = 10
    }

    // ========================================
    // LIFECYCLE
    // ========================================

    override fun onCreate() {
        super.onCreate()
        try {
            windowManager = getSystemService(WINDOW_SERVICE) as? WindowManager
            getScreenDimensionsWithRetry()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) createNotificationChannel()
            BubbleManager.init(this)
            isServiceRunning = true
            android.util.Log.d("BubbleService", "✅ onCreate: ${screenWidth}x${screenHeight}")
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ onCreate failed: $e")
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
            android.util.Log.e("BubbleService", "❌ onStartCommand: $e")
        }
        return START_STICKY
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
                    screenWidth  = bounds.width()
                    screenHeight = bounds.height()
                    return
                }
            }
            val dm = resources.displayMetrics
            if (dm.widthPixels > 0) {
                screenWidth  = dm.widthPixels
                screenHeight = dm.heightPixels
                return
            }
            if (dimensionRetryCount < MAX_RETRY) {
                dimensionRetryCount++
                mainHandler.postDelayed({ attemptGetScreenDimensions() },
                    200L * dimensionRetryCount)
                return
            }
            screenWidth  = 1080
            screenHeight = 2340
        } catch (e: Exception) {
            screenWidth  = 1080
            screenHeight = 2340
            android.util.Log.e("BubbleService", "❌ Screen dimensions: $e")
        }
    }

    // ========================================
    // INTENT ROUTING
    // ========================================

    private fun handleIntent(intent: Intent) {
        when (intent.action) {
            ACTION_SHOW_BUBBLE -> {
                val userId      = intent.getStringExtra("userId") ?: return
                val userName    = intent.getStringExtra("userName") ?: ""
                val avatarUrl   = intent.getStringExtra("avatarUrl") ?: ""
                val unreadCount = intent.getIntExtra("unreadCount", 0)
                val lastMessage = intent.getStringExtra("lastMessage") ?: ""
                val posX        = intent.getIntExtra("positionX", screenWidth - 100)
                val posY        = intent.getIntExtra("positionY", 200)
                showBubble(userId, userName, avatarUrl, unreadCount, lastMessage, posX, posY)
            }
            ACTION_UPDATE_BUBBLE -> {
                val userId = intent.getStringExtra("userId") ?: return
                updateBubble(userId,
                    intent.getIntExtra("unreadCount", 0),
                    intent.getStringExtra("lastMessage") ?: "")
            }
            ACTION_UPDATE_BUBBLE_POSITION -> {
                val userId = intent.getStringExtra("userId") ?: return
                val x = intent.getIntExtra("positionX", -1)
                val y = intent.getIntExtra("positionY", -1)
                if (x >= 0 && y >= 0) updateBubblePosition(userId, x, y)
            }
            ACTION_HIDE_BUBBLE    -> hideBubble(intent.getStringExtra("userId") ?: return)
            ACTION_SHOW_MINI_CHAT -> {
                val userId   = intent.getStringExtra("userId") ?: return
                val userName = intent.getStringExtra("userName") ?: ""
                val avatar   = intent.getStringExtra("avatarUrl") ?: ""
                showMiniChat(userId, userName, avatar)
            }
            ACTION_HIDE_MINI_CHAT  -> hideMiniChat()
            ACTION_HIDE_ALL_BUBBLES -> hideAllBubbles()
        }
    }

    // ========================================
    // MINI CHAT — ENGINE RIÊNG (CRITICAL FIX)
    // ========================================

    private fun showMiniChat(userId: String, userName: String, avatarUrl: String) {
        android.util.Log.d("BubbleService", "💬 showMiniChat: $userName")
        mainHandler.post {
            try {
                // Dọn view cũ an toàn
                cleanupMiniChatView()
                currentMiniChatUserId = userId
                initializeMiniChatEngine { continueShowingMiniChat(userId, userName, avatarUrl) }
            } catch (e: Exception) {
                android.util.Log.e("BubbleService", "❌ showMiniChat failed: $e")
            }
        }
    }

    /**
     * CRITICAL FIX: Dùng engine RIÊNG "mini_chat_overlay_engine" cho MiniChat.
     * Không bao giờ đụng vào SHARED_ENGINE_ID của BubbleActivity.
     */
    private fun initializeMiniChatEngine(onReady: () -> Unit) {
        val cache = FlutterEngineCache.getInstance()
        var engine = cache.get(MINI_CHAT_ENGINE_ID)

        // Validate engine còn sống
        if (engine != null && !engine.dartExecutor.isExecutingDart) {
            android.util.Log.w("BubbleService", "⚠️ MiniChat engine dead, recreating")
            cache.remove(MINI_CHAT_ENGINE_ID)
            engine = null
        }

        if (engine != null) {
            android.util.Log.d("BubbleService", "♻️ Reusing mini chat engine")
            miniChatEngine = engine
            onReady()
        } else {
            android.util.Log.d("BubbleService", "🔧 Creating new mini chat engine")
            val newEngine = FlutterEngine(this)
            newEngine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            newEngine.lifecycleChannel.appIsResumed()
            cache.put(MINI_CHAT_ENGINE_ID, newEngine)
            miniChatEngine = newEngine

            // Chờ engine warmup
            mainHandler.postDelayed({
                android.util.Log.d("BubbleService", "✅ MiniChat engine ready")
                onReady()
            }, 600L)
        }
    }

    private fun continueShowingMiniChat(userId: String, userName: String, avatarUrl: String) {
        val engine = miniChatEngine ?: run {
            android.util.Log.e("BubbleService", "❌ Engine null in continueShowingMiniChat")
            return
        }

        // FIX-2: guard — engine phải đang execute dart
        if (!engine.dartExecutor.isExecutingDart) {
            android.util.Log.e("BubbleService", "❌ Engine not executing dart")
            return
        }

        try {
            // FIX-3: tạo FlutterView mới, KHÔNG reuse view cũ
            val flutterView = FlutterView(this)
            // attach an toàn (engine riêng, không conflict)
            flutterView.attachToFlutterEngine(engine)
            miniChatFlutterView = flutterView

            setupMiniChatChannel()

            val width  = ((screenWidth * 0.85).toInt()).coerceIn(300, 600)
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

            windowManager?.addView(flutterView, miniChatParams)
            android.util.Log.d("BubbleService", "✅ MiniChat view added to WindowManager")

            mainHandler.postDelayed({
                flutterView.requestFocus()
                flutterView.isFocusableInTouchMode = true
                mainHandler.postDelayed({
                    sendMiniChatData(userId, userName, avatarUrl)
                }, 300L)
            }, 150L)

        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ continueShowingMiniChat failed: $e")
            cleanupMiniChatView()
        }
    }

    private fun setupMiniChatChannel() {
        val engine = miniChatEngine ?: return
        try {
            miniChatChannel = MethodChannel(engine.dartExecutor.binaryMessenger, MINI_CHAT_CHANNEL)
            miniChatChannel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "minimize" -> {
                        miniChatFlutterView?.let { hideKeyboard(it) }
                        hideMiniChat()
                        currentMiniChatUserId?.let { bubbleViews[it]?.visibility = View.VISIBLE }
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
            android.util.Log.d("BubbleService", "✅ MiniChat MethodChannel ready")
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ MiniChat channel setup failed: $e")
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

    /**
     * FIX-4: cleanup theo đúng thứ tự — detach rồi mới remove từ WM
     */
    private fun cleanupMiniChatView() {
        val view = miniChatFlutterView ?: return
        mainHandler.post {
            try {
                hideKeyboard(view)
                // FIX-4: detach trước
                try { view.detachFromFlutterEngine() } catch (_: Exception) {}
                // rồi mới remove khỏi WindowManager
                try { windowManager?.removeView(view) } catch (_: Exception) {}
            } catch (e: Exception) {
                android.util.Log.e("BubbleService", "❌ cleanupMiniChatView: $e")
            } finally {
                miniChatFlutterView = null
                miniChatParams      = null
                miniChatChannel?.setMethodCallHandler(null)
                miniChatChannel     = null
                // Không null miniChatEngine — cần giữ engine sống cho lần sau
            }
        }
    }

    private fun hideMiniChat() {
        android.util.Log.d("BubbleService", "🔽 hideMiniChat")
        cleanupMiniChatView()
        mainHandler.postDelayed({
            currentMiniChatUserId = null
            checkAndStopService()
        }, 150L)
    }

    // ========================================
    // KEYBOARD HELPERS
    // ========================================

    private fun showKeyboard(view: View) {
        try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.showSoftInput(view, InputMethodManager.SHOW_IMPLICIT)
        } catch (_: Exception) {}
    }

    private fun hideKeyboard(view: View) {
        try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.hideSoftInputFromWindow(view.windowToken, 0)
        } catch (_: Exception) {}
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
                if (screenWidth <= 0 || screenHeight <= 0) {
                    getScreenDimensionsWithRetry()
                    return@post
                }

                bubbleViews[userId]?.let {
                    try { windowManager?.removeView(it) } catch (_: Exception) {}
                }

                val bubbleView = BubbleView(this, userId, userName, avatarUrl)
                bubbleView.updateUnreadCount(unreadCount)
                bubbleView.updateLastMessage(lastMessage)

                val bubbleSize = 64
                val maxBoundX = maxOf(BUBBLE_PADDING, screenWidth  - bubbleSize - BUBBLE_PADDING)
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

                mainHandler.postDelayed({
                    setupBubbleListeners(bubbleView, userId, userName, avatarUrl, params)
                }, 100L)
                mainHandler.postDelayed({
                    if (bubbleViews.containsKey(userId)) snapBubbleToEdge(userId)
                }, 500L)

            } catch (e: Exception) {
                android.util.Log.e("BubbleService", "❌ showBubble failed: $e")
            }
        }
    }

    private fun setupBubbleListeners(
        bubbleView: BubbleView,
        userId: String, userName: String,
        avatarUrl: String,
        params: WindowManager.LayoutParams
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
                        val maxX = maxOf(BUBBLE_PADDING, screenWidth  - bubbleView.width - BUBBLE_PADDING)
                        val maxY = maxOf(BUBBLE_PADDING, screenHeight - bubbleView.height - BUBBLE_PADDING)
                        p.x = p.x.coerceIn(BUBBLE_PADDING, maxX)
                        p.y = p.y.coerceIn(BUBBLE_PADDING, maxY)
                        try { windowManager?.updateViewLayout(bubbleView, p) } catch (_: Exception) {}
                    }
                }
            }

            bubbleView.setOnDragEndListener {
                hideDeleteZone()
                isDraggingAnyBubble = false
                mainHandler.postDelayed({
                    if (bubbleViews.containsKey(userId)) snapBubbleToEdge(userId)
                }, 100L)
            }
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ Listener setup: $e")
        }
    }

    private fun snapBubbleToEdge(userId: String) {
        val bubbleView = bubbleViews[userId] ?: return
        val params     = bubbleParams[userId] ?: return
        val centerX    = params.x + bubbleView.width / 2
        val targetX    = if (centerX < screenWidth / 2) BUBBLE_PADDING + 10
        else screenWidth - bubbleView.width - BUBBLE_PADDING - 10

        android.animation.ValueAnimator.ofInt(params.x, targetX).apply {
            duration = 300
            interpolator = android.view.animation.OvershootInterpolator(1.5f)
            addUpdateListener { anim ->
                // FIX: check view masih ada sebelum update
                if (!bubbleViews.containsKey(userId)) { cancel(); return@addUpdateListener }
                params.x = anim.animatedValue as Int
                try { windowManager?.updateViewLayout(bubbleView, params) }
                catch (_: Exception) { cancel() }
            }
            start()
        }
    }

    private fun updateBubblePosition(userId: String, x: Int, y: Int) {
        val bubbleView = bubbleViews[userId] ?: return
        val params     = bubbleParams[userId] ?: return
        val maxX = maxOf(BUBBLE_PADDING, screenWidth  - bubbleView.width  - BUBBLE_PADDING)
        val maxY = maxOf(BUBBLE_PADDING, screenHeight - bubbleView.height - BUBBLE_PADDING)
        params.x = x.coerceIn(BUBBLE_PADDING, maxX)
        params.y = y.coerceIn(BUBBLE_PADDING, maxY)
        try { windowManager?.updateViewLayout(bubbleView, params) } catch (_: Exception) {}
    }

    private fun updateBubble(userId: String, unreadCount: Int, lastMessage: String) {
        try {
            bubbleViews[userId]?.let {
                it.updateUnreadCount(unreadCount)
                it.updateLastMessage(lastMessage)
                it.animateNewMessage()
            }
        } catch (_: Exception) {}
    }

    private fun hideBubble(userId: String) {
        mainHandler.post {
            try {
                val view = bubbleViews.remove(userId)
                bubbleParams.remove(userId)
                view?.let {
                    it.cleanup()
                    try { windowManager?.removeView(it) } catch (_: Exception) {}
                }
                checkAndStopService()
            } catch (_: Exception) {}
        }
    }

    private fun hideAllBubbles() {
        mainHandler.post {
            try {
                bubbleViews.values.forEach { view ->
                    view.cleanup()
                    try { windowManager?.removeView(view) } catch (_: Exception) {}
                }
                bubbleViews.clear()
                bubbleParams.clear()
                checkAndStopService()
            } catch (_: Exception) {}
        }
    }

    private fun onBubbleClicked(userId: String, userName: String, avatarUrl: String) {
        try {
            bubbleViews[userId]?.visibility = View.GONE
            showMiniChat(userId, userName, avatarUrl)
            BubbleManager.markAsRead(this, userId)
            val intent = Intent("CHAT_BUBBLE_CLICKED").apply {
                putExtra("userId",    userId)
                putExtra("userName",  userName)
                putExtra("avatarUrl", avatarUrl)
            }
            sendBroadcast(intent)
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ Bubble click: $e")
        }
    }

    // ========================================
    // DELETE ZONE
    // ========================================

    private fun showDeleteZone() {
        if (deleteZoneView != null) { deleteZoneView?.show(); return }
        try {
            val zone = DeleteZoneView(this)
            val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE

            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT, 150, layoutFlag,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE,
                PixelFormat.TRANSLUCENT
            ).apply { gravity = Gravity.BOTTOM }

            windowManager?.addView(zone, params)
            deleteZoneView  = zone
            deleteZoneParams = params
            zone.show()
        } catch (e: Exception) {
            android.util.Log.e("BubbleService", "❌ showDeleteZone: $e")
        }
    }

    private fun hideDeleteZone() { deleteZoneView?.hide() }

    // ========================================
    // NOTIFICATION & STOP
    // ========================================

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Chat Bubbles", NotificationManager.IMPORTANCE_LOW
            ).apply { description = "Active chat bubbles"; setShowBadge(false) }
            getSystemService(NotificationManager::class.java)
                ?.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        val text = when {
            bubbleViews.isNotEmpty() && miniChatFlutterView != null ->
                "${bubbleViews.size} bubble(s) + Mini chat"
            bubbleViews.isNotEmpty() -> "${bubbleViews.size} bubble(s) active"
            miniChatFlutterView != null -> "Mini chat active"
            else -> "Chat bubbles ready"
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Chat Bubbles")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    private fun checkAndStopService() {
        if (bubbleViews.isEmpty() && miniChatFlutterView == null && isServiceRunning) {
            stopForeground(true)
            stopSelf()
            isServiceRunning = false
        }
    }

    // ========================================
    // DESTROY
    // ========================================

    override fun onDestroy() {
        android.util.Log.d("BubbleService", "🛑 onDestroy")
        isServiceRunning = false

        miniChatFlutterView?.let { hideKeyboard(it) }

        BubbleManager.cleanup()

        deleteZoneView?.let {
            try { windowManager?.removeView(it) } catch (_: Exception) {}
        }
        deleteZoneView = null

        bubbleViews.values.forEach { view ->
            try { view.cleanup(); windowManager?.removeView(view) } catch (_: Exception) {}
        }
        bubbleViews.clear()
        bubbleParams.clear()

        // FIX-4: detach trước khi remove
        miniChatFlutterView?.let {
            try { it.detachFromFlutterEngine() } catch (_: Exception) {}
            try { windowManager?.removeView(it)  } catch (_: Exception) {}
        }
        miniChatFlutterView = null
        miniChatChannel?.setMethodCallHandler(null)
        miniChatChannel     = null

        miniChatEngine      = null

        android.util.Log.d("BubbleService",
            "ℹ️ Engines kept alive in cache (shared + mini_chat)")
        super.onDestroy()
    }
}
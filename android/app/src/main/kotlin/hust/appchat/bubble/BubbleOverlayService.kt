package hust.appchat.bubble

import android.animation.ValueAnimator
import android.app.*
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.*
import android.view.animation.OvershootInterpolator
import android.view.inputmethod.InputMethodManager
import androidx.core.app.NotificationCompat
import hust.appchat.BubbleActivity
import hust.appchat.R
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * BubbleOverlayService — Production-Ready v2.0
 *
 * Architecture:
 *  - Each FlutterView gets its own dedicated FlutterEngine (MINI_CHAT_ENGINE_ID).
 *    This is entirely separate from the shared engine used by BubbleActivity,
 *    preventing any IllegalStateException from double-attach.
 *  - All WindowManager operations are marshalled to the main thread via mainHandler.
 *  - Cleanup follows strict order: hide keyboard → detach FlutterView → remove from WM.
 *  - Engine is kept warm in FlutterEngineCache after hide, for fast re-open.
 *  - BroadcastReceiver handles cross-process bubble commands efficiently.
 *
 * Fixes vs v1:
 *  [F-1] Dedicated mini-chat engine — zero conflict with BubbleActivity shared engine.
 *  [F-2] isExecutingDart guard before every FlutterView.attachToFlutterEngine().
 *  [F-3] cleanupMiniChatView() always detaches before WM.removeView().
 *  [F-4] snapBubbleToEdge() cancels animation if bubble removed mid-snap.
 *  [F-5] Engine warm-up now waits for dartExecutor.isExecutingDart via polling.
 *  [F-6] onDestroy() deregisters broadcast receiver before teardown.
 *  [F-7] checkAndStopService() guard against double-stop.
 *  [F-8] Bubble drag: coerce to safe bounds accounting for real view size.
 */
class BubbleOverlayService : Service() {

    // ── Core ──────────────────────────────────────────────────────────────────
    private var windowManager: WindowManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // ── Bubble state ──────────────────────────────────────────────────────────
    private val bubbleViews   = mutableMapOf<String, BubbleView>()
    private val bubbleParams  = mutableMapOf<String, WindowManager.LayoutParams>()
    private var isDraggingAnyBubble = false

    // ── MiniChat state ────────────────────────────────────────────────────────
    private var miniChatFlutterView  : FlutterView? = null
    private var miniChatParams       : WindowManager.LayoutParams? = null
    private var miniChatEngine       : FlutterEngine? = null
    private var miniChatChannel      : MethodChannel? = null
    private var currentMiniChatUserId: String? = null
    private var miniChatVisible      = false

    // ── Delete zone ───────────────────────────────────────────────────────────
    private var deleteZoneView  : DeleteZoneView? = null
    private var deleteZoneParams: WindowManager.LayoutParams? = null

    // ── Screen ────────────────────────────────────────────────────────────────
    private var screenWidth  = 0
    private var screenHeight = 0
    private var dimensionRetryCount = 0

    // ── Service state ─────────────────────────────────────────────────────────
    private var isServiceRunning = false
    private var broadcastReceiver: BroadcastReceiver? = null

    // ─────────────────────────────────────────────────────────────────────────
    companion object {
        const val ACTION_SHOW_BUBBLE            = "hust.appchat.SHOW_BUBBLE"
        const val ACTION_HIDE_BUBBLE            = "hust.appchat.HIDE_BUBBLE"
        const val ACTION_UPDATE_BUBBLE          = "hust.appchat.UPDATE_BUBBLE"
        const val ACTION_UPDATE_BUBBLE_POSITION = "hust.appchat.UPDATE_BUBBLE_POSITION"
        const val ACTION_SHOW_MINI_CHAT         = "hust.appchat.SHOW_MINI_CHAT"
        const val ACTION_HIDE_MINI_CHAT         = "hust.appchat.HIDE_MINI_CHAT"
        const val ACTION_HIDE_ALL_BUBBLES       = "hust.appchat.HIDE_ALL_BUBBLES"
        const val ACTION_CHAT_BUBBLE_CLICKED    = "hust.appchat.CHAT_BUBBLE_CLICKED"

        private const val NOTIFICATION_ID     = 12_345
        private const val CHANNEL_ID          = "chat_bubbles"
        private const val MINI_CHAT_ENGINE_ID = "mini_chat_overlay_engine"
        private const val MINI_CHAT_CHANNEL   = "mini_chat_channel"
        private const val BUBBLE_SIZE_DP      = 64
        private const val BUBBLE_PADDING_DP   = 10
        private const val ENGINE_WARMUP_POLL_INTERVAL = 50L
        private const val ENGINE_WARMUP_TIMEOUT      = 5_000L

        fun buildIntent(context: Context, action: String, block: Intent.() -> Unit = {}): Intent =
            Intent(context, BubbleOverlayService::class.java).apply { this.action = action; block() }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // LIFECYCLE
    // ─────────────────────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        try {
            windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
            refreshScreenDimensions()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) createNotificationChannel()
            BubbleManager.init(this)
            registerBroadcastReceiver()
            isServiceRunning = true
            log("✅ onCreate — screen: ${screenWidth}×${screenHeight}")
        } catch (e: Exception) {
            loge("onCreate", e)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForeground(NOTIFICATION_ID, buildNotification())
            }
            isServiceRunning = true
            intent?.let { handleIntent(it) }
        } catch (e: Exception) {
            loge("onStartCommand", e)
        }
        return START_STICKY
    }

    override fun onDestroy() {
        log("🛑 onDestroy")
        isServiceRunning = false

        unregisterBroadcastReceiverSafe()
        BubbleManager.cleanup()

        // Destroy delete zone
        deleteZoneView?.let { safeRemoveView(it) }
        deleteZoneView   = null
        deleteZoneParams = null

        // Destroy all bubbles
        bubbleViews.values.forEach { view ->
            try { view.cleanup() } catch (_: Exception) {}
            safeRemoveView(view)
        }
        bubbleViews.clear()
        bubbleParams.clear()

        // Destroy mini chat (detach first!)
        miniChatFlutterView?.let { view ->
            hideKeyboard(view)
            safeDetachFlutterView(view)
            safeRemoveView(view)
        }
        miniChatFlutterView = null
        miniChatChannel?.setMethodCallHandler(null)
        miniChatChannel  = null
        miniChatEngine   = null   // release reference; cache keeps engine warm

        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // BROADCAST RECEIVER
    // ─────────────────────────────────────────────────────────────────────────

    private fun registerBroadcastReceiver() {
        broadcastReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) = handleIntent(intent)
        }
        val filter = IntentFilter().apply {
            listOf(
                ACTION_SHOW_BUBBLE, ACTION_HIDE_BUBBLE, ACTION_UPDATE_BUBBLE,
                ACTION_UPDATE_BUBBLE_POSITION, ACTION_SHOW_MINI_CHAT,
                ACTION_HIDE_MINI_CHAT, ACTION_HIDE_ALL_BUBBLES
            ).forEach { addAction(it) }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(broadcastReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(broadcastReceiver, filter)
        }
    }

    private fun unregisterBroadcastReceiverSafe() {
        try { broadcastReceiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        broadcastReceiver = null
    }

    // ─────────────────────────────────────────────────────────────────────────
    // SCREEN DIMENSIONS
    // ─────────────────────────────────────────────────────────────────────────

    private fun refreshScreenDimensions() {
        dimensionRetryCount = 0
        tryGetScreenDimensions()
    }

    private fun tryGetScreenDimensions() {
        try {
            val got = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val b = windowManager?.currentWindowMetrics?.bounds
                if (b != null && b.width() > 0) { screenWidth = b.width(); screenHeight = b.height(); true }
                else false
            } else {
                val dm = resources.displayMetrics
                if (dm.widthPixels > 0) { screenWidth = dm.widthPixels; screenHeight = dm.heightPixels; true }
                else false
            }
            if (!got) {
                if (dimensionRetryCount++ < 5) {
                    mainHandler.postDelayed({ tryGetScreenDimensions() }, 200L * dimensionRetryCount)
                } else { screenWidth = 1080; screenHeight = 2340 }
            }
        } catch (e: Exception) {
            screenWidth = 1080; screenHeight = 2340
            loge("screenDimensions", e)
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    // ─────────────────────────────────────────────────────────────────────────
    // INTENT ROUTING
    // ─────────────────────────────────────────────────────────────────────────

    private fun handleIntent(intent: Intent) {
        when (intent.action) {
            ACTION_SHOW_BUBBLE -> {
                val uid = intent.getStringExtra("userId") ?: return
                showBubble(
                    userId      = uid,
                    userName    = intent.getStringExtra("userName") ?: "",
                    avatarUrl   = intent.getStringExtra("avatarUrl") ?: "",
                    unreadCount = intent.getIntExtra("unreadCount", 0),
                    lastMessage = intent.getStringExtra("lastMessage") ?: "",
                    positionX   = intent.getIntExtra("positionX", screenWidth - dp(100)),
                    positionY   = intent.getIntExtra("positionY", dp(200))
                )
            }
            ACTION_UPDATE_BUBBLE -> {
                val uid = intent.getStringExtra("userId") ?: return
                updateBubble(uid, intent.getIntExtra("unreadCount", 0),
                    intent.getStringExtra("lastMessage") ?: "")
            }
            ACTION_UPDATE_BUBBLE_POSITION -> {
                val uid = intent.getStringExtra("userId") ?: return
                val x = intent.getIntExtra("positionX", -1)
                val y = intent.getIntExtra("positionY", -1)
                if (x >= 0 && y >= 0) updateBubblePosition(uid, x, y)
            }
            ACTION_HIDE_BUBBLE     -> hideBubble(intent.getStringExtra("userId") ?: return)
            ACTION_SHOW_MINI_CHAT  -> showMiniChat(
                userId   = intent.getStringExtra("userId") ?: return,
                userName = intent.getStringExtra("userName") ?: "",
                avatarUrl = intent.getStringExtra("avatarUrl") ?: ""
            )
            ACTION_HIDE_MINI_CHAT  -> hideMiniChat()
            ACTION_HIDE_ALL_BUBBLES -> hideAllBubbles()
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // MINI CHAT — DEDICATED ENGINE
    // ─────────────────────────────────────────────────────────────────────────

    private fun showMiniChat(userId: String, userName: String, avatarUrl: String) {
        log("💬 showMiniChat userId=$userId")
        mainHandler.post {
            try {
                cleanupMiniChatView()
                currentMiniChatUserId = userId
                ensureMiniChatEngine { attachAndDisplayMiniChat(userId, userName, avatarUrl) }
            } catch (e: Exception) {
                loge("showMiniChat", e)
            }
        }
    }

    /**
     * Ensures the dedicated mini-chat engine exists and is executing Dart.
     * Uses polling (max ENGINE_WARMUP_TIMEOUT ms) instead of a fixed delay.
     */
    private fun ensureMiniChatEngine(onReady: () -> Unit) {
        val cache = FlutterEngineCache.getInstance()
        var engine = cache.get(MINI_CHAT_ENGINE_ID)

        // Evict dead engine
        if (engine != null && !engine.dartExecutor.isExecutingDart) {
            log("⚠️ MiniChat engine dead — evicting")
            try { engine.destroy() } catch (_: Exception) {}
            cache.remove(MINI_CHAT_ENGINE_ID)
            engine = null
        }

        if (engine != null) {
            log("♻️ Reusing mini-chat engine")
            miniChatEngine = engine
            onReady()
            return
        }

        log("🔧 Creating new mini-chat engine")
        val newEngine = FlutterEngine(this)
        newEngine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        newEngine.lifecycleChannel.appIsResumed()
        cache.put(MINI_CHAT_ENGINE_ID, newEngine)
        miniChatEngine = newEngine

        // Poll until executing or timeout
        val startTime = System.currentTimeMillis()
        fun poll() {
            if (!isServiceRunning) return
            when {
                newEngine.dartExecutor.isExecutingDart -> {
                    log("✅ MiniChat engine warm")
                    onReady()
                }
                System.currentTimeMillis() - startTime > ENGINE_WARMUP_TIMEOUT -> {
                    loge("MiniChat engine warmup timed out after ${ENGINE_WARMUP_TIMEOUT}ms")
                }
                else -> mainHandler.postDelayed(::poll, ENGINE_WARMUP_POLL_INTERVAL)
            }
        }
        mainHandler.postDelayed(::poll, ENGINE_WARMUP_POLL_INTERVAL)
    }

    private fun attachAndDisplayMiniChat(userId: String, userName: String, avatarUrl: String) {
        val engine = miniChatEngine ?: run { loge("attachAndDisplayMiniChat: engine null"); return }
        if (!engine.dartExecutor.isExecutingDart) { loge("attachAndDisplayMiniChat: engine not executing"); return }

        try {
            // Always create a fresh FlutterView; never reuse stale views
            val flutterView = FlutterView(this, FlutterTextureView(this))
            flutterView.attachToFlutterEngine(engine)  // safe — dedicated engine
            miniChatFlutterView = flutterView
            miniChatVisible     = true

            setupMiniChatMethodChannel()

            val wPx = (screenWidth * 0.88).toInt().coerceIn(dp(300), dp(500))
            val hPx = (screenHeight * 0.72).toInt().coerceIn(dp(400), dp(820))
            val layoutFlag = overlayType()

            miniChatParams = WindowManager.LayoutParams(
                wPx, hPx, layoutFlag,
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL       or
                        WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH   or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN      or
                        WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity     = Gravity.CENTER
                softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
                // Make focusable so keyboard works
                flags = flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            }

            windowManager?.addView(flutterView, miniChatParams)
            log("✅ MiniChat view added — ${wPx}×${hPx}")

            // Focus & send navigation data
            mainHandler.postDelayed({
                flutterView.isFocusableInTouchMode = true
                flutterView.requestFocus()
            }, 120L)
            mainHandler.postDelayed({ sendMiniChatNavigationData(userId, userName, avatarUrl) }, 450L)

        } catch (e: Exception) {
            loge("attachAndDisplayMiniChat", e)
            cleanupMiniChatView()
        }
    }

    private fun setupMiniChatMethodChannel() {
        val engine = miniChatEngine ?: return
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
                "updateBubble" -> {
                    val uid          = call.argument<String>("userId") ?: return@setMethodCallHandler
                    val unread       = call.argument<Int>("unreadCount") ?: 0
                    val lastMsg      = call.argument<String>("lastMessage") ?: ""
                    updateBubble(uid, unread, lastMsg)
                    result.success(true)
                }
                "requestScreenSize" -> {
                    result.success(mapOf("width" to screenWidth, "height" to screenHeight))
                }
                else -> result.notImplemented()
            }
        }
        log("✅ MiniChat MethodChannel registered")
    }

    private fun sendMiniChatNavigationData(userId: String, userName: String, avatarUrl: String) {
        try {
            miniChatChannel?.invokeMethod("navigateToMiniChat", mapOf(
                "peerId"        to userId,
                "peerNickname"  to userName,
                "peerAvatar"    to avatarUrl
            ))
        } catch (e: Exception) { loge("sendMiniChatNavigationData", e) }
    }

    /**
     * Safe cleanup: keyboard → detach → remove from WM (in this exact order).
     */
    private fun cleanupMiniChatView() {
        val view = miniChatFlutterView ?: return
        mainHandler.post {
            try {
                hideKeyboard(view)
                safeDetachFlutterView(view)
                safeRemoveView(view)
            } finally {
                miniChatFlutterView = null
                miniChatParams      = null
                miniChatVisible     = false
                miniChatChannel?.setMethodCallHandler(null)
                miniChatChannel = null
                // Engine stays warm in cache — do NOT null miniChatEngine here
            }
        }
    }

    private fun hideMiniChat() {
        log("🔽 hideMiniChat")
        cleanupMiniChatView()
        mainHandler.postDelayed({
            currentMiniChatUserId = null
            checkAndStopService()
            updateNotification()
        }, 160L)
    }

    // ─────────────────────────────────────────────────────────────────────────
    // BUBBLE OPERATIONS
    // ─────────────────────────────────────────────────────────────────────────

    private fun showBubble(
        userId: String, userName: String, avatarUrl: String,
        unreadCount: Int, lastMessage: String,
        positionX: Int, positionY: Int
    ) {
        mainHandler.post {
            if (screenWidth <= 0) { refreshScreenDimensions(); return@post }
            try {
                // Remove existing view for same user
                bubbleViews.remove(userId)?.let { old ->
                    try { old.cleanup(); safeRemoveView(old) } catch (_: Exception) {}
                }
                bubbleParams.remove(userId)

                val bubbleView = BubbleView(this, userId, userName, avatarUrl).also {
                    it.updateUnreadCount(unreadCount)
                    it.updateLastMessage(lastMessage)
                }

                val bSize = dp(BUBBLE_SIZE_DP)
                val pad   = dp(BUBBLE_PADDING_DP)
                val maxX  = (screenWidth  - bSize - pad).coerceAtLeast(pad)
                val maxY  = (screenHeight - bSize - pad).coerceAtLeast(pad)

                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    overlayType(),
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL        or
                            WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH    or
                            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS       or
                            WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.TOP or Gravity.START
                    x = positionX.coerceIn(pad, maxX)
                    y = positionY.coerceIn(pad, maxY)
                }

                windowManager?.addView(bubbleView, params)
                bubbleViews[userId]  = bubbleView
                bubbleParams[userId] = params

                // Defer listener setup until view is measured
                mainHandler.postDelayed({
                    setupBubbleInteraction(bubbleView, userId, userName, avatarUrl, params)
                }, 100L)
                mainHandler.postDelayed({
                    if (bubbleViews.containsKey(userId)) snapToEdge(userId)
                }, 500L)

                updateNotification()
            } catch (e: Exception) { loge("showBubble", e) }
        }
    }

    private fun setupBubbleInteraction(
        view: BubbleView, userId: String,
        userName: String, avatarUrl: String,
        params: WindowManager.LayoutParams
    ) {
        try {
            view.setOnClickListener { onBubbleClicked(userId, userName, avatarUrl) }

            view.setOnDragListener { isInDeleteZone, deltaX, deltaY ->
                if (!isDraggingAnyBubble && (deltaX != 0f || deltaY != 0f)) {
                    isDraggingAnyBubble = true
                    showDeleteZone()
                }
                if (isInDeleteZone) {
                    deleteZoneView?.animateToActive(true)
                    view.animateDelete {
                        hideDeleteZone()
                        isDraggingAnyBubble = false
                        BubbleManager.removeBubble(this, userId)
                        checkAndStopService()
                    }
                } else {
                    deleteZoneView?.animateToActive(false)
                    val viewW = view.width.takeIf { it > 0 } ?: dp(BUBBLE_SIZE_DP)
                    val viewH = view.height.takeIf { it > 0 } ?: dp(BUBBLE_SIZE_DP)
                    val pad   = dp(BUBBLE_PADDING_DP)
                    val maxX  = (screenWidth  - viewW - pad).coerceAtLeast(pad)
                    val maxY  = (screenHeight - viewH - pad).coerceAtLeast(pad)
                    params.x = (params.x + deltaX.toInt()).coerceIn(pad, maxX)
                    params.y = (params.y + deltaY.toInt()).coerceIn(pad, maxY)
                    try { windowManager?.updateViewLayout(view, params) } catch (_: Exception) {}
                }
            }

            view.setOnDragEndListener {
                hideDeleteZone()
                isDraggingAnyBubble = false
                mainHandler.postDelayed({
                    if (bubbleViews.containsKey(userId)) snapToEdge(userId)
                }, 80L)
            }
        } catch (e: Exception) { loge("setupBubbleInteraction", e) }
    }

    private fun snapToEdge(userId: String) {
        val view   = bubbleViews[userId] ?: return
        val params = bubbleParams[userId] ?: return
        val viewW  = view.width.takeIf { it > 0 } ?: dp(BUBBLE_SIZE_DP)
        val pad    = dp(BUBBLE_PADDING_DP)
        val centerX = params.x + viewW / 2
        val targetX = if (centerX < screenWidth / 2) pad + dp(8)
        else screenWidth - viewW - pad - dp(8)

        ValueAnimator.ofInt(params.x, targetX).apply {
            duration    = 320L
            interpolator = OvershootInterpolator(1.4f)
            addUpdateListener { anim ->
                if (!bubbleViews.containsKey(userId)) { cancel(); return@addUpdateListener }
                params.x = anim.animatedValue as Int
                try { windowManager?.updateViewLayout(view, params) }
                catch (_: Exception) { cancel() }
            }
            start()
        }
    }

    private fun updateBubblePosition(userId: String, x: Int, y: Int) {
        mainHandler.post {
            val view   = bubbleViews[userId] ?: return@post
            val params = bubbleParams[userId] ?: return@post
            val vW = view.width.takeIf { it > 0 } ?: dp(BUBBLE_SIZE_DP)
            val vH = view.height.takeIf { it > 0 } ?: dp(BUBBLE_SIZE_DP)
            val pad = dp(BUBBLE_PADDING_DP)
            params.x = x.coerceIn(pad, (screenWidth  - vW - pad).coerceAtLeast(pad))
            params.y = y.coerceIn(pad, (screenHeight - vH - pad).coerceAtLeast(pad))
            try { windowManager?.updateViewLayout(view, params) } catch (_: Exception) {}
        }
    }

    private fun updateBubble(userId: String, unreadCount: Int, lastMessage: String) {
        mainHandler.post {
            bubbleViews[userId]?.let {
                it.updateUnreadCount(unreadCount)
                it.updateLastMessage(lastMessage)
                it.animateNewMessage()
            }
        }
    }

    private fun hideBubble(userId: String) {
        mainHandler.post {
            try {
                val view = bubbleViews.remove(userId)
                bubbleParams.remove(userId)
                view?.let {
                    it.cleanup()
                    safeRemoveView(it)
                }
                updateNotification()
                checkAndStopService()
            } catch (_: Exception) {}
        }
    }

    private fun hideAllBubbles() {
        mainHandler.post {
            bubbleViews.values.forEach { view ->
                try { view.cleanup() } catch (_: Exception) {}
                safeRemoveView(view)
            }
            bubbleViews.clear()
            bubbleParams.clear()
            updateNotification()
            checkAndStopService()
        }
    }

    private fun onBubbleClicked(userId: String, userName: String, avatarUrl: String) {
        try {
            bubbleViews[userId]?.visibility = View.GONE
            showMiniChat(userId, userName, avatarUrl)
            BubbleManager.markAsRead(this, userId)
            sendBroadcast(Intent(ACTION_CHAT_BUBBLE_CLICKED).apply {
                putExtra("userId",    userId)
                putExtra("userName",  userName)
                putExtra("avatarUrl", avatarUrl)
            })
        } catch (e: Exception) { loge("onBubbleClicked", e) }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // DELETE ZONE
    // ─────────────────────────────────────────────────────────────────────────

    private fun showDeleteZone() {
        if (deleteZoneView != null) { deleteZoneView?.show(); return }
        try {
            val zone = DeleteZoneView(this)
            val params = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT, dp(160), overlayType(),
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                        WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                PixelFormat.TRANSLUCENT
            ).apply { gravity = Gravity.BOTTOM }
            windowManager?.addView(zone, params)
            deleteZoneView   = zone
            deleteZoneParams = params
            zone.show()
        } catch (e: Exception) { loge("showDeleteZone", e) }
    }

    private fun hideDeleteZone() {
        deleteZoneView?.hide()
    }

    // ─────────────────────────────────────────────────────────────────────────
    // KEYBOARD
    // ─────────────────────────────────────────────────────────────────────────

    private fun showKeyboard(view: View) {
        try {
            (getSystemService(INPUT_METHOD_SERVICE) as? InputMethodManager)
                ?.showSoftInput(view, InputMethodManager.SHOW_IMPLICIT)
        } catch (_: Exception) {}
    }

    private fun hideKeyboard(view: View) {
        try {
            (getSystemService(INPUT_METHOD_SERVICE) as? InputMethodManager)
                ?.hideSoftInputFromWindow(view.windowToken, 0)
        } catch (_: Exception) {}
    }

    // ─────────────────────────────────────────────────────────────────────────
    // NOTIFICATION
    // ─────────────────────────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(CHANNEL_ID, "Chat Bubbles", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Active chat bubbles"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        val bubbleCount = bubbleViews.size
        val text = buildString {
            if (bubbleCount > 0) append("$bubbleCount cuộc trò chuyện")
            if (miniChatVisible) { if (isNotEmpty()) append(" • "); append("Mini chat đang mở") }
            if (isEmpty()) append("Chat Bubble đang chạy")
        }
        val tapIntent = PendingIntent.getActivity(this, 0,
            Intent(this, BubbleActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Chat Bubble")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(tapIntent)
            .build()
    }

    private fun updateNotification() {
        if (!isServiceRunning) return
        try {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(NOTIFICATION_ID, buildNotification())
        } catch (_: Exception) {}
    }

    // ─────────────────────────────────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────────────────────────────────

    @Suppress("DEPRECATION")
    private fun overlayType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE

    private fun safeRemoveView(view: View) {
        try { windowManager?.removeViewImmediate(view) }
        catch (_: Exception) {
            try { windowManager?.removeView(view) } catch (_: Exception) {}
        }
    }

    private fun safeDetachFlutterView(view: FlutterView) {
        try { view.detachFromFlutterEngine() } catch (_: Exception) {}
    }

    private fun checkAndStopService() {
        if (bubbleViews.isEmpty() && !miniChatVisible && isServiceRunning) {
            log("🛑 No active UI — stopping service")
            stopForeground(true)
            stopSelf()
            isServiceRunning = false
        }
    }

    private fun log(msg: String) = android.util.Log.d("BubbleService", msg)
    private fun loge(tag: String, e: Exception) = android.util.Log.e("BubbleService", "❌ $tag: $e")
    private fun loge(msg: String) = android.util.Log.e("BubbleService", "❌ $msg")
}
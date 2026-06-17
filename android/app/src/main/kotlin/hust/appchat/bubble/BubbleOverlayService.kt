// android/app/src/main/kotlin/hust/appchat/bubble/BubbleOverlayService.kt
package hust.appchat.bubble

import android.animation.ValueAnimator
import android.app.*
import android.content.*
import android.content.res.Configuration
import android.graphics.PixelFormat
import android.os.*
import android.util.Log
import android.view.*
import android.view.animation.OvershootInterpolator
import android.view.inputmethod.InputMethodManager
import androidx.core.app.NotificationCompat
import hust.appchat.BubbleActivity
import hust.appchat.FlutterMiniChatActivity
import hust.appchat.R
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

class BubbleOverlayService : Service() {

    companion object {
        private const val TAG = "BubbleService"

        const val ACTION_SHOW_BUBBLE            = "hust.appchat.SHOW_BUBBLE"
        const val ACTION_HIDE_BUBBLE            = "hust.appchat.HIDE_BUBBLE"
        const val ACTION_UPDATE_BUBBLE          = "hust.appchat.UPDATE_BUBBLE"
        const val ACTION_UPDATE_BUBBLE_POSITION = "hust.appchat.UPDATE_BUBBLE_POSITION"
        const val ACTION_SHOW_MINI_CHAT         = "hust.appchat.SHOW_MINI_CHAT"
        const val ACTION_HIDE_MINI_CHAT         = "hust.appchat.HIDE_MINI_CHAT"
        const val ACTION_HIDE_ALL_BUBBLES       = "hust.appchat.HIDE_ALL_BUBBLES"

        const val ACTION_CHAT_BUBBLE_CLICKED    = "CHAT_BUBBLE_CLICKED"
        const val ACTION_CHAT_BUBBLE_MESSAGE    = "CHAT_BUBBLE_MESSAGE"
        const val ACTION_CHAT_BUBBLE_DISMISS    = "CHAT_BUBBLE_DISMISS"

        private const val NOTIF_ID           = 12_345
        private const val NOTIF_CHANNEL      = "chat_bubbles"
        private const val MINI_ENGINE_ID     = "mini_chat_overlay_engine"
        private const val MINI_CHANNEL       = "mini_chat_channel"
        private const val BUBBLE_DP          = 66
        private const val BUBBLE_PAD_DP      = 8
        private const val WARMUP_POLL_MS     = 50L
        private const val WARMUP_TIMEOUT_MS  = 6_000L

        fun buildIntent(context: Context, action: String, block: Intent.() -> Unit = {}): Intent =
            Intent(context, BubbleOverlayService::class.java).apply { this.action = action; block() }
    }

    // ─── Core ─────────────────────────────────────────────────────────────
    private var wm: WindowManager? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // ─── Bubble registry ─────────────────────────────────────────────────
    private val bubbleViews  = mutableMapOf<String, BubbleView>()
    private val bubbleParams = mutableMapOf<String, WindowManager.LayoutParams>()
    private var isDragging   = false

    // ─── Mini-chat ────────────────────────────────────────────────────────
    private var miniView    : FlutterView? = null
    private var miniParams  : WindowManager.LayoutParams? = null
    private var miniEngine  : FlutterEngine? = null
    private var miniChannel : MethodChannel? = null
    private var miniUserId  : String? = null
    private var miniVisible = false
    private var isEngineWarmingUp = false

    // LỖI F FIX: Guard chống double-tap dẫn đến race condition
    private val isMiniChatTransitioning = AtomicBoolean(false)

    // ─── Delete zone ──────────────────────────────────────────────────────
    private var deleteZone      : DeleteZoneView? = null
    private var deleteZoneParams: WindowManager.LayoutParams? = null

    // ─── Screen ───────────────────────────────────────────────────────────
    private var screenW = 0
    private var screenH = 0
    private var dimensionRetryCount = 0

    // ─── Broadcast ────────────────────────────────────────────────────────
    private var receiver: BroadcastReceiver? = null
    private var isServiceRunning = false

    // ═════════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═════════════════════════════════════════════════════════════════════

    override fun onCreate() {
        super.onCreate()
        try {
            wm = getSystemService(WINDOW_SERVICE) as WindowManager
            refreshScreenDimensions()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) createChannel()
            BubbleManager.init(this)
            registerReceiver()
            isServiceRunning = true
            log("✅ onCreate — screen ${screenW}×${screenH}")
        } catch (e: Exception) { loge("onCreate", e) }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    startForeground(NOTIF_ID, buildNotification())
                } catch (e: Exception) {
                    // LỖI N FIX: Android 15 chặn start FGS từ background nếu không có visible overlay
                    loge("startForeground blocked by system", e)
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
            isServiceRunning = true
            intent?.let { dispatch(it) }
        } catch (e: Exception) { loge("onStartCommand", e) }
        return START_STICKY
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        refreshScreenDimensions()
    }

    override fun onDestroy() {
        log("🛑 onDestroy")
        isServiceRunning = false
        unregisterReceiverSafe()
        BubbleManager.cleanup()
        teardownDeleteZone()
        teardownAllBubbles()
        teardownMiniChat()
        super.onDestroy()
    }

    // ═════════════════════════════════════════════════════════════════════
    // BROADCAST RECEIVER
    // ═════════════════════════════════════════════════════════════════════

    private fun registerReceiver() {
        receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) = dispatch(intent)
        }
        val f = IntentFilter().apply {
            listOf(
                ACTION_SHOW_BUBBLE, ACTION_HIDE_BUBBLE, ACTION_UPDATE_BUBBLE,
                ACTION_UPDATE_BUBBLE_POSITION, ACTION_SHOW_MINI_CHAT,
                ACTION_HIDE_MINI_CHAT, ACTION_HIDE_ALL_BUBBLES
            ).forEach { addAction(it) }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, f, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(receiver, f)
        }
    }

    private fun unregisterReceiverSafe() {
        try { receiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        receiver = null
    }

    // ═════════════════════════════════════════════════════════════════════
    // INTENT DISPATCH
    // ═════════════════════════════════════════════════════════════════════

    private fun dispatch(intent: Intent) {
        val uid = intent.getStringExtra("userId")
        when (intent.action) {
            ACTION_SHOW_BUBBLE -> uid?.let {
                showBubble(it,
                    intent.getStringExtra("userName")    ?: "",
                    intent.getStringExtra("avatarUrl")   ?: "",
                    intent.getIntExtra("unreadCount", 0),
                    intent.getStringExtra("lastMessage") ?: "",
                    intent.getIntExtra("positionX", screenW - dp(BUBBLE_DP + BUBBLE_PAD_DP)),
                    intent.getIntExtra("positionY", dp(200))
                )
            }
            ACTION_UPDATE_BUBBLE -> uid?.let {
                updateBubble(it, intent.getIntExtra("unreadCount", 0),
                    intent.getStringExtra("lastMessage") ?: "")
            }
            ACTION_UPDATE_BUBBLE_POSITION -> uid?.let {
                val x = intent.getIntExtra("positionX", -1)
                val y = intent.getIntExtra("positionY", -1)
                if (x >= 0 && y >= 0) moveBubble(it, x, y)
            }
            ACTION_HIDE_BUBBLE     -> uid?.let { hideBubble(it) }
            ACTION_SHOW_MINI_CHAT  -> uid?.let {
                showMiniChat(it, intent.getStringExtra("userName") ?: "",
                    intent.getStringExtra("avatarUrl") ?: "")
            }
            ACTION_HIDE_MINI_CHAT  -> hideMiniChat()
            ACTION_HIDE_ALL_BUBBLES -> hideAllBubbles()
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // BUBBLE MANAGEMENT
    // ═════════════════════════════════════════════════════════════════════

    private fun showBubble(uid: String, name: String, av: String, unread: Int,
                           msg: String, posX: Int, posY: Int) {
        // LỖI H FIX: Samsung One UI 7 + Android 15: Bubble API bị intercept bởi Smart Pop-up.
        // WindowManager overlay vẫn hoạt động bình thường, service này chính là fallback.
        mainHandler.post {
            if (screenW <= 0) { refreshScreenDimensions(); return@post }
            try {
                bubbleViews.remove(uid)?.let { old -> old.cleanup(); safeRemove(old) }
                bubbleParams.remove(uid)

                val view = BubbleView(this, uid, name, av).apply {
                    setUnreadCount(unread)
                    setLastMessage(msg)
                }

                val bSz = dp(BUBBLE_DP)
                val pad = dp(BUBBLE_PAD_DP)
                val maxX = (screenW - bSz - pad).coerceAtLeast(pad)
                val maxY = (screenH - bSz - pad).coerceAtLeast(pad)

                var layoutFlags = WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                        WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED

                if (Build.VERSION.SDK_INT < 35) {
                    layoutFlags = layoutFlags or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                }

                val lp = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    overlayType(),
                    layoutFlags,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.TOP or Gravity.START
                    x = posX.coerceIn(pad, maxX)
                    y = posY.coerceIn(pad, maxY)
                }

                try {
                    wm?.addView(view, lp)
                } catch (e: WindowManager.BadTokenException) {
                    // LỖI K FIX: Bắt BadTokenException nếu quyền SYSTEM_ALERT_WINDOW bị thu hồi ngầm định
                    loge("Quyền SYSTEM_ALERT_WINDOW bị thu hồi ngầm", e)
                    return@post
                }

                bubbleViews[uid]  = view
                bubbleParams[uid] = lp

                mainHandler.postDelayed({ wireInteraction(view, uid, name, av, lp) }, 120L)
                mainHandler.postDelayed({ if (bubbleViews.containsKey(uid)) snapEdge(uid) }, 550L)

                view.scaleX = 0f; view.scaleY = 0f; view.alpha = 0f
                view.animate().scaleX(1f).scaleY(1f).alpha(1f)
                    .setDuration(350).setInterpolator(OvershootInterpolator(2.5f)).start()

                updateNotification()
                log("🫧 Bubble shown: $name")
            } catch (e: Exception) { loge("showBubble", e) }
        }
    }

    private fun wireInteraction(view: BubbleView, uid: String, name: String, av: String, lp: WindowManager.LayoutParams) {
        view.onBubbleClick = { onBubbleClicked(uid, name, av) }
        view.onDragDelta = { inDeleteZone, dx, dy ->
            if (!isDragging && (dx != 0f || dy != 0f)) { isDragging = true; showDeleteZone() }
            if (inDeleteZone) {
                deleteZone?.animateToActive(true)
                view.animateDelete {
                    hideDeleteZone()
                    isDragging = false
                    BubbleManager.removeBubble(this, uid)
                    broadcastEvent(ACTION_CHAT_BUBBLE_DISMISS, uid)
                    checkStop()
                }
            } else {
                deleteZone?.animateToActive(false)
                val vW = view.width.takeIf { it > 0 } ?: dp(BUBBLE_DP)
                val vH = view.height.takeIf { it > 0 } ?: dp(BUBBLE_DP)
                val pad = dp(BUBBLE_PAD_DP)
                lp.x = (lp.x + dx.toInt()).coerceIn(pad, (screenW - vW - pad).coerceAtLeast(pad))
                lp.y = (lp.y + dy.toInt()).coerceIn(pad, (screenH - vH - pad).coerceAtLeast(pad))
                try { wm?.updateViewLayout(view, lp) } catch (_: Exception) {}
            }
        }
        view.onDragEnd = {
            hideDeleteZone()
            isDragging = false
            mainHandler.postDelayed({ if (bubbleViews.containsKey(uid)) snapEdge(uid) }, 80L)
        }
    }

    private fun snapEdge(uid: String) {
        val view = bubbleViews[uid] ?: return
        val lp   = bubbleParams[uid] ?: return
        val vW   = view.width.takeIf { it > 0 } ?: dp(BUBBLE_DP)
        val pad  = dp(BUBBLE_PAD_DP + 4)
        val cx   = lp.x + vW / 2
        val targetX = if (cx < screenW / 2) pad else screenW - vW - pad

        ValueAnimator.ofInt(lp.x, targetX).apply {
            duration     = 340
            interpolator = OvershootInterpolator(1.6f)
            addUpdateListener { a ->
                if (!bubbleViews.containsKey(uid)) { cancel(); return@addUpdateListener }
                lp.x = a.animatedValue as Int
                try { wm?.updateViewLayout(view, lp) } catch (_: Exception) { cancel() }
            }
            start()
        }
    }

    private fun onBubbleClicked(uid: String, name: String, av: String) {
        bubbleViews[uid]?.visibility = View.GONE
        showMiniChat(uid, name, av)
        BubbleManager.markAsRead(this, uid)
        sendBroadcast(Intent(ACTION_CHAT_BUBBLE_CLICKED).apply {
            putExtra("userId",    uid)
            putExtra("userName",  name)
            putExtra("avatarUrl", av)
        })
    }

    private fun updateBubble(uid: String, unread: Int, msg: String) {
        mainHandler.post {
            bubbleViews[uid]?.let {
                try { it.setUnreadCount(unread); it.setLastMessage(msg) }
                catch (e: Exception) { it.updateUnreadCount(unread); it.updateLastMessage(msg) }
                if (unread > 0) it.animateNewMessage()
            }
        }
    }

    private fun moveBubble(uid: String, x: Int, y: Int) {
        mainHandler.post {
            val view = bubbleViews[uid] ?: return@post
            val lp   = bubbleParams[uid] ?: return@post
            val pad  = dp(BUBBLE_PAD_DP)
            lp.x = x.coerceIn(pad, (screenW - (view.width.takeIf { it > 0 } ?: dp(BUBBLE_DP)) - pad).coerceAtLeast(pad))
            lp.y = y.coerceIn(pad, (screenH - (view.height.takeIf { it > 0 } ?: dp(BUBBLE_DP)) - pad).coerceAtLeast(pad))
            try { wm?.updateViewLayout(view, lp) } catch (_: Exception) {}
        }
    }

    private fun hideBubble(uid: String) {
        mainHandler.post {
            bubbleViews.remove(uid)?.let { view ->
                view.animate().alpha(0f).scaleX(0.6f).scaleY(0.6f).setDuration(220)
                    .withEndAction { view.cleanup(); safeRemove(view) }.start()
            }
            bubbleParams.remove(uid)
            updateNotification()
            checkStop()
        }
    }

    private fun hideAllBubbles() {
        mainHandler.post {
            teardownAllBubbles()
            updateNotification()
            checkStop()
        }
    }

    private fun teardownAllBubbles() {
        bubbleViews.values.forEach { v -> try { v.cleanup() } catch (_: Exception) {}; safeRemove(v) }
        bubbleViews.clear(); bubbleParams.clear()
    }

    // ═════════════════════════════════════════════════════════════════════
    // MINI CHAT
    // ═════════════════════════════════════════════════════════════════════

    private fun showMiniChat(uid: String, name: String, av: String) {
        log("💬 showMiniChat uid=$uid")

        // LỖI F FIX: Double-tap race condition guard
        if (!isMiniChatTransitioning.compareAndSet(false, true)) return

        mainHandler.post {
            teardownMiniChat {
                isMiniChatTransitioning.set(false) // Reset cờ sau khi teardown xong
                miniUserId = uid
                ensureEngine { attachMiniChat(uid, name, av) }
            }
        }
    }

    private fun ensureEngine(onReady: () -> Unit) {
        if (isEngineWarmingUp) return

        val cache = FlutterEngineCache.getInstance()
        var eng = cache.get(MINI_ENGINE_ID)

        // LỖI G FIX: Nếu engine đã warm (từ MainActivity), tái sử dụng ngay lập tức
        if (eng != null && eng.dartExecutor.isExecutingDart) {
            miniEngine = eng
            // PHẢI gọi appIsResumed vì engine đang ở trạng thái detached
            eng.lifecycleChannel.appIsResumed()
            onReady()
            return
        }

        if (eng != null && !eng.dartExecutor.isExecutingDart) {
            log("⚠️ Stale mini engine — evicting")
            try { eng.destroy() } catch (_: Exception) {}
            cache.remove(MINI_ENGINE_ID); eng = null
        }

        log("🔧 Creating new mini-chat engine (Fallback)")
        isEngineWarmingUp = true
        val newEng = FlutterEngine(this)
        newEng.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        newEng.lifecycleChannel.appIsResumed()
        cache.put(MINI_ENGINE_ID, newEng)
        miniEngine = newEng

        val t0 = System.currentTimeMillis()
        fun poll() {
            if (!isServiceRunning) {
                isEngineWarmingUp = false
                return
            }
            when {
                newEng.dartExecutor.isExecutingDart -> {
                    log("✅ Mini engine warm")
                    isEngineWarmingUp = false
                    onReady()
                }
                System.currentTimeMillis() - t0 > WARMUP_TIMEOUT_MS -> {
                    loge("Mini engine warmup timeout")
                    isEngineWarmingUp = false
                }
                else -> mainHandler.postDelayed(::poll, WARMUP_POLL_MS)
            }
        }
        mainHandler.postDelayed(::poll, WARMUP_POLL_MS)
    }

    private fun attachMiniChat(uid: String, name: String, av: String) {
        // LỖI E FIX: KHÔNG tạo FlutterView trong Service context gây blank screen.
        // Chuyển sang launch FlutterMiniChatActivity.
        try {
            val intent = FlutterMiniChatActivity.createIntent(this, uid, name, av).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            miniVisible = true
        } catch (e: Exception) {
            loge("attachMiniChat via Activity failed, launching legacy fallback", e)
            attachMiniChatLegacy(uid, name, av)
        }
    }

    // Hàm gắn FlutterView cũ được giữ lại làm Fallback cho thiết bị quá cũ
    private fun attachMiniChatLegacy(uid: String, name: String, av: String) {
        val eng = miniEngine ?: return
        if (!eng.dartExecutor.isExecutingDart) { loge("attachMiniChatLegacy: engine dead"); return }

        try {
            val view = FlutterView(this, FlutterTextureView(this))
            view.attachToFlutterEngine(eng)
            miniView    = view
            miniVisible = true

            miniChannel = MethodChannel(eng.dartExecutor.binaryMessenger, MINI_CHANNEL).also { channel ->
                channel.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "minimize" -> {
                            view.findFocus()?.let { f -> hideKeyboard(f) }
                            hideMiniChat()
                            miniUserId?.let { id -> bubbleViews[id]?.visibility = View.VISIBLE }
                            result.success(true)
                        }
                        "close" -> {
                            view.findFocus()?.let { f -> hideKeyboard(f) }
                            hideMiniChat()
                            miniUserId?.let { id ->
                                BubbleManager.removeBubble(this@BubbleOverlayService, id)
                                broadcastEvent(ACTION_CHAT_BUBBLE_DISMISS, id)
                            }
                            result.success(true)
                        }
                        "sendMessage" -> {
                            val msg = call.argument<String>("message") ?: ""
                            miniUserId?.let { id ->
                                sendBroadcast(Intent(ACTION_CHAT_BUBBLE_MESSAGE).apply {
                                    putExtra("userId", id)
                                    putExtra("message", msg)
                                })
                            }
                            result.success(true)
                        }
                        "updateBubble" -> {
                            val id = call.argument<String>("userId") ?: return@setMethodCallHandler
                            val unread  = call.argument<Int>("unreadCount") ?: 0
                            val lastMsg = call.argument<String>("lastMessage") ?: ""
                            updateBubble(id, unread, lastMsg)
                            result.success(true)
                        }
                        "requestScreenSize" -> {
                            result.success(mapOf("width" to screenW, "height" to screenH))
                        }
                        else -> result.notImplemented()
                    }
                }
            }

            val wPx = (screenW * 0.88).toInt().coerceIn(dp(300), dp(500))
            val hPx = (screenH * 0.72).toInt().coerceIn(dp(400), dp(820))

            miniParams = WindowManager.LayoutParams(
                wPx, hPx, overlayType(),
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                        WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED and
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv(),
                PixelFormat.TRANSLUCENT
            ).apply {
                gravity       = Gravity.CENTER
                softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
            }

            wm?.addView(view, miniParams)
            log("✅ Legacy Mini-chat attached ${wPx}×${hPx}")

            view.scaleX = 0.85f; view.scaleY = 0.85f; view.alpha = 0f
            view.animate().scaleX(1f).scaleY(1f).alpha(1f)
                .setDuration(320).setInterpolator(OvershootInterpolator(1.8f)).start()

            mainHandler.postDelayed({ view.isFocusableInTouchMode = true; view.requestFocus() }, 130L)
            mainHandler.postDelayed({ sendMiniNav(uid, name, av) }, 480L)

        } catch (e: Exception) {
            loge("attachMiniChatLegacy", e); teardownMiniChat()
        }
    }

    private fun sendMiniNav(uid: String, name: String, av: String) {
        try {
            miniChannel?.invokeMethod("navigateToMiniChat", mapOf(
                "peerId"       to uid,
                "peerNickname" to name,
                "peerAvatar"   to av
            ))
        } catch (e: Exception) { loge("sendMiniNav", e) }
    }

    private fun hideMiniChat() {
        mainHandler.post {
            teardownMiniChat {
                miniUserId = null
                checkStop()
                updateNotification()
            }
        }
    }

    private fun teardownMiniChat(onComplete: () -> Unit = {}) {
        val v = miniView
        if (v == null) {
            // Trường hợp chạy MiniChat qua Activity, Service không quản lý view
            miniVisible = false
            onComplete()
            return
        }

        mainHandler.post {
            try {
                miniVisible = false

                v.findFocus()?.let { hideKeyboard(it) }
                v.animate().alpha(0f).scaleX(0.88f).scaleY(0.88f).setDuration(200)
                    .withEndAction {
                        safeDetach(v)
                        safeRemove(v)
                        miniView = null
                        miniParams = null
                        miniChannel?.setMethodCallHandler(null)
                        miniChannel = null
                        onComplete()
                    }.start()
            } catch (e: Exception) {
                loge("teardownMiniChat lỗi", e)
                onComplete()
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // DELETE ZONE
    // ═════════════════════════════════════════════════════════════════════

    private fun showDeleteZone() {
        if (deleteZone != null) { deleteZone?.show(); return }
        try {
            val zone = DeleteZoneView(this)
            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT, dp(160), overlayType(),
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                        WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                        WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
                PixelFormat.TRANSLUCENT
            ).apply { gravity = Gravity.BOTTOM }
            wm?.addView(zone, lp)
            deleteZone = zone; deleteZoneParams = lp
            zone.show()
        } catch (e: Exception) { loge("showDeleteZone", e) }
    }

    private fun hideDeleteZone() { deleteZone?.hide() }

    private fun teardownDeleteZone() {
        deleteZone?.let { safeRemove(it) }
        deleteZone = null; deleteZoneParams = null
    }

    // ═════════════════════════════════════════════════════════════════════
    // HELPERS & UTILS
    // ═════════════════════════════════════════════════════════════════════

    private fun isSamsungDevice() = Build.MANUFACTURER.lowercase() == "samsung"

    private fun isOneUI7OrHigher(): Boolean {
        return try {
            val v = Class.forName("com.samsung.android.feature.SemFloatingFeature")
                .getMethod("getInstance").invoke(null)
            v != null
        } catch (_: Exception) { false }
    }

    private fun broadcastEvent(action: String, uid: String) {
        sendBroadcast(Intent(action).apply { putExtra("userId", uid) })
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(NOTIF_CHANNEL, "Chat Bubbles", NotificationManager.IMPORTANCE_MIN).apply {
                setShowBadge(false); enableLights(false); enableVibration(false)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        val count = bubbleViews.size
        val text = buildString {
            if (count > 0) append("$count cuộc trò chuyện")
            if (miniVisible) { if (isNotEmpty()) append(" · "); append("Mini chat đang mở") }
            if (isEmpty()) append("Chat Bubble đang chạy")
        }
        val pi = PendingIntent.getActivity(this, 0,
            Intent(this, BubbleActivity::class.java).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        return NotificationCompat.Builder(this, NOTIF_CHANNEL)
            .setContentTitle("Chat Bubble")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_notification)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true).setShowWhen(false)
            .setContentIntent(pi).build()
    }

    private fun updateNotification() {
        if (!isServiceRunning) return
        try {
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIF_ID, buildNotification())
        } catch (_: Exception) {}
    }

    private fun refreshScreenDimensions() {
        dimensionRetryCount = 0
        tryGetScreenDimensions()
    }

    private fun tryGetScreenDimensions() {
        try {
            val got = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val b = wm?.currentWindowMetrics?.bounds
                if (b != null && b.width() > 0) { screenW = b.width(); screenH = b.height(); true } else false
            } else {
                val dm = resources.displayMetrics
                if (dm.widthPixels > 0) { screenW = dm.widthPixels; screenH = dm.heightPixels; true } else false
            }
            if (!got) {
                if (dimensionRetryCount++ < 5) {
                    mainHandler.postDelayed({ tryGetScreenDimensions() }, 200L * dimensionRetryCount)
                } else { screenW = 1080; screenH = 2340 }
            }
        } catch (e: Exception) { screenW = 1080; screenH = 2340; loge("screenDimensions", e) }
    }

    private fun checkStop() {
        if (bubbleViews.isEmpty() && !miniVisible && isServiceRunning) {
            log("🛑 No UI — stopping service")
            stopForeground(true); stopSelf(); isServiceRunning = false
        }
    }

    private fun dp(v: Int) = (v * resources.displayMetrics.density).toInt()

    @Suppress("DEPRECATION")
    private fun overlayType() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else WindowManager.LayoutParams.TYPE_PHONE

    private fun safeRemove(v: View) {
        try { wm?.removeViewImmediate(v) }
        catch (_: Exception) { try { wm?.removeView(v) } catch (_: Exception) {} }
    }

    private fun safeDetach(v: FlutterView) {
        try { v.detachFromFlutterEngine() } catch (_: Exception) {}
    }

    private fun hideKeyboard(v: View) {
        try { (getSystemService(INPUT_METHOD_SERVICE) as? InputMethodManager)?.hideSoftInputFromWindow(v.windowToken, 0) }
        catch (_: Exception) {}
    }

    private fun log(m: String)  = Log.d(TAG, m)
    private fun loge(m: String) = Log.e(TAG, "❌ $m")
    private fun loge(tag: String, e: Exception) = Log.e(TAG, "❌ $tag: $e")
}
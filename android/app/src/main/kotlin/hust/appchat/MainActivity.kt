// android/app/src/main/kotlin/hust/appchat/MainActivity.kt
package hust.appchat

import android.app.NotificationManager
import android.content.*
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import hust.appchat.notifications.BubbleNotificationManager
import hust.appchat.notifications.BubbleNotificationService
import hust.appchat.shortcuts.ShortcutHelper

/**
 * MainActivity — complete Flutter ↔ Android bridge.
 * * Đã dọn dẹp toàn bộ tàn dư của luồng WindowManager (Android < 11).
 * Mọi thao tác hiển thị bong bóng chat hiện tại được định tuyến thẳng qua
 * BubbleNotificationService (sử dụng Native Bubble API).
 */
class MainActivity : FlutterActivity() {

    // ── Channel identifiers ───────────────────────────────────────────────
    companion object {
        private const val TAG = "MainActivity"

        // Legacy overlay channels
        private const val CH_LEGACY_METHOD = "chat_bubble_overlay"
        private const val CH_LEGACY_EVENT  = "chat_bubble_events"

        // V2 bubble API channels
        private const val CH_V2_METHOD = "chat_bubbles_v2"
        private const val CH_V2_EVENT  = "chat_bubble_events_v2"

        // Broadcast actions
        private const val ACTION_BUBBLE_CLICK   = "CHAT_BUBBLE_CLICKED"
        private const val ACTION_BUBBLE_MESSAGE = "CHAT_BUBBLE_MESSAGE"
        private const val ACTION_BUBBLE_DISMISS = "CHAT_BUBBLE_DISMISS"

        // ID Engine dùng chung
        const val MINI_ENGINE_ID = "mini_chat_overlay_engine"
    }

    // ── State ─────────────────────────────────────────────────────────────
    private var eventSinkLegacy   : EventChannel.EventSink? = null
    private var eventSinkV2       : EventChannel.EventSink? = null
    private var broadcastReceiver : BroadcastReceiver?      = null
    private var receiversRegistered = false
    private var isFlutterReady      = false

    // ═════════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═════════════════════════════════════════════════════════════════════

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            BubbleNotificationService.init(this)
            Log.d(TAG, "✅ BubbleNotificationService initialized")

            // [SỬA LỖI P0 & P1]: Sử dụng chung thực thể EngineWarmer để nạp trước
            // Cả Bubble Engine (cần truyền đúng ID của BubbleActivity) và Mini Chat Engine
            EngineWarmer.warmUp(this, "bubble_chat_engine") // Thay thế BubbleActivity.warmUpBubbleEngine(this)
            EngineWarmer.warmUp(this, MINI_ENGINE_ID)

            if (ShortcutHelper.isShortcutsSupported()) {
                Log.d(TAG, "✅ Shortcuts supported")
            }

            Log.d(TAG, "✅ Boot complete")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Boot failed: $e")
        }
    }

    override fun configureFlutterEngine(@NonNull engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        Log.d(TAG, "🔧 Configuring Flutter Engine...")

        setupLegacyMethodChannel(engine)
        setupLegacyEventChannel(engine)
        setupV2MethodChannel(engine)
        setupV2EventChannel(engine)

        isFlutterReady = true
        Log.d(TAG, "✅ Flutter engine configured and ready")
    }

    override fun onResume() {
        super.onResume()
        if (!isFlutterReady) return
        BubbleNotificationService.onAppResumed(this)
    }

    override fun onPause() {
        super.onPause()
        BubbleNotificationService.onAppPaused()
    }

    override fun onDestroy() {
        unregisterBubbleReceivers()
        eventSinkLegacy = null
        eventSinkV2     = null
        super.onDestroy()
    }

    // ═════════════════════════════════════════════════════════════════════
    // LEGACY METHOD CHANNEL  (chat_bubble_overlay)
    // ═════════════════════════════════════════════════════════════════════

    private fun setupLegacyMethodChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CH_LEGACY_METHOD)
            .setMethodCallHandler { call, result ->
                Log.d(TAG, "📞 Legacy: ${call.method}")
                try {
                    when (call.method) {
                        // Trả về true luôn do trên Android 11+ với Bubble API không cần quyền overlay
                        "hasPermission" -> result.success(true)
                        "requestPermission" -> result.success(true)

                        "showBubble" -> {
                            val uid   = call.argument<String>("userId")    ?: return@setMethodCallHandler result.success(false)
                            val uname = call.argument<String>("userName")  ?: return@setMethodCallHandler result.success(false)
                            val av    = call.argument<String>("avatarUrl") ?: ""
                            val msg   = call.argument<String>("lastMessage") ?: ""
                            BubbleNotificationService.showBubbleNotification(this, uid, uname, msg, av)
                            result.success(true)
                        }

                        "hideBubble" -> {
                            val uid = call.argument<String>("userId") ?: return@setMethodCallHandler result.success(false)
                            BubbleNotificationService.dismissBubble(this, uid)
                            result.success(true)
                        }

                        "hideAllBubbles" -> {
                            BubbleNotificationService.dismissAllBubbles(this)
                            result.success(true)
                        }

                        // [SỬA LỖI P0]: Lấy Meta từ BubbleNotificationManager để chống lỗi mất tên/ảnh
                        "updateBubble" -> {
                            val uid = call.argument<String>("userId")  ?: return@setMethodCallHandler result.success(false)
                            val msg = call.argument<String>("message") ?: ""
                            val meta = BubbleNotificationManager.getMeta(uid)
                            BubbleNotificationService.updateBubbleNotification(this, uid, meta?.first ?: "", msg, meta?.second ?: "")
                            result.success(true)
                        }

                        // Native Mini Chat đã chết, trả về false để Flutter nhường quyền cho Dart Overlay
                        "showMiniChat" -> result.success(false)
                        "hideMiniChat" -> result.success(false)

                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Legacy method ${call.method}: $e")
                    result.error("ERROR", e.message, null)
                }
            }
    }

    // ═════════════════════════════════════════════════════════════════════
    // LEGACY EVENT CHANNEL  (chat_bubble_events)
    // ═════════════════════════════════════════════════════════════════════

    private fun setupLegacyEventChannel(engine: FlutterEngine) {
        EventChannel(engine.dartExecutor.binaryMessenger, CH_LEGACY_EVENT)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSinkLegacy = sink
                    registerBubbleReceivers()
                    Log.d(TAG, "✅ Legacy event channel listening")
                }
                override fun onCancel(args: Any?) {
                    eventSinkLegacy = null
                    if (eventSinkV2 == null) unregisterBubbleReceivers()
                }
            })
    }

    // ═════════════════════════════════════════════════════════════════════
    // V2 METHOD CHANNEL  (chat_bubbles_v2)
    // ═════════════════════════════════════════════════════════════════════

    private fun setupV2MethodChannel(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CH_V2_METHOD)
            .setMethodCallHandler { call, result ->
                Log.d(TAG, "📞 V2: ${call.method}")
                try {
                    when (call.method) {

                        "checkBubbleApiSupport" -> result.success(true) // Luôn true với minSdk 30

                        // [SỬA LỖI P1]: Hàm báo cáo trạng thái tắt/mở quyền hiển thị bubble toàn hệ thống
                        "checkBubbleChannelEnabled" -> {
                            val nm = getSystemService(NotificationManager::class.java)
                            result.success(nm?.areBubblesAllowed() == true)
                        }

                        "showBubble" -> {
                            val uid   = call.argument<String>("userId")    ?: return@setMethodCallHandler result.success(false)
                            val uname = call.argument<String>("userName")  ?: return@setMethodCallHandler result.success(false)
                            val msg   = call.argument<String>("message")   ?: ""
                            val av    = call.argument<String>("avatarUrl") ?: ""
                            BubbleNotificationService.showBubbleNotification(this, uid, uname, msg, av)
                            result.success(true)
                        }

                        // [SỬA LỖI P0]: Lấy tên và avatar từ nguồn Meta để không bị trắng lịch sử
                        "updateBubble" -> {
                            val uid = call.argument<String>("userId")  ?: return@setMethodCallHandler result.success(false)
                            val msg = call.argument<String>("message") ?: ""
                            val meta = BubbleNotificationManager.getMeta(uid)
                            BubbleNotificationService.updateBubbleNotification(this, uid, meta?.first ?: "", msg, meta?.second ?: "")
                            result.success(true)
                        }

                        "hideBubble" -> {
                            val uid = call.argument<String>("userId") ?: return@setMethodCallHandler result.success(false)
                            BubbleNotificationService.dismissBubble(this, uid)
                            result.success(true)
                        }

                        "hideAllBubbles" -> {
                            BubbleNotificationService.dismissAllBubbles(this)
                            result.success(true)
                        }

                        "sendMessage" -> {
                            val uid   = call.argument<String>("userId")      ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing required arguments", null)
                            val uname = call.argument<String>("userName")    ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing required arguments", null)
                            val msg   = call.argument<String>("message")     ?: return@setMethodCallHandler result.error("INVALID_ARGS", "Missing required arguments", null)
                            val av    = call.argument<String>("avatarUrl")   ?: ""
                            val typeStr = call.argument<String>("messageType") ?: "text"
                            val type = when (typeStr.lowercase()) {
                                "image"    -> BubbleNotificationManager.MessageType.IMAGE
                                "voice"    -> BubbleNotificationManager.MessageType.VOICE
                                "location" -> BubbleNotificationManager.MessageType.LOCATION
                                else       -> BubbleNotificationManager.MessageType.TEXT
                            }
                            BubbleNotificationService.sendMessage(this, uid, uname, msg, av, type)
                            result.success(true)
                        }

                        "getMessageCount" -> {
                            val uid = call.argument<String>("userId") ?: return@setMethodCallHandler result.success(0)
                            result.success(BubbleNotificationManager.getMessageCount(uid))
                        }

                        "getBubbleStats" -> result.success(BubbleNotificationService.getBubbleStats())

                        "clearMessageHistory" -> {
                            val uid = call.argument<String>("userId") ?: return@setMethodCallHandler result.success(false)
                            BubbleNotificationManager.clearHistory(uid)
                            result.success(true)
                        }

                        "logBubbleState" -> {
                            BubbleNotificationService.logBubbleState()
                            result.success(true)
                        }

                        "getShortcutCount" -> result.success(ShortcutHelper.getShortcutCount(this))

                        "verifyShortcut" -> {
                            val uid = call.argument<String>("userId") ?: return@setMethodCallHandler result.success(false)
                            result.success(ShortcutHelper.shortcutExists(this, uid))
                        }

                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ V2 method ${call.method}: $e")
                    result.error("ERROR", e.message, null)
                }
            }
    }

    // ═════════════════════════════════════════════════════════════════════
    // V2 EVENT CHANNEL  (chat_bubble_events_v2)
    // ═════════════════════════════════════════════════════════════════════

    private fun setupV2EventChannel(engine: FlutterEngine) {
        EventChannel(engine.dartExecutor.binaryMessenger, CH_V2_EVENT)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSinkV2 = sink
                    registerBubbleReceivers()
                    Log.d(TAG, "✅ V2 event channel listening")
                }
                override fun onCancel(args: Any?) {
                    eventSinkV2 = null
                    if (eventSinkLegacy == null) unregisterBubbleReceivers()
                }
            })
    }

    // ═════════════════════════════════════════════════════════════════════
    // BROADCAST RECEIVER  (native → Dart events)
    // ═════════════════════════════════════════════════════════════════════

    private fun registerBubbleReceivers() {
        if (receiversRegistered) return
        broadcastReceiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                intent ?: return
                val payload: Map<String, Any?> = when (intent.action) {
                    ACTION_BUBBLE_CLICK -> mapOf(
                        "type"      to "click",
                        "userId"    to (intent.getStringExtra("userId") ?: ""),
                        "userName"  to (intent.getStringExtra("userName") ?: ""),
                        "avatarUrl" to (intent.getStringExtra("avatarUrl") ?: ""),
                        "message"   to (intent.getStringExtra("message") ?: ""),
                    )
                    ACTION_BUBBLE_MESSAGE -> mapOf(
                        "type"    to "message",
                        "userId"  to (intent.getStringExtra("userId") ?: ""),
                        "message" to (intent.getStringExtra("message") ?: ""),
                    )
                    ACTION_BUBBLE_DISMISS -> mapOf(
                        "type"   to "dismiss",
                        "userId" to (intent.getStringExtra("userId") ?: ""),
                    )
                    else -> return
                }
                dispatchEvent(payload)
            }
        }

        val filter = IntentFilter().apply {
            addAction(ACTION_BUBBLE_CLICK)
            addAction(ACTION_BUBBLE_MESSAGE)
            addAction(ACTION_BUBBLE_DISMISS)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(broadcastReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(broadcastReceiver, filter)
            }
            receiversRegistered = true
            Log.d(TAG, "✅ Bubble broadcast receivers registered")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Register receivers: $e")
        }
    }

    private fun unregisterBubbleReceivers() {
        if (!receiversRegistered) return
        try { broadcastReceiver?.let { unregisterReceiver(it) } } catch (_: Exception) {}
        broadcastReceiver   = null
        receiversRegistered = false
    }

    /** Dispatch to whichever Dart event sinks are currently active. */
    private fun dispatchEvent(payload: Map<String, Any?>) {
        runOnUiThread {
            try {
                eventSinkLegacy?.success(payload)
                eventSinkV2?.success(payload)
            } catch (e: Exception) {
                Log.e(TAG, "❌ dispatchEvent: $e")
            }
        }
    }
}

/**
 * [SỬA LỖI P0]: Lớp khởi động chung tập trung hóa tài nguyên Engine
 * Quản lý khởi tạo sớm các Flutter Engine nhằm giải quyết tình trạng giật lag màn hình đen (Cold Start)
 * từ 2-4s khi hiển thị UI Native (Bubble Activity) hoặc Mini Chat.
 */
object EngineWarmer {
    private const val TAG = "EngineWarmer"

    fun warmUp(context: Context, engineId: String) {
        val cache = FlutterEngineCache.getInstance()
        if (cache.get(engineId)?.dartExecutor?.isExecutingDart == true) {
            Log.d(TAG, "♻️ Engine $engineId already warm")
            return
        }

        Log.d(TAG, "🔥 Warming engine $engineId…")
        try {
            val eng = FlutterEngine(context.applicationContext)
            eng.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            // Đưa engine vào trạng thái standby, ngừng render UI cho đến khi Activity kích hoạt thực sự
            eng.lifecycleChannel.appIsDetached()
            cache.put(engineId, eng)
            Log.d(TAG, "✅ Engine $engineId warm and standby")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Engine warmup failed for $engineId: $e")
        }
    }
}
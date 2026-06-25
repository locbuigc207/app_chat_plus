// android/app/src/main/kotlin/hust/appchat/MainActivity.kt
package hust.appchat

import android.app.NotificationManager
import android.content.*
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import androidx.lifecycle.lifecycleScope
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import hust.appchat.notifications.BubbleNotificationManager
import hust.appchat.notifications.BubbleNotificationService
import hust.appchat.shortcuts.ShortcutHelper
import hust.appchat.utils.BubblePermissionChecker
import hust.appchat.utils.OemCompatHelper
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

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
        private const val CHANNEL_MESSAGES = "chat_messages"
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

            // Chạy hoàn toàn trên Main Thread mặc định của lifecycleScope.
            // Sử dụng delay(500) để nhường quyền ưu tiên vẽ UI trước, tránh gây block Main Thread hay ANR.
            lifecycleScope.launch {
                delay(500)
                EngineWarmer.warmUp(applicationContext, "bubble_chat_engine")
                EngineWarmer.warmUp(applicationContext, MINI_ENGINE_ID)
            }

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

        registerBubbleReceivers()

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

        dispatchEvent(mapOf("event" to "app_resumed"))

        // [SỬA LỖI P2]: Thực hiện kiểm tra ngầm (Silent re-check) quyền bong bóng chat
        // Chỉ chạy trên các hệ thống OEM (như Samsung One UI 7) có tiểu sử tự reset quyền sau update
        if (isFlutterReady && OemCompatHelper.needsResumePermissionCheck()) {
            val ok = BubblePermissionChecker.isChannelBubbleEnabled(this)
            if (!ok) dispatchEvent(mapOf("event" to "bubble_permission_lost"))
        }
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
                        "hasPermission" -> {
                            val isAllowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val nm = getSystemService(NotificationManager::class.java)
                                val channel = nm?.getNotificationChannel(CHANNEL_MESSAGES)
                                channel?.canBubble() == true && nm.areNotificationsEnabled()
                            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                getSystemService(NotificationManager::class.java)?.areBubblesAllowed() == true
                            } else {
                                false
                            }
                            result.success(isAllowed)
                        }

                        "requestPermission" -> {
                            try {
                                val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                    putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                Log.e(TAG, "❌ Cannot open notification settings: $e")
                                result.success(false)
                            }
                        }

                        "showBubble" -> {
                            val uid   = call.argument<String>("userId")    ?: return@setMethodCallHandler result.success(false)
                            val uname = call.argument<String>("userName")  ?: return@setMethodCallHandler result.success(false)
                            val av    = call.argument<String>("avatarUrl") ?: ""
                            val msg   = call.argument<String>("lastMessage") ?: ""
                            val isGroup = call.argument<Boolean>("isGroup") ?: false // Đọc thêm isGroup

                            BubbleNotificationService.showBubbleNotification(
                                context = this,
                                userId = uid,
                                userName = uname,
                                message = msg,
                                avatarUrl = av,
                                isGroup = isGroup // Truyền isGroup xuống
                            )
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

                        "updateBubble" -> {
                            val uid = call.argument<String>("userId")  ?: return@setMethodCallHandler result.success(false)
                            val msg = call.argument<String>("message") ?: ""
                            val uname = call.argument<String>("userName") ?: ""
                            val av = call.argument<String>("avatarUrl") ?: ""
                            val isGroup = call.argument<Boolean>("isGroup") ?: false

                            val meta = BubbleNotificationManager.getMeta(uid)
                            val finalName = meta?.userName ?: uname       // Thay .first thành .userName
                            val finalAvatar = meta?.avatarUrl ?: av       // Thay .second thành .avatarUrl
                            val finalIsGroup = meta?.isGroup ?: isGroup   // Đọc cờ isGroup đã lưu

                            BubbleNotificationService.updateBubbleNotification(
                                context = this,
                                userId = uid,
                                userName = finalName,
                                message = msg,
                                avatarUrl = finalAvatar,
                                isGroup = finalIsGroup // Truyền cờ isGroup
                            )
                            result.success(true)
                        }

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
                    Log.d(TAG, "✅ Legacy event channel listening")
                }
                override fun onCancel(args: Any?) {
                    eventSinkLegacy = null
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

                        // ==========================================
                        // OEM & PERMISSION INTEGRATION (TÍCH HỢP MỚI)
                        // ==========================================
                        "getBubblePermissionStatus" -> {
                            result.success(BubblePermissionChecker.check(this).dartName)
                        }

                        "getOemName" -> {
                            result.success(OemCompatHelper.getOemName())
                        }

                        "getBubbleSetupSteps" -> {
                            result.success(OemCompatHelper.getBubbleSetupSteps(this))
                        }

                        "openBubbleSettings" -> {
                            OemCompatHelper.openBubbleSettings(this)
                            result.success(true)
                        }

                        "openBatteryWhitelist" -> {
                            OemCompatHelper.openBatteryWhitelist(this)
                            result.success(true)
                        }

                        "openAutoStartSettings" -> {
                            OemCompatHelper.openAutoStartSettings(this)
                            result.success(true)
                        }

                        // ==========================================
                        // EXISTING BUBBLE METHODS
                        // ==========================================
                        "checkBubbleApiSupport" -> result.success(true)

                        "checkBubbleChannelEnabled" -> {
                            val isAllowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val nm = getSystemService(NotificationManager::class.java)
                                val channel = nm?.getNotificationChannel(CHANNEL_MESSAGES)
                                channel?.canBubble() == true && nm.areNotificationsEnabled()
                            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                getSystemService(NotificationManager::class.java)?.areBubblesAllowed() == true
                            } else {
                                false
                            }
                            result.success(isAllowed)
                        }

                        "checkBubblesEnabled" -> {
                            val isAllowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val nm = getSystemService(NotificationManager::class.java)
                                val channel = nm?.getNotificationChannel(CHANNEL_MESSAGES)
                                channel?.canBubble() == true && nm.areNotificationsEnabled()
                            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                                getSystemService(NotificationManager::class.java)?.areBubblesAllowed() == true
                            } else {
                                false
                            }
                            result.success(isAllowed)
                        }

                        "getActiveBubbles" -> {
                            try {
                                val list = BubbleNotificationService.getActiveBubbleUserIds().map { uid ->
                                    val meta = BubbleNotificationManager.getMeta(uid)
                                    mapOf(
                                        "userId" to uid,
                                        "userName" to (meta?.userName ?: ""),    // Thay .first thành .userName
                                        "avatarUrl" to (meta?.avatarUrl ?: "")  // Thay .second thành .avatarUrl
                                    )
                                }
                                result.success(list)
                            } catch (e: Exception) {
                                Log.e(TAG, "❌ getActiveBubbles: $e")
                                result.success(emptyList<Map<String, String>>())
                            }
                        }

                        "showBubble" -> {
                            val uid   = call.argument<String>("userId")    ?: return@setMethodCallHandler result.success(false)
                            val uname = call.argument<String>("userName")  ?: return@setMethodCallHandler result.success(false)
                            val msg   = call.argument<String>("message")   ?: ""
                            val av    = call.argument<String>("avatarUrl") ?: ""
                            val isGroup = call.argument<Boolean>("isGroup") ?: false // Đọc thêm isGroup

                            BubbleNotificationService.showBubbleNotification(
                                context = this,
                                userId = uid,
                                userName = uname,
                                message = msg,
                                avatarUrl = av,
                                isGroup = isGroup // Truyền isGroup
                            )
                            result.success(true)
                        }

                        "updateBubble" -> {
                            val uid = call.argument<String>("userId")  ?: return@setMethodCallHandler result.success(false)
                            val msg = call.argument<String>("message") ?: ""
                            val uname = call.argument<String>("userName") ?: ""
                            val av = call.argument<String>("avatarUrl") ?: ""
                            val isGroup = call.argument<Boolean>("isGroup") ?: false

                            val meta = BubbleNotificationManager.getMeta(uid)
                            val finalName = meta?.userName ?: uname       // Thay .first thành .userName
                            val finalAvatar = meta?.avatarUrl ?: av       // Thay .second thành .avatarUrl
                            val finalIsGroup = meta?.isGroup ?: isGroup   // Đọc cờ isGroup

                            BubbleNotificationService.updateBubbleNotification(
                                context = this,
                                userId = uid,
                                userName = finalName,
                                message = msg,
                                avatarUrl = finalAvatar,
                                isGroup = finalIsGroup // Truyền cờ isGroup
                            )
                            result.success(true)
                        }

                        "clearUnread" -> {
                            val uid = call.argument<String>("userId") ?: return@setMethodCallHandler result.success(false)
                            if (uid.isNotEmpty()) {
                                BubbleNotificationManager.clearHistory(uid)
                                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                                nm.cancel(BubbleNotificationManager.notifId(uid))
                                result.success(true)
                            } else {
                                result.success(false)
                            }
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
                            val isGroup = call.argument<Boolean>("isGroup") ?: false // Đọc cờ isGroup

                            val type = when (typeStr.lowercase()) {
                                "image"    -> BubbleNotificationManager.MessageType.IMAGE
                                "voice"    -> BubbleNotificationManager.MessageType.VOICE
                                "location" -> BubbleNotificationManager.MessageType.LOCATION
                                else       -> BubbleNotificationManager.MessageType.TEXT
                            }

                            BubbleNotificationService.sendMessage(
                                context = this,
                                userId = uid,
                                userName = uname,
                                message = msg,
                                avatarUrl = av,
                                messageType = type,
                                isGroup = isGroup // Truyền isGroup xuống
                            )
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
                    Log.d(TAG, "✅ V2 event channel listening")
                }
                override fun onCancel(args: Any?) {
                    eventSinkV2 = null
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
 * Lớp khởi động chung tập trung hóa tài nguyên Engine
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

            try {
                val registryClass = Class.forName("io.flutter.plugins.GeneratedPluginRegistrant")
                val registerMethod = registryClass.getDeclaredMethod("registerWith", FlutterEngine::class.java)
                registerMethod.invoke(null, eng)
                Log.d(TAG, "✅ Plugins registered explicitly for $engineId")
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ GeneratedPluginRegistrant setup failed: $e")
            }

            val bundlePath = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            val entrypoint = when (engineId) {
                "bubble_chat_engine" -> DartExecutor.DartEntrypoint(bundlePath, "bubbleMain")
                MainActivity.MINI_ENGINE_ID -> DartExecutor.DartEntrypoint(bundlePath, "miniChatMain")
                else -> DartExecutor.DartEntrypoint.createDefault()
            }

            eng.dartExecutor.executeDartEntrypoint(entrypoint)

            // Đưa engine vào trạng thái standby, ngừng render UI cho đến khi Activity kích hoạt thực sự
            eng.lifecycleChannel.appIsDetached()
            cache.put(engineId, eng)
            Log.d(TAG, "✅ Engine $engineId warm and standby")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Engine warmup failed for $engineId: $e")
        }
    }
}
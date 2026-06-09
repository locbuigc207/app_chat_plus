// android/app/src/main/kotlin/hust/appchat/MainActivity.kt
package hust.appchat

import android.content.*
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import hust.appchat.bubble.BubbleManager
import hust.appchat.bubble.BubbleOverlayService
import hust.appchat.notifications.BubbleNotificationManager
import hust.appchat.notifications.BubbleNotificationService
import hust.appchat.shortcuts.ShortcutHelper

/**
 * MainActivity — complete Flutter ↔ Android bridge.
 *
 * Channels exposed to Dart:
 * Legacy (ChatBubbleService / Android < 11):
 * METHOD  "chat_bubble_overlay"   → hasPermission, requestPermission, showBubble,
 * hideBubble, hideAllBubbles, showMiniChat, hideMiniChat
 * EVENT   "chat_bubble_events"    → click, message, dismiss
 *
 * V2 (BubbleServiceV2 / Android 11+):
 * METHOD  "chat_bubbles_v2"       → checkBubbleApiSupport, showBubble, updateBubble,
 * hideBubble, hideAllBubbles, sendMessage, getMessageCount,
 * getBubbleStats, clearMessageHistory, logBubbleState,
 * getShortcutCount, verifyShortcut
 * EVENT   "chat_bubble_events_v2" → click, message, dismiss
 *
 * Events are broadcast to BOTH sinks so either Dart service can listen.
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

        private const val OVERLAY_REQUEST = 1001
    }

    // ── State ─────────────────────────────────────────────────────────────
    private var eventSinkLegacy   : EventChannel.EventSink? = null
    private var eventSinkV2       : EventChannel.EventSink? = null
    private var pendingPermResult : MethodChannel.Result?   = null
    private var broadcastReceiver : BroadcastReceiver?      = null
    private var receiversRegistered = false
    private var isFlutterReady      = false

    // ═════════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═════════════════════════════════════════════════════════════════════

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            BubbleManager.init(this)
            Log.d(TAG, "✅ BubbleManager initialized")

            BubbleNotificationService.init(this)
            Log.d(TAG, "✅ BubbleNotificationService initialized")

            // FIX #2: Warm up shared Flutter engine sớm trong MainActivity.
            // Khi user nhận notification và bubble mở lần đầu, engine đã sẵn sàng
            // → không có cold-start delay, không risk tạo 2 engine đồng thời.
            // warmUpSharedEngine() là idempotent: gọi nhiều lần không hại gì.
            BubbleActivity.warmUpSharedEngine(this)
            Log.d(TAG, "✅ Shared Flutter engine warm-up initiated")

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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
            BubbleNotificationService.onAppResumed(this)
        else
            BubbleManager.onAppResumed(this)
    }

    override fun onPause() {
        super.onPause()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
            BubbleNotificationService.onAppPaused()
        else
            BubbleManager.onAppPaused()
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

                        "hasPermission" ->
                            result.success(hasOverlayPermission())

                        "requestPermission" ->
                            requestOverlayPermission(result)

                        "showBubble" -> {
                            val uid   = call.argument<String>("userId")    ?: return@setMethodCallHandler result.success(false)
                            val uname = call.argument<String>("userName")  ?: return@setMethodCallHandler result.success(false)
                            val av    = call.argument<String>("avatarUrl") ?: ""
                            val msg   = call.argument<String>("lastMessage") ?: ""
                            showBubbleCompat(uid, uname, av, msg)
                            result.success(true)
                        }

                        "hideBubble" -> {
                            val uid = call.argument<String>("userId") ?: return@setMethodCallHandler result.success(false)
                            hideBubbleCompat(uid)
                            result.success(true)
                        }

                        "hideAllBubbles" -> {
                            hideAllBubblesCompat()
                            result.success(true)
                        }

                        "updateBubble" -> {
                            val uid = call.argument<String>("userId")  ?: return@setMethodCallHandler result.success(false)
                            val msg = call.argument<String>("message") ?: ""
                            updateBubbleCompat(uid, msg)
                            result.success(true)
                        }

                        "showMiniChat" -> {
                            val uid   = call.argument<String>("userId")    ?: return@setMethodCallHandler result.success(false)
                            val uname = call.argument<String>("userName")  ?: ""
                            val av    = call.argument<String>("avatarUrl") ?: ""
                            result.success(startMiniChatService(uid, uname, av))
                        }

                        "hideMiniChat" -> {
                            result.success(stopMiniChatService())
                        }

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

                        "checkBubbleApiSupport" ->
                            result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)

                        "showBubble" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                                result.error("UNSUPPORTED", "Bubble API requires Android 11+", null)
                                return@setMethodCallHandler
                            }
                            val uid   = call.argument<String>("userId")    ?: return@setMethodCallHandler result.success(false)
                            val uname = call.argument<String>("userName")  ?: return@setMethodCallHandler result.success(false)
                            val msg   = call.argument<String>("message")   ?: ""
                            val av    = call.argument<String>("avatarUrl") ?: ""
                            BubbleNotificationService.showBubbleNotification(this, uid, uname, msg, av)
                            result.success(true)
                        }

                        "updateBubble" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) { result.success(false); return@setMethodCallHandler }
                            val uid = call.argument<String>("userId")  ?: return@setMethodCallHandler result.success(false)
                            val msg = call.argument<String>("message") ?: ""
                            BubbleNotificationService.updateBubbleNotification(this, uid, "", msg, "")
                            result.success(true)
                        }

                        "hideBubble" -> {
                            val uid = call.argument<String>("userId") ?: return@setMethodCallHandler result.success(false)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                                BubbleNotificationService.dismissBubble(this, uid)
                            else
                                BubbleManager.removeBubble(this, uid)
                            result.success(true)
                        }

                        "hideAllBubbles" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                                BubbleNotificationService.dismissAllBubbles(this)
                            else
                                BubbleManager.cleanup()
                            result.success(true)
                        }

                        "sendMessage" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) { result.success(false); return@setMethodCallHandler }
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
                            result.success(
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                                    BubbleNotificationManager.getMessageCount(uid)
                                else 0
                            )
                        }

                        "getBubbleStats" ->
                            result.success(BubbleNotificationService.getBubbleStats())

                        "clearMessageHistory" -> {
                            val uid = call.argument<String>("userId") ?: return@setMethodCallHandler result.success(false)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                BubbleNotificationManager.clearHistory(uid)
                                result.success(true)
                            } else result.success(false)
                        }

                        "logBubbleState" -> {
                            BubbleNotificationService.logBubbleState()
                            result.success(true)
                        }

                        "getShortcutCount" ->
                            result.success(ShortcutHelper.getShortcutCount(this))

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

    // ═════════════════════════════════════════════════════════════════════
    // COMPAT HELPERS
    // ═════════════════════════════════════════════════════════════════════

    private fun showBubbleCompat(uid: String, uname: String, av: String, msg: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
            BubbleNotificationService.showBubbleNotification(this, uid, uname, msg, av)
        else
            BubbleManager.showBubble(this, uid, uname, av, msg)
    }

    private fun hideBubbleCompat(uid: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
            BubbleNotificationService.dismissBubble(this, uid)
        else
            BubbleManager.removeBubble(this, uid)
    }

    private fun hideAllBubblesCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
            BubbleNotificationService.dismissAllBubbles(this)
        else {
            stopService(Intent(this, BubbleOverlayService::class.java))
            BubbleManager.cleanup()
        }
    }

    private fun updateBubbleCompat(uid: String, msg: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
            BubbleNotificationService.updateBubbleNotification(this, uid, "", msg, "")
        else
            BubbleManager.showBubble(this, uid, "", "", msg)
    }

    private fun startMiniChatService(uid: String, uname: String, av: String): Boolean {
        return try {
            val intent = Intent(this, BubbleOverlayService::class.java).apply {
                action = BubbleOverlayService.ACTION_SHOW_MINI_CHAT
                putExtra("userId",    uid)
                putExtra("userName",  uname)
                putExtra("avatarUrl", av)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                startForegroundService(intent)
            else
                startService(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ startMiniChatService: $e"); false
        }
    }

    private fun stopMiniChatService(): Boolean {
        return try {
            startService(Intent(this, BubbleOverlayService::class.java).apply {
                action = BubbleOverlayService.ACTION_HIDE_MINI_CHAT
            })
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ stopMiniChatService: $e"); false
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // OVERLAY PERMISSION
    // ═════════════════════════════════════════════════════════════════════

    private fun hasOverlayPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(this)

    private fun requestOverlayPermission(result: MethodChannel.Result) {
        if (hasOverlayPermission()) { result.success(true); return }
        pendingPermResult = result
        try {
            startActivityForResult(
                Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")),
                OVERLAY_REQUEST
            )
        } catch (e: Exception) {
            result.success(false)
            pendingPermResult = null
        }
    }

    override fun onActivityResult(req: Int, res: Int, data: Intent?) {
        super.onActivityResult(req, res, data)
        if (req == OVERLAY_REQUEST) {
            pendingPermResult?.success(hasOverlayPermission())
            pendingPermResult = null
        }
    }
}
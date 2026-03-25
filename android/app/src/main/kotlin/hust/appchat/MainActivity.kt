// android/app/src/main/kotlin/hust/appchat/MainActivity.kt
// THAY ĐỔI: Thêm BubbleActivity.warmUpSharedEngine() trong onCreate()
// để shared engine được warm up sớm, tránh cold start khi bubble mở lần đầu.

package hust.appchat

import android.content.Intent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import hust.appchat.bubble.BubbleManager
import hust.appchat.bubble.BubbleOverlayService
import hust.appchat.notifications.BubbleNotificationService
import hust.appchat.notifications.BubbleNotificationManager
import hust.appchat.shortcuts.ShortcutHelper

class MainActivity : FlutterActivity() {

    private val CHANNEL = "chat_bubble_overlay"
    private val EVENT_CHANNEL = "chat_bubble_events"
    private val CHANNEL_V2 = "chat_bubbles_v2"
    private val EVENT_CHANNEL_V2 = "chat_bubble_events_v2"

    private val OVERLAY_PERMISSION_REQUEST = 1001

    private var bubbleClickReceiver: BroadcastReceiver? = null
    private var bubbleMessageReceiver: BroadcastReceiver? = null
    private var eventSink: EventChannel.EventSink? = null
    private var eventSinkV2: EventChannel.EventSink? = null
    private var pendingPermissionResult: MethodChannel.Result? = null

    private var receiversRegistered = false
    private var isFlutterReady = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            BubbleManager.init(this)
            android.util.Log.d("MainActivity", "✅ BubbleManager initialized")

            BubbleNotificationService.init(this)
            android.util.Log.d("MainActivity", "✅ BubbleNotificationService initialized")

            // FIX #2: Warm up shared Flutter engine sớm trong MainActivity.
            // Khi user nhận notification và bubble mở lần đầu, engine đã sẵn sàng
            // → không có cold-start delay, không risk tạo 2 engine đồng thời.
            // warmUpSharedEngine() là idempotent: gọi nhiều lần không hại gì.
            BubbleActivity.warmUpSharedEngine(this)
            android.util.Log.d("MainActivity", "✅ Shared Flutter engine warm-up initiated")

            if (ShortcutHelper.isShortcutsSupported()) {
                android.util.Log.d("MainActivity", "✅ Shortcuts supported")
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ Initialization failed: $e")
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        android.util.Log.d("MainActivity", "🔧 Configuring Flutter Engine...")

        setupMethodChannel(flutterEngine)
        setupEventChannel(flutterEngine)
        setupMethodChannelV2(flutterEngine)
        setupEventChannelV2(flutterEngine)

        isFlutterReady = true
        android.util.Log.d("MainActivity", "✅ Flutter Engine ready")
    }

    // ========================================
    // V2 METHOD CHANNEL
    // ========================================
    private fun setupMethodChannelV2(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_V2)
            .setMethodCallHandler { call, result ->
                android.util.Log.d("MainActivity", "📞 V2 Method: ${call.method}")
                try {
                    when (call.method) {
                        "checkBubbleApiSupport" -> {
                            result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                        }
                        "showBubble" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                                result.error("UNSUPPORTED", "Bubble API requires Android 11+", null)
                                return@setMethodCallHandler
                            }
                            val userId = call.argument<String>("userId")
                            val userName = call.argument<String>("userName")
                            val message = call.argument<String>("message")
                            val avatarUrl = call.argument<String>("avatarUrl")
                            if (userId != null && userName != null && message != null) {
                                BubbleNotificationService.showBubbleNotification(
                                    context = this, userId = userId,
                                    userName = userName, message = message,
                                    avatarUrl = avatarUrl ?: ""
                                )
                                result.success(true)
                            } else {
                                result.error("INVALID_ARGS", "Missing required arguments", null)
                            }
                        }
                        "updateBubble" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) { result.success(false); return@setMethodCallHandler }
                            val userId = call.argument<String>("userId")
                            val message = call.argument<String>("message")
                            if (userId != null && message != null) {
                                BubbleNotificationService.updateBubbleNotification(this, userId, "", message, "")
                                result.success(true)
                            } else result.success(false)
                        }
                        "hideBubble" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) { result.success(false); return@setMethodCallHandler }
                            val userId = call.argument<String>("userId")
                            if (userId != null) { BubbleNotificationService.dismissBubble(this, userId); result.success(true) }
                            else result.success(false)
                        }
                        "hideAllBubbles" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) BubbleNotificationService.dismissAllBubbles(this)
                            result.success(true)
                        }
                        "getShortcutCount" -> result.success(ShortcutHelper.getShortcutCount(this))
                        "verifyShortcut" -> {
                            val userId = call.argument<String>("userId")
                            result.success(if (userId != null) ShortcutHelper.shortcutExists(this, userId) else false)
                        }
                        "sendMessage" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) { result.success(false); return@setMethodCallHandler }
                            val userId = call.argument<String>("userId")
                            val userName = call.argument<String>("userName")
                            val message = call.argument<String>("message")
                            val avatarUrl = call.argument<String>("avatarUrl")
                            val messageTypeStr = call.argument<String>("messageType") ?: "text"
                            if (userId != null && userName != null && message != null) {
                                val messageType = when (messageTypeStr.lowercase()) {
                                    "image" -> BubbleNotificationManager.MessageType.IMAGE
                                    "voice" -> BubbleNotificationManager.MessageType.VOICE
                                    "location" -> BubbleNotificationManager.MessageType.LOCATION
                                    else -> BubbleNotificationManager.MessageType.TEXT
                                }
                                BubbleNotificationService.sendMessage(this, userId, userName, message, avatarUrl ?: "", messageType)
                                result.success(true)
                            } else result.error("INVALID_ARGS", "Missing required arguments", null)
                        }
                        "getMessageCount" -> {
                            val userId = call.argument<String>("userId")
                            result.success(
                                if (userId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                                    BubbleNotificationManager.getMessageCount(userId)
                                else 0
                            )
                        }
                        "getBubbleStats" -> result.success(BubbleNotificationService.getBubbleStats())
                        "clearMessageHistory" -> {
                            val userId = call.argument<String>("userId")
                            if (userId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                BubbleNotificationManager.clearHistory(userId)
                                result.success(true)
                            } else result.success(false)
                        }
                        "logBubbleState" -> {
                            BubbleNotificationService.logBubbleState()
                            result.success(true)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "❌ V2 Method error: $e")
                    result.error("ERROR", e.message, null)
                }
            }
    }

    private fun setupEventChannelV2(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_V2)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSinkV2 = events
                }
                override fun onCancel(arguments: Any?) { eventSinkV2 = null }
            })
    }

    private fun setupMethodChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "hasPermission" -> result.success(checkOverlayPermission())
                        "requestPermission" -> requestOverlayPermission(result)
                        "showBubble" -> {
                            val userId = call.argument<String>("userId")
                            val userName = call.argument<String>("userName")
                            val avatarUrl = call.argument<String>("avatarUrl")
                            val lastMessage = call.argument<String>("lastMessage")
                            if (userId != null && userName != null) {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                    BubbleNotificationService.showBubbleNotification(this, userId, userName, lastMessage ?: "New message", avatarUrl ?: "")
                                } else {
                                    BubbleManager.showBubble(this, userId, userName, avatarUrl ?: "", lastMessage)
                                }
                                result.success(true)
                            } else result.success(false)
                        }
                        "hideBubble" -> {
                            val userId = call.argument<String>("userId")
                            if (userId != null) {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) BubbleNotificationService.dismissBubble(this, userId)
                                else BubbleManager.removeBubble(this, userId)
                                result.success(true)
                            } else result.success(false)
                        }
                        "hideAllBubbles" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) BubbleNotificationService.dismissAllBubbles(this)
                            else {
                                stopService(Intent(this, BubbleOverlayService::class.java))
                                BubbleManager.cleanup()
                            }
                            result.success(true)
                        }
                        "showMiniChat" -> {
                            val userId = call.argument<String>("userId")
                            val userName = call.argument<String>("userName")
                            val avatarUrl = call.argument<String>("avatarUrl")
                            if (userId != null && userName != null) {
                                val intent = Intent(this, BubbleOverlayService::class.java).apply {
                                    action = BubbleOverlayService.ACTION_SHOW_MINI_CHAT
                                    putExtra("userId", userId)
                                    putExtra("userName", userName)
                                    putExtra("avatarUrl", avatarUrl ?: "")
                                }
                                try {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
                                    else startService(intent)
                                    result.success(true)
                                } catch (e: Exception) { result.success(false) }
                            } else result.success(false)
                        }
                        "hideMiniChat" -> {
                            val intent = Intent(this, BubbleOverlayService::class.java).apply { action = BubbleOverlayService.ACTION_HIDE_MINI_CHAT }
                            try { startService(intent); result.success(true) } catch (e: Exception) { result.success(false) }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "❌ Legacy method error: $e")
                    result.error("ERROR", e.message, null)
                }
            }
    }

    private fun setupEventChannel(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    setupBubbleListeners()
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    unsetupBubbleListeners()
                }
            })
    }

    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(this) else true
    }

    private fun requestOverlayPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            pendingPermissionResult = result
            try {
                startActivityForResult(
                    Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")),
                    OVERLAY_PERMISSION_REQUEST
                )
            } catch (e: Exception) { result.success(false) }
        } else result.success(true)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == OVERLAY_PERMISSION_REQUEST) {
            pendingPermissionResult?.success(checkOverlayPermission())
            pendingPermissionResult = null
        }
    }

    private fun setupBubbleListeners() {
        if (receiversRegistered) return
        if (eventSink == null && eventSinkV2 == null) return

        bubbleClickReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "CHAT_BUBBLE_CLICKED") {
                    val eventData = mapOf(
                        "type" to "click",
                        "userId" to (intent.getStringExtra("userId") ?: ""),
                        "userName" to (intent.getStringExtra("userName") ?: ""),
                        "avatarUrl" to (intent.getStringExtra("avatarUrl") ?: "")
                    )
                    try { eventSink?.success(eventData); eventSinkV2?.success(eventData) } catch (e: Exception) { }
                }
            }
        }

        bubbleMessageReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "CHAT_BUBBLE_MESSAGE") {
                    val eventData = mapOf(
                        "type" to "message",
                        "userId" to (intent.getStringExtra("userId") ?: ""),
                        "message" to (intent.getStringExtra("message") ?: "")
                    )
                    try { eventSink?.success(eventData); eventSinkV2?.success(eventData) } catch (e: Exception) { }
                }
            }
        }

        try {
            val clickFilter = IntentFilter("CHAT_BUBBLE_CLICKED")
            val messageFilter = IntentFilter("CHAT_BUBBLE_MESSAGE")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(bubbleClickReceiver, clickFilter, Context.RECEIVER_NOT_EXPORTED)
                registerReceiver(bubbleMessageReceiver, messageFilter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(bubbleClickReceiver, clickFilter)
                @Suppress("UnspecifiedRegisterReceiverFlag")
                registerReceiver(bubbleMessageReceiver, messageFilter)
            }
            receiversRegistered = true
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ Error registering receivers: $e")
        }
    }

    private fun unsetupBubbleListeners() {
        if (!receiversRegistered) return
        listOf(bubbleClickReceiver, bubbleMessageReceiver).forEach { receiver ->
            receiver?.let { try { unregisterReceiver(it) } catch (e: Exception) { } }
        }
        bubbleClickReceiver = null
        bubbleMessageReceiver = null
        receiversRegistered = false
    }

    override fun onResume() {
        super.onResume()
        if (isFlutterReady) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) BubbleNotificationService.onAppResumed(this)
            else BubbleManager.onAppResumed(this)
        }
    }

    override fun onPause() {
        super.onPause()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) BubbleNotificationService.onAppPaused()
        else BubbleManager.onAppPaused()
    }

    override fun onDestroy() {
        unsetupBubbleListeners()
        eventSink = null
        eventSinkV2 = null
        super.onDestroy()
    }
}
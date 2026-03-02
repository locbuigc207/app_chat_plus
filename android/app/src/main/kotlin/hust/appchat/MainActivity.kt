// android/app/src/main/kotlin/hust/appchat/MainActivity.kt

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
    // ========================================
    // CHANNELS
    // ========================================
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

    // ========================================
    // INITIALIZATION
    // ========================================
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)

        try {
            BubbleManager.init(this)
            android.util.Log.d("MainActivity", "✅ BubbleManager initialized")

            BubbleNotificationService.init(this)
            android.util.Log.d("MainActivity", "✅ BubbleNotificationService initialized")

            if (ShortcutHelper.isShortcutsSupported()) {
                android.util.Log.d("MainActivity", "✅ Shortcuts supported")
                android.util.Log.d("MainActivity", "📊 Shortcut count: ${ShortcutHelper.getShortcutCount(this)}")
            } else {
                android.util.Log.w("MainActivity", "⚠️ Shortcuts not supported")
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ Initialization failed: $e")
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        android.util.Log.d("MainActivity", "🔧 Configuring Flutter Engine...")

        flutterEngine.dartExecutor.executeDartEntrypoint(
            io.flutter.embedding.engine.dart.DartExecutor.DartEntrypoint.createDefault()
        )

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
                            val isSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
                            result.success(isSupported)
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
                                android.util.Log.d("MainActivity", "🎈 Creating Bubble API notification: $userName")

                                BubbleNotificationService.showBubbleNotification(
                                    context = this,
                                    userId = userId,
                                    userName = userName,
                                    message = message,
                                    avatarUrl = avatarUrl ?: ""
                                )

                                result.success(true)
                            } else {
                                result.error("INVALID_ARGS", "Missing required arguments", null)
                            }
                        }

                        "updateBubble" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                                result.success(false)
                                return@setMethodCallHandler
                            }

                            val userId = call.argument<String>("userId")
                            val message = call.argument<String>("message")

                            if (userId != null && message != null) {
                                BubbleNotificationService.updateBubbleNotification(
                                    context = this,
                                    userId = userId,
                                    userName = "",
                                    message = message,
                                    avatarUrl = ""
                                )
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        }

                        "hideBubble" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                                result.success(false)
                                return@setMethodCallHandler
                            }

                            val userId = call.argument<String>("userId")
                            if (userId != null) {
                                BubbleNotificationService.dismissBubble(this, userId)
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        }

                        "hideAllBubbles" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                BubbleNotificationService.dismissAllBubbles(this)
                            }
                            result.success(true)
                        }

                        "getShortcutCount" -> {
                            val count = ShortcutHelper.getShortcutCount(this)
                            result.success(count)
                        }

                        "verifyShortcut" -> {
                            val userId = call.argument<String>("userId")
                            if (userId != null) {
                                val exists = ShortcutHelper.shortcutExists(this, userId)
                                result.success(exists)
                            } else {
                                result.success(false)
                            }
                        }

                        "sendMessage" -> {
                            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                                result.success(false)
                                return@setMethodCallHandler
                            }

                            val userId = call.argument<String>("userId")
                            val userName = call.argument<String>("userName")
                            val message = call.argument<String>("message")
                            val avatarUrl = call.argument<String>("avatarUrl")
                            val messageTypeStr = call.argument<String>("messageType") ?: "text"

                            if (userId != null && userName != null && message != null) {
                                android.util.Log.d("MainActivity", "📤 Sending message: $message")

                                val messageType = when (messageTypeStr.lowercase()) {
                                    "image" -> BubbleNotificationManager.MessageType.IMAGE
                                    "voice" -> BubbleNotificationManager.MessageType.VOICE
                                    "location" -> BubbleNotificationManager.MessageType.LOCATION
                                    else -> BubbleNotificationManager.MessageType.TEXT
                                }

                                BubbleNotificationService.sendMessage(
                                    context = this,
                                    userId = userId,
                                    userName = userName,
                                    message = message,
                                    avatarUrl = avatarUrl ?: "",
                                    messageType = messageType
                                )

                                result.success(true)
                            } else {
                                result.error("INVALID_ARGS", "Missing required arguments", null)
                            }
                        }

                        "getMessageCount" -> {
                            val userId = call.argument<String>("userId")
                            if (userId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val count = BubbleNotificationManager.getMessageCount(userId)
                                android.util.Log.d("MainActivity", "📊 Message count for $userId: $count")
                                result.success(count)
                            } else {
                                result.success(0)
                            }
                        }

                        "getBubbleStats" -> {
                            val stats = BubbleNotificationService.getBubbleStats()
                            android.util.Log.d("MainActivity", "📊 Bubble stats: $stats")
                            result.success(stats)
                        }

                        "clearMessageHistory" -> {
                            val userId = call.argument<String>("userId")
                            if (userId != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                BubbleNotificationManager.clearHistory(userId)
                                android.util.Log.d("MainActivity", "🗑️ Cleared history for: $userId")
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        }

                        "logBubbleState" -> {
                            BubbleNotificationService.logBubbleState()
                            android.util.Log.d("MainActivity", "📊 Logged bubble state")
                            result.success(true)
                        }

                        else -> {
                            android.util.Log.w("MainActivity", "⚠️ Unknown V2 method: ${call.method}")
                            result.notImplemented()
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "❌ V2 Method error: $e")
                    result.error("ERROR", e.message, null)
                }
            }

        android.util.Log.d("MainActivity", "✅ V2 MethodChannel registered")
    }

    // ========================================
    // V2 EVENT CHANNEL
    // ========================================
    private fun setupEventChannelV2(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL_V2)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    android.util.Log.d("MainActivity", "✅ V2 EventChannel listener attached")
                    eventSinkV2 = events
                }

                override fun onCancel(arguments: Any?) {
                    android.util.Log.d("MainActivity", "🛑 V2 EventChannel listener cancelled")
                    eventSinkV2 = null
                }
            })

        android.util.Log.d("MainActivity", "✅ V2 EventChannel registered")
    }

    // ========================================
    // LEGACY METHOD CHANNEL
    // ========================================
    private fun setupMethodChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                android.util.Log.d("MainActivity", "📞 Legacy Method: ${call.method}")

                try {
                    when (call.method) {
                        "hasPermission" -> {
                            val hasPermission = checkOverlayPermission()
                            result.success(hasPermission)
                        }

                        "requestPermission" -> {
                            requestOverlayPermission(result)
                        }

                        "showBubble" -> {
                            val userId = call.argument<String>("userId")
                            val userName = call.argument<String>("userName")
                            val avatarUrl = call.argument<String>("avatarUrl")
                            val lastMessage = call.argument<String>("lastMessage")

                            if (userId != null && userName != null) {
                                android.util.Log.d("MainActivity", "🎈 Legacy showBubble: $userName")

                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                    BubbleNotificationService.showBubbleNotification(
                                        context = this,
                                        userId = userId,
                                        userName = userName,
                                        message = lastMessage ?: "New message",
                                        avatarUrl = avatarUrl ?: ""
                                    )
                                } else {
                                    BubbleManager.showBubble(
                                        this,
                                        userId,
                                        userName,
                                        avatarUrl ?: "",
                                        lastMessage
                                    )
                                }
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        }

                        "hideBubble" -> {
                            val userId = call.argument<String>("userId")
                            if (userId != null) {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                    BubbleNotificationService.dismissBubble(this, userId)
                                } else {
                                    BubbleManager.removeBubble(this, userId)
                                }
                                result.success(true)
                            } else {
                                result.success(false)
                            }
                        }

                        "hideAllBubbles" -> {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                BubbleNotificationService.dismissAllBubbles(this)
                            } else {
                                val intent = Intent(this, BubbleOverlayService::class.java)
                                stopService(intent)
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
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                        startForegroundService(intent)
                                    } else {
                                        startService(intent)
                                    }
                                    result.success(true)
                                } catch (e: Exception) {
                                    android.util.Log.e("MainActivity", "❌ Error: $e")
                                    result.success(false)
                                }
                            } else {
                                result.success(false)
                            }
                        }

                        "hideMiniChat" -> {
                            val intent = Intent(this, BubbleOverlayService::class.java).apply {
                                action = BubbleOverlayService.ACTION_HIDE_MINI_CHAT
                            }
                            try {
                                startService(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.success(false)
                            }
                        }

                        else -> {
                            android.util.Log.w("MainActivity", "⚠️ Unknown legacy method: ${call.method}")
                            result.notImplemented()
                        }
                    }
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "❌ Legacy method error: $e")
                    result.error("ERROR", e.message, null)
                }
            }

        android.util.Log.d("MainActivity", "✅ Legacy MethodChannel registered")
    }

    // ========================================
    // EVENT CHANNEL SETUP
    // ========================================
    private fun setupEventChannel(flutterEngine: FlutterEngine) {
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    android.util.Log.d("MainActivity", "✅ Legacy EventChannel listener attached")
                    eventSink = events
                    setupBubbleListeners()
                }

                override fun onCancel(arguments: Any?) {
                    android.util.Log.d("MainActivity", "🛑 Legacy EventChannel listener cancelled")
                    eventSink = null
                    unsetupBubbleListeners()
                }
            })

        android.util.Log.d("MainActivity", "✅ Legacy EventChannel registered")
    }

    // ========================================
    // PERMISSION HANDLING
    // ========================================
    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun requestOverlayPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                android.util.Log.d("MainActivity", "📱 Requesting overlay permission")
                pendingPermissionResult = result

                try {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:$packageName")
                    )
                    startActivityForResult(intent, OVERLAY_PERMISSION_REQUEST)
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "❌ Error: $e")
                    result.success(false)
                }
            } else {
                result.success(true)
            }
        } else {
            result.success(true)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == OVERLAY_PERMISSION_REQUEST) {
            val hasPermission = checkOverlayPermission()
            android.util.Log.d("MainActivity", "📱 Permission result: $hasPermission")

            pendingPermissionResult?.success(hasPermission)
            pendingPermissionResult = null
        }
    }

    // ========================================
    // BROADCAST RECEIVERS
    // ========================================
    private fun setupBubbleListeners() {
        if (receiversRegistered) {
            android.util.Log.d("MainActivity", "ℹ️ Receivers already registered")
            return
        }

        if (eventSink == null && eventSinkV2 == null) {
            android.util.Log.w("MainActivity", "⚠️ Cannot setup receivers: both sinks are null")
            return
        }

        bubbleClickReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "CHAT_BUBBLE_CLICKED") {
                    val userId = intent.getStringExtra("userId") ?: ""
                    val userName = intent.getStringExtra("userName") ?: ""
                    val avatarUrl = intent.getStringExtra("avatarUrl") ?: ""

                    android.util.Log.d("MainActivity", "🫧 Bubble clicked: $userName")

                    val eventData = mapOf(
                        "type" to "click",
                        "userId" to userId,
                        "userName" to userName,
                        "avatarUrl" to avatarUrl
                    )

                    try {
                        eventSink?.success(eventData)
                        eventSinkV2?.success(eventData)
                        android.util.Log.d("MainActivity", "✅ Event sent to both channels")
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "❌ Failed to send event: $e")
                    }
                }
            }
        }

        bubbleMessageReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == "CHAT_BUBBLE_MESSAGE") {
                    val userId = intent.getStringExtra("userId") ?: ""
                    val message = intent.getStringExtra("message") ?: ""

                    val eventData = mapOf(
                        "type" to "message",
                        "userId" to userId,
                        "message" to message
                    )

                    try {
                        eventSink?.success(eventData)
                        eventSinkV2?.success(eventData)
                    } catch (e: Exception) {
                        android.util.Log.e("MainActivity", "❌ Failed to send message event: $e")
                    }
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
            android.util.Log.d("MainActivity", "✅ Receivers registered")
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "❌ Error registering receivers: $e")
        }
    }

    private fun unsetupBubbleListeners() {
        if (!receiversRegistered) return

        bubbleClickReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "⚠️ Error unregistering click receiver: $e")
            }
        }

        bubbleMessageReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "⚠️ Error unregistering message receiver: $e")
            }
        }

        bubbleClickReceiver = null
        bubbleMessageReceiver = null
        receiversRegistered = false
        android.util.Log.d("MainActivity", "✅ Receivers unregistered")
    }

    // ========================================
    // LIFECYCLE
    // ========================================
    override fun onResume() {
        super.onResume()
        android.util.Log.d("MainActivity", "▶️ App resumed")

        if (isFlutterReady) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                BubbleNotificationService.onAppResumed(this)
            } else {
                BubbleManager.onAppResumed(this)
            }
        }
    }

    override fun onPause() {
        super.onPause()
        android.util.Log.d("MainActivity", "⏸️ App paused")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            BubbleNotificationService.onAppPaused()
        } else {
            BubbleManager.onAppPaused()
        }
    }

    override fun onDestroy() {
        unsetupBubbleListeners()
        eventSink = null
        eventSinkV2 = null
        super.onDestroy()
    }
}
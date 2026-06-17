// android/app/src/main/kotlin/hust/appchat/FlutterMiniChatActivity.kt
package hust.appchat

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Gravity
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.window.OnBackInvokedDispatcher
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterMiniChatActivity — a compact floating Flutter window.
 *
 * This Activity renders inside a small, centred floating window (using
 * [WindowManager.LayoutParams]) rather than occupying the full screen.
 * It uses its own dedicated FlutterEngine (MINI_ENGINE_ID) to avoid any
 * collision with BubbleActivity's shared engine.
 *
 * Window behaviour
 * ─────────────────
 * • Occupies ~88 % screen width × ~70 % screen height, centred.
 * • Rounded corners via a transparent window background + Flutter surface drawing.
 * • [FLAG_NOT_TOUCH_MODAL] allows touches outside to reach the app behind.
 * • [SOFT_INPUT_ADJUST_RESIZE] keeps the keyboard from covering the input.
 *
 * Flutter communication
 * ─────────────────────
 * Channel "mini_chat_channel" / "mini_chat_overlay":
 * Flutter → Native  : minimize, close, sendMessage, requestScreenSize, getUserInfo
 * Native  → Flutter : initMiniChat / navigateToMiniChat
 */
class FlutterMiniChatActivity : FlutterActivity() {

    // ─── Constants ────────────────────────────────────────────────────────
    companion object {
        private const val TAG          = "MiniChatActivity"
        const val MINI_ENGINE_ID       = "mini_chat_overlay_engine"
        private const val CHANNEL      = "mini_chat_channel"

        private const val EXTRA_UID    = "userId"
        private const val EXTRA_NAME   = "userName"
        private const val EXTRA_AVATAR = "avatarUrl"

        private const val WARMUP_POLL_MS    = 50L
        private const val WARMUP_TIMEOUT_MS = 5_000L
        private const val FALLBACK_NAV_MS   = 600L

        fun createIntent(
            ctx: Context, userId: String, userName: String, avatarUrl: String,
        ): Intent = Intent(ctx, FlutterMiniChatActivity::class.java).apply {
            putExtra(EXTRA_UID,    userId)
            putExtra(EXTRA_NAME,   userName)
            putExtra(EXTRA_AVATAR, avatarUrl)

            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
        }
    }

    // ─── State ────────────────────────────────────────────────────────────
    private var channel      : MethodChannel? = null
    private var flutterReady = false
    private var userId       = ""
    private var userName     = ""
    private var avatarUrl    = ""
    private val mainHandler  = Handler(Looper.getMainLooper())

    // ═════════════════════════════════════════════════════════════════════
    // ENGINE
    // ═════════════════════════════════════════════════════════════════════

    override fun provideFlutterEngine(ctx: Context): FlutterEngine? {
        val cache = FlutterEngineCache.getInstance()
        var eng   = cache.get(MINI_ENGINE_ID)

        // Evict dead engine
        if (eng != null && !eng.dartExecutor.isExecutingDart) {
            Log.w(TAG, "⚠️ Stale mini engine — evicting")
            try { eng.destroy() } catch (_: Exception) {}
            cache.remove(MINI_ENGINE_ID)
            eng = null
        }

        if (eng == null) {
            Log.d(TAG, "🔧 Creating mini-chat engine")
            eng = FlutterEngine(ctx.applicationContext)
            eng.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            cache.put(MINI_ENGINE_ID, eng)
        }
        return eng
    }

    // ═════════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═════════════════════════════════════════════════════════════════════

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        userId    = intent.getStringExtra(EXTRA_UID)    ?: ""
        userName  = intent.getStringExtra(EXTRA_NAME)   ?: ""
        avatarUrl = intent.getStringExtra(EXTRA_AVATAR) ?: ""

        if (userId.isEmpty()) {
            Log.e(TAG, "❌ No userId"); finish(); return
        }

        // LỖI O FIX: Đăng ký OnBackInvokedCallback chuẩn Android 16 cho API 33+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT
            ) {
                Log.d(TAG, "🔙 System Back gesture — minimizing mini chat")
                hideKeyboard()
                moveTaskToBack(true)
            }
        }

        applyFloatingWindowStyle()
        Log.d(TAG, "✅ onCreate — $userName")
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        // LỖI C FIX: Đánh thức engine từ standby mode sang active khi Activity attach thành công
        engine.lifecycleChannel.appIsResumed()

        setupChannel(engine)
        scheduleNavigation()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val uid = intent.getStringExtra(EXTRA_UID) ?: return
        if (uid == userId) return // same user — no re-nav

        Log.d(TAG, "🔄 New intent → ${intent.getStringExtra(EXTRA_NAME)}")
        userId    = uid
        userName  = intent.getStringExtra(EXTRA_NAME)   ?: ""
        avatarUrl = intent.getStringExtra(EXTRA_AVATAR) ?: ""

        scheduleNavigation()
    }

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }

    // ═════════════════════════════════════════════════════════════════════
    // WINDOW STYLING
    // ═════════════════════════════════════════════════════════════════════

    private fun applyFloatingWindowStyle() {
        try {
            val dm = resources.displayMetrics
            val w  = (dm.widthPixels  * 0.88).toInt()
            val h  = (dm.heightPixels * 0.70).toInt()

            // LỖI E FIX: XÓA HOÀN TOÀN window.setType() vì gây BadTokenException trên Activity context.
            window.setLayout(w, h)
            window.setGravity(Gravity.CENTER)

            // Set Window transparent cho bo góc từ Flutter Render
            window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(Color.TRANSPARENT))
            window.setFormat(PixelFormat.TRANSLUCENT)

            window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)

            window.addFlags(
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                        WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
            )
            Log.d(TAG, "✅ Floating window ${w}×${h}")
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ applyFloatingWindowStyle: $e")
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // CHANNEL
    // ═════════════════════════════════════════════════════════════════════

    private fun setupChannel(engine: FlutterEngine) {
        // LỖI J FIX: Unregister handler cũ để tránh xung đột Isolate khi tái sử dụng Engine
        channel?.setMethodCallHandler(null)
        channel = null

        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "flutterReady" -> {
                    flutterReady = true
                    sendNavigation()
                    result.success(true)
                }
                "minimize" -> {
                    hideKeyboard()
                    moveTaskToBack(true)
                    result.success(true)
                }
                "close" -> {
                    hideKeyboard()
                    finish()
                    result.success(true)
                }
                "sendMessage" -> {
                    val msg = call.argument<String>("message") ?: ""
                    Log.d(TAG, "💬 User sent: $msg")
                    // Broadcast to MainActivity → Flutter EventSink
                    sendBroadcast(Intent("CHAT_BUBBLE_MESSAGE").apply {
                        putExtra("userId",  userId)
                        putExtra("message", msg)
                    })
                    result.success(true)
                }
                "requestScreenSize" -> {
                    val dm = resources.displayMetrics
                    result.success(mapOf(
                        "width"  to dm.widthPixels,
                        "height" to dm.heightPixels
                    ))
                }
                "getUserInfo" -> {
                    result.success(mapOf(
                        "userId"    to userId,
                        "userName"  to userName,
                        "avatarUrl" to avatarUrl,
                    ))
                }
                else -> result.notImplemented()
            }
        }

        // Fallback navigation if Flutter never calls flutterReady
        mainHandler.postDelayed({
            if (!flutterReady && !isFinishing) {
                Log.d(TAG, "⏰ Navigation fallback")
                flutterReady = true
                sendNavigation()
            }
        }, FALLBACK_NAV_MS)
    }

    // ═════════════════════════════════════════════════════════════════════
    // NAVIGATION
    // ═════════════════════════════════════════════════════════════════════

    private fun scheduleNavigation() {
        val eng = flutterEngine ?: return
        val t0  = System.currentTimeMillis()

        fun poll() {
            if (isFinishing) return
            when {
                eng.dartExecutor.isExecutingDart && flutterReady -> {
                    sendNavigation()
                }
                System.currentTimeMillis() - t0 > WARMUP_TIMEOUT_MS -> {
                    Log.e(TAG, "❌ Navigation timeout")
                }
                else -> {
                    mainHandler.postDelayed(::poll, WARMUP_POLL_MS)
                }
            }
        }
        mainHandler.postDelayed(::poll, WARMUP_POLL_MS)
    }

    private fun sendNavigation() {
        if (isFinishing) return
        try {
            // Gửi cả 2 call để hỗ trợ code Flutter cũ và mới
            channel?.invokeMethod("initMiniChat", mapOf(
                "userId"    to userId,
                "userName"  to userName,
                "avatarUrl" to avatarUrl
            ))

            channel?.invokeMethod("navigateToMiniChat", mapOf(
                "peerId"       to userId,
                "peerNickname" to userName,
                "peerAvatar"   to avatarUrl,
            ))

            Log.d(TAG, "✅ Navigation sent → $userName")

            mainHandler.postDelayed({
                try {
                    window.decorView.requestFocus()
                    (getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
                        ?.toggleSoftInput(InputMethodManager.SHOW_IMPLICIT, 0)
                } catch (_: Exception) {}
            }, 400L)
        } catch (e: Exception) {
            Log.e(TAG, "❌ sendNavigation: $e")
        }
    }

    // ─── Keyboard ─────────────────────────────────────────────────────────

    private fun hideKeyboard() {
        try {
            (getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
                ?.hideSoftInputFromWindow(window.decorView.windowToken, 0)
        } catch (_: Exception) {}
    }
}
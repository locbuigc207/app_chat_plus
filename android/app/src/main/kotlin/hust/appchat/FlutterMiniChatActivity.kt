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
import android.view.View
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.window.OnBackInvokedDispatcher
import androidx.window.layout.WindowMetricsCalculator
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * FlutterMiniChatActivity — a compact floating Flutter window.
 *
 * * [SINGLE OWNER]: Hoàn toàn chịu trách nhiệm về vòng đời của MINI_ENGINE_ID.
 * MainActivity chỉ chịu trách nhiệm nạp trước (warm-up), khi Activity này bị hủy
 * nó sẽ giữ quyền quyết định engine nào sẽ bị evict để tránh memory leak.
 *
 * This Activity renders inside a small, centred floating window rather than
 * occupying the full screen.
 */
class FlutterMiniChatActivity : FlutterActivity() {

    // ─── Constants ────────────────────────────────────────────────────────
    companion object {
        private const val TAG          = "MiniChatActivity"

        // Đồng bộ định danh Mini Engine ID từ MainActivity
        const val MINI_ENGINE_ID       = MainActivity.MINI_ENGINE_ID
        private const val CHANNEL      = "mini_chat_channel"

        private const val EXTRA_UID    = "userId"
        private const val EXTRA_NAME   = "userName"
        private const val EXTRA_AVATAR = "avatarUrl"

        private const val WARMUP_POLL_MS    = 50L
        private const val WARMUP_TIMEOUT_MS = 5_000L
        private const val FALLBACK_NAV_MS   = 600L
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

        // Lọc bỏ Engine chết
        if (eng != null && !eng.dartExecutor.isExecutingDart) {
            Log.w(TAG, "⚠️ Stale mini engine — evicting")
            try { eng.destroy() } catch (_: Exception) {}
            cache.remove(MINI_ENGINE_ID)
            eng = null
        }

        if (eng == null) {
            Log.d(TAG, "🔧 Creating mini-chat engine")
            eng = FlutterEngine(ctx.applicationContext)

            // [SỬA LỖI KIẾN TRÚC]: Gọi đúng entry point 'miniChatMain' thay vì chạy lại hàm main()
            // Giải quyết triệt để vấn đề xung đột khóa tệp tin của Hive gây lỗi trắng màn hình overlay.
            val bundlePath = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            eng.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(bundlePath, "miniChatMain")
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

        // Xử lý System Back gesture chuẩn từ Android 13+
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

    // [SỬA LỖI BỔ SUNG]: Override onBackPressed() để thu nhỏ (minimize) overlay
    // thay vì đóng cứng cửa sổ trên các dòng máy Android cũ hơn (API < 33).
    @Suppress("DEPRECATION")
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        Log.d(TAG, "🔙 Legacy Back button pressed — minimizing mini chat")
        hideKeyboard()
        moveTaskToBack(true)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)

        // Wake up engine từ trạng thái detached của EngineWarmer
        engine.lifecycleChannel.appIsResumed()

        setupChannel(engine)
        scheduleNavigation()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val uid = intent.getStringExtra(EXTRA_UID) ?: return
        if (uid == userId) return

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
            val metrics = WindowMetricsCalculator.getOrCreate().computeCurrentWindowMetrics(this)
            val bounds = metrics.bounds

            val w = (bounds.width() * 0.88).toInt()
            val h = (bounds.height() * 0.70).toInt()

            window.setLayout(w, h)
            window.setGravity(Gravity.CENTER)

            // Khởi tạo window transparent cho các góc bo tròn vẽ từ Flutter
            window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(Color.TRANSPARENT))
            window.setFormat(PixelFormat.TRANSLUCENT)

            window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE)
            window.clearFlags(WindowManager.LayoutParams.FLAG_DIM_BEHIND)

            window.addFlags(
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                        WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED
            )

            window.decorView.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES

            Log.d(TAG, "✅ Floating window ${w}×${h} applied via Jetpack WindowMetrics")
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ applyFloatingWindowStyle: $e")
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // CHANNEL
    // ═════════════════════════════════════════════════════════════════════

    private fun setupChannel(engine: FlutterEngine) {
        // Dọn dẹp handler cũ khi tái sử dụng cache engine
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

                    sendBroadcast(Intent("CHAT_BUBBLE_MESSAGE").apply {
                        putExtra("userId",  userId)
                        putExtra("message", msg)
                    })
                    result.success(true)
                }
                "requestScreenSize" -> {
                    val metrics = WindowMetricsCalculator.getOrCreate().computeCurrentWindowMetrics(this)
                    val bounds = metrics.bounds
                    result.success(mapOf(
                        "width"  to bounds.width(),
                        "height" to bounds.height()
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

        // Kích hoạt navigation fallback nếu Flutter side quên invoke "flutterReady"
        mainHandler.postDelayed({
            if (!flutterReady && !isFinishing) {
                Log.d(TAG, "⏰ Navigation fallback triggered")
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
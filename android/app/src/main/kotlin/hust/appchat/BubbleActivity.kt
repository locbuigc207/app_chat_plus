// android/app/src/main/kotlin/hust/appchat/BubbleActivity.kt
package hust.appchat

import android.content.Context
import android.content.Intent
import android.content.LocusId
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.window.OnBackInvokedDispatcher
import hust.appchat.notifications.BubbleNotificationManager
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class BubbleActivity : FlutterActivity() {

    // ─── Constants ────────────────────────────────────────────────────────
    companion object {
        private const val TAG = "BubbleActivity"

        // Đồng bộ với định danh truyền vào EngineWarmer tại MainActivity
        const val BUBBLE_ENGINE_ID = "bubble_chat_engine"

        private const val CHANNEL           = "bubble_chat_channel"
        private const val EXTRA_UID         = "userId"
        private const val EXTRA_NAME        = "userName"
        private const val EXTRA_AVATAR      = "avatarUrl"

        private const val RETRY_INTERVAL_MS = 60L
        private const val MAX_RETRIES       = 60          // ~3.6 s
        private const val FALLBACK_READY_MS = 2500L
        private const val KEYBOARD_DELAY_MS = 350L
        private const val MAX_NAV_CACHE     = 50

        fun createIntent(
            ctx: Context,
            userId: String,
            userName: String,
            avatarUrl: String
        ): Intent = Intent(ctx, BubbleActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data   = android.net.Uri.parse("bubble://chat/$userId")
            putExtra(EXTRA_UID,    userId)
            putExtra(EXTRA_NAME,   userName)
            putExtra(EXTRA_AVATAR, avatarUrl)
            addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
            addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        }
    }

    // ─── State ────────────────────────────────────────────────────────────
    private var channel        : MethodChannel? = null
    private var isFlutterReady = false

    private var currentUid    : String? = null
    private var currentName   : String? = null
    private var currentAvatar : String? = null

    private var pendingUid    : String? = null
    private var pendingName   : String? = null
    private var pendingAvatar : String? = null

    private val navigatedUsers = LinkedHashSet<String>()
    private val mainHandler    = Handler(Looper.getMainLooper())

    // ─── Lifecycle ────────────────────────────────────────────────────────

    override fun onCreate(savedInstanceState: Bundle?) {
        // ══════════════════════════════════════════════════════════════════
        // [FIX BUG 1 — BẮT BUỘC #1] Root cause: blank screen khi tap bubble
        //
        // Vấn đề gốc: super.onCreate() nội bộ gọi provideFlutterEngine()
        // → configureFlutterEngine() → setPending() → NHƯNG lúc này
        // currentUid = null vì readExtras() chưa chạy (nó nằm SAU super
        // trong code cũ). Kết quả: pendingUid = null, scheduleNav(0)
        // bail ngay tại "val uid = pendingUid ?: return". Khi flutterReady
        // được gửi lên sau đó, scheduleNav() cũng null-bail vì pendingUid
        // chưa bao giờ được cập nhật → navigateToChat không bao giờ được
        // invoke → BubbleEntryPage loading vô tận.
        //
        // Cách sửa: readExtras() PHẢI chạy TRƯỚC super.onCreate() để
        // currentUid đã có giá trị đúng khi configureFlutterEngine() fires.
        // ══════════════════════════════════════════════════════════════════
        if (savedInstanceState == null) readExtras(intent)

        super.onCreate(savedInstanceState)
        // Từ đây trở đi: configureFlutterEngine() đã chạy với currentUid đúng.

        // Xử lý back gesture đúng chuẩn Android 13+ (API 33 / Tiramisu trở lên)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(
                OnBackInvokedDispatcher.PRIORITY_DEFAULT
            ) {
                Log.d(TAG, "🔙 System Back gesture — minimizing bubble")
                // Bubble mode: back = thu nhỏ về icon, không finish()
                moveTaskToBack(true)
            }
        }

        if (!validateUser()) { Log.e(TAG, "❌ Missing user info"); finish(); return }

        // [FIX BUG 1 — belt-and-suspenders]: Gọi lại setPending() sau super
        // để phủ edge case: engine lấy từ cache có thể không trigger lại
        // configureFlutterEngine(), hoặc Flutter engine đã ở trạng thái ready
        // trước khi Activity init xong (ví dụ: EngineWarmer đã warm engine).
        setPending()
        if (isFlutterReady) scheduleNav(0)

        // Gắn LocusId để hệ thống Android join đúng task
        // khi mở lại Bubble từ Bubble Bar / Recents / Overview
        setLocusContext(LocusId(currentUid!!), null)

        Log.d(TAG, "✅ onCreate — user: $currentName ($currentUid)")
    }

    // [Xử lý back cho thiết bị API < 33: Android 11, 12, 12L]
    @Suppress("DEPRECATION")
    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        Log.d(TAG, "🔙 Legacy Back button pressed — minimizing bubble")
        moveTaskToBack(true)
    }

    override fun provideFlutterEngine(ctx: Context): FlutterEngine? {
        val cache = FlutterEngineCache.getInstance()
        var eng   = cache.get(BUBBLE_ENGINE_ID)

        if (eng != null && !eng.dartExecutor.isExecutingDart) {
            Log.w(TAG, "⚠️ Cached engine dead — recreating")
            cache.remove(BUBBLE_ENGINE_ID)
            eng = null
        }

        if (eng == null) {
            Log.d(TAG, "🔧 Creating new bubble engine")
            eng = FlutterEngine(ctx.applicationContext)
            // Dùng entry point bubbleMain riêng để tránh conflict Hive với main isolate
            val bundlePath = FlutterInjector.instance().flutterLoader().findAppBundlePath()
            eng.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(bundlePath, "bubbleMain")
            )
            cache.put(BUBBLE_ENGINE_ID, eng)
        } else {
            Log.d(TAG, "♻️ Reusing bubble engine")
        }
        return eng
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        // Đánh thức engine khi Activity attach vào
        engine.lifecycleChannel.appIsResumed()

        configureWindow()
        setupChannel(engine)
        // Sau FIX BUG 1: readExtras() đã chạy trước super.onCreate(),
        // nên currentUid ở đây đã có giá trị đúng.
        setPending()
        scheduleNav(0)
    }

    // Handle bubble resize / re-embed trên Android 16+ (foldable, split screen)
    override fun onMultiWindowModeChanged(
        isInMultiWindowMode: Boolean,
        newConfig: Configuration
    ) {
        super.onMultiWindowModeChanged(isInMultiWindowMode, newConfig)
        Log.d(TAG, "🪟 Multi-window mode changed: $isInMultiWindowMode")
        if (isFlutterReady) {
            channel?.invokeMethod(
                "onWindowSizeChanged", mapOf(
                    "width"  to newConfig.screenWidthDp,
                    "height" to newConfig.screenHeightDp
                )
            )
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        Log.d(TAG, "📐 Config changed: w=${newConfig.screenWidthDp}dp, h=${newConfig.screenHeightDp}dp")
        if (isFlutterReady) {
            channel?.invokeMethod(
                "onWindowSizeChanged", mapOf(
                    "width"  to newConfig.screenWidthDp,
                    "height" to newConfig.screenHeightDp
                )
            )
        }
    }

    override fun onResume() {
        super.onResume()
        val uid = pendingUid ?: return

        // ══════════════════════════════════════════════════════════════════
        // [FIX BUG 3 — TỐI ƯU] ChatPage reload nhẹ mỗi lần re-open bubble
        //
        // Vấn đề: onResume() gọi doNavigate() mỗi lần bubble được maximize
        // lại từ nền → ChatPage bị reload nhẹ mỗi lần, dù Dart có dedup
        // 2s để xử lý.
        //
        // Cách sửa: Guard !navigatedUsers.contains(uid) — chỉ gọi
        // doNavigate() trong onResume() khi đây là lần đầu tiên navigate
        // cho uid này. Các lần mở lại sau, ChatPage đang hiển thị đúng
        // và không cần reload. Nếu intent mới đến qua onNewIntent(),
        // navigatedUsers.remove(uid) sẽ reset guard để nav lại.
        // ══════════════════════════════════════════════════════════════════
        if (isFlutterReady && !navigatedUsers.contains(uid)) {
            Log.d(TAG, "▶️ onResume — first-time nav: $uid")
            doNavigate(uid, pendingName ?: "", pendingAvatar ?: "")
        }
    }

    override fun onPause() {
        super.onPause()
        hideKeyboard()
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        Log.d(TAG, "🏠 User pressed Home — minimizing bubble")
        // Giữ cho thiết bị cũ / hành vi bấm phím home cứng
        moveTaskToBack(true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val newUid  = intent.getStringExtra(EXTRA_UID)  ?: return
        val newName = intent.getStringExtra(EXTRA_NAME) ?: return

        // Reset guard BUG3 để onResume() / scheduleNav() có thể navigate lại cho user mới
        navigatedUsers.remove(newUid)

        Log.d(TAG, "🔄 New intent → $newName ($newUid)")
        currentUid    = newUid
        currentName   = newName
        currentAvatar = intent.getStringExtra(EXTRA_AVATAR)

        // Cập nhật LocusId khi Bubble nhận intent của user khác
        setLocusContext(LocusId(newUid), null)

        setPending()
        scheduleNav(0)
    }

    override fun onSaveInstanceState(out: Bundle) {
        super.onSaveInstanceState(out)
        out.putString("uid",    currentUid)
        out.putString("name",   currentName)
        out.putString("avatar", currentAvatar)
        out.putStringArrayList("navDone", ArrayList(navigatedUsers))
    }

    override fun onRestoreInstanceState(saved: Bundle) {
        super.onRestoreInstanceState(saved)
        currentUid    = saved.getString("uid")
        currentName   = saved.getString("name")
        currentAvatar = saved.getString("avatar")
        saved.getStringArrayList("navDone")?.let { navigatedUsers.addAll(it) }
        setPending()

        if (isFlutterReady && channel != null) scheduleNav(0)
    }

    override fun onDestroy() {
        // Báo cho Manager biết bubble đã bị đóng hoàn toàn
        BubbleNotificationManager.markCollapsed(currentUid ?: "")

        mainHandler.removeCallbacksAndMessages(null)
        channel?.setMethodCallHandler(null)
        channel        = null
        isFlutterReady = false
        navigatedUsers.clear()
        super.onDestroy()
        Log.d(TAG, "✅ onDestroy — bubble engine kept in cache")
    }

    // ─── Engine setup ─────────────────────────────────────────────────────

    private fun configureWindow() {
        try {
            window.clearFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE)
            window.setSoftInputMode(
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
                        WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE
            )
            window.decorView.requestFocus()
        } catch (e: Exception) { Log.e(TAG, "⚠️ configureWindow: $e") }
    }

    private fun setupChannel(engine: FlutterEngine) {
        // Unregister handler cũ nếu engine được reuse từ cache
        channel?.setMethodCallHandler(null)
        channel = null

        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "flutterReady" -> {
                    Log.d(TAG, "🟢 Flutter ready")
                    isFlutterReady = true

                    // Sau FIX BUG 1: currentUid đúng ở đây → markExpanded nhận uid thật.
                    // Trước khi fix: currentUid = null → markExpanded("") bị ghi sai.
                    BubbleNotificationManager.markExpanded(currentUid ?: "")

                    scheduleNav(0)
                    result.success(true)
                }
                "minimize"      -> { moveTaskToBack(true); result.success(true) }
                "close"         -> { moveTaskToBack(true); result.success(true) }
                "getUserInfo"   -> result.success(
                    mapOf(
                        "userId"    to currentUid,
                        "userName"  to currentName,
                        "avatarUrl" to currentAvatar,
                    )
                )
                "getBubbleMode" -> result.success(true)
                "showKeyboard"  -> {
                    mainHandler.postDelayed({ showKeyboard() }, 150L)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Phát hiện HyperOS 2 để kích hoạt resize linh hoạt phía Dart
        val isHyperOS2 =
            System.getProperty("ro.product.build.version.incremental", "").contains("OS2") ||
                    System.getProperty("ro.build.version.hyperos", "").startsWith("2") ||
                    (System.getProperty("ro.miui.ui.version.name", "").isNotEmpty() &&
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE)

        if (isHyperOS2) {
            mainHandler.postDelayed({
                channel?.invokeMethod("adaptForHyperOS2", mapOf("avoidFixedSize" to true))
            }, 200L)
        }

        // Fallback safety: nếu Flutter không gửi "flutterReady" sau 2500ms
        // (engine bị treo khởi động), tự đánh dấu ready và thử navigate.
        mainHandler.postDelayed({
            if (!isFlutterReady && !isFinishing) {
                Log.d(TAG, "⏰ Flutter ready (fallback timer — 2500ms)")
                isFlutterReady = true
                scheduleNav(0)
            }
        }, FALLBACK_READY_MS)
    }

    // ─── Navigation ───────────────────────────────────────────────────────

    private fun setPending() {
        pendingUid    = currentUid
        pendingName   = currentName
        pendingAvatar = currentAvatar
    }

    private fun scheduleNav(attempt: Int) {
        if (isFinishing) return
        val uid  = pendingUid  ?: return
        val name = pendingName ?: return
        val av   = pendingAvatar ?: ""

        if (navigatedUsers.contains(uid)) {
            // Uid đã trong cache: force-navigate lại để Dart đảm bảo cập nhật UI
            // (phòng trường hợp ChatPage bị trắng sau engine restart / process death)
            Log.d(TAG, "♻️ $uid in cache — forcing nav update")
            doNavigate(uid, name, av)
            return
        }

        if (!isFlutterReady) {
            if (attempt >= MAX_RETRIES) {
                Log.e(TAG, "❌ Nav timeout after $MAX_RETRIES retries (~${MAX_RETRIES * RETRY_INTERVAL_MS}ms)")
                return
            }
            mainHandler.postDelayed({ scheduleNav(attempt + 1) }, RETRY_INTERVAL_MS)
            return
        }

        if (channel == null) return
        doNavigate(uid, name, av)
    }

    private fun doNavigate(uid: String, name: String, av: String) {
        if (isFinishing) return
        try {
            channel?.invokeMethod(
                "navigateToChat", mapOf(
                    "peerId"       to uid,
                    "peerNickname" to name,
                    "peerAvatar"   to av,
                    "isBubbleMode" to true,
                )
            )

            // Duy trì LRU-style cache cho navigatedUsers (giới hạn MAX_NAV_CACHE uid)
            if (navigatedUsers.size >= MAX_NAV_CACHE) {
                navigatedUsers.iterator().next().also { navigatedUsers.remove(it) }
            }
            navigatedUsers.add(uid)
            Log.d(TAG, "✅ Navigated → $name ($uid)")

            mainHandler.postDelayed({ showKeyboard() }, KEYBOARD_DELAY_MS)
        } catch (e: Exception) { Log.e(TAG, "❌ doNavigate: $e") }
    }

    // ─── Keyboard ─────────────────────────────────────────────────────────

    private fun showKeyboard() {
        try {
            window.decorView.requestFocus()
            (getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
                ?.toggleSoftInput(InputMethodManager.SHOW_FORCED, 0)
        } catch (_: Exception) {}
    }

    private fun hideKeyboard() {
        try {
            (getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager)
                ?.hideSoftInputFromWindow(window.decorView.windowToken, 0)
        } catch (_: Exception) {}
    }

    // ─── Helpers ──────────────────────────────────────────────────────────

    private fun readExtras(i: Intent) {
        currentUid    = i.getStringExtra(EXTRA_UID)
        currentName   = i.getStringExtra(EXTRA_NAME)
        currentAvatar = i.getStringExtra(EXTRA_AVATAR)
    }

    private fun validateUser() =
        !currentUid.isNullOrEmpty() && !currentName.isNullOrEmpty()
}
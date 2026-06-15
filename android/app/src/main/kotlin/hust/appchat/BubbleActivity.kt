// android/app/src/main/kotlin/hust/appchat/BubbleActivity.kt
package hust.appchat

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class BubbleActivity : FlutterActivity() {

    // ─── Constants ────────────────────────────────────────────────────────
    companion object {
        private const val TAG = "BubbleActivity"

        // ĐÃ SỬA: Đổi sang Engine dành riêng cho Bubble để tránh xung đột với MainActivity
        const val BUBBLE_ENGINE_ID = "bubble_flutter_engine"

        private const val CHANNEL        = "bubble_chat_channel"
        private const val EXTRA_UID      = "userId"
        private const val EXTRA_NAME     = "userName"
        private const val EXTRA_AVATAR   = "avatarUrl"

        private const val RETRY_INTERVAL_MS    = 60L
        private const val MAX_RETRIES          = 60          // ~3.6 s

        // ĐÃ SỬA: Tăng thời gian chờ Fallback lên 1500ms
        private const val FALLBACK_READY_MS    = 1500L
        private const val KEYBOARD_DELAY_MS    = 350L
        private const val MAX_NAV_CACHE        = 50

        /** Idempotent — safe to call multiple times. */
        fun warmUpBubbleEngine(ctx: Context) {
            val cache = FlutterEngineCache.getInstance()
            cache.get(BUBBLE_ENGINE_ID)
                ?.takeIf { it.dartExecutor.isExecutingDart }
                ?.also { Log.d(TAG, "♻️ Bubble Engine already warm"); return }

            cache.get(BUBBLE_ENGINE_ID)?.let {
                Log.w(TAG, "⚠️ Stale engine — evicting")
                cache.remove(BUBBLE_ENGINE_ID)
            }

            Log.d(TAG, "🔥 Warming bubble engine…")
            val eng = FlutterEngine(ctx.applicationContext)
            eng.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            // Không gọi lifecycleChannel.appIsResumed() ở đây vì Bubble chưa thực sự hiện lên
            cache.put(BUBBLE_ENGINE_ID, eng)
            Log.d(TAG, "✅ Bubble engine warm")
        }

        fun createIntent(
            ctx: Context,
            userId: String,
            userName: String,
            avatarUrl: String
        ): Intent = Intent(ctx, BubbleActivity::class.java).apply {
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
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            Log.w(TAG, "⚠️ Bubble API requires Android 11+"); finish(); return
        }

        // ĐÃ SỬA: Xóa hoàn toàn (this as ComponentActivity) và OnBackPressedCallback
        // Lý do: Android Bubble tự động xử lý back system để thu nhỏ bubble.

        if (savedInstanceState == null) readExtras(intent)
        if (!validateUser()) { Log.e(TAG, "❌ Missing user info"); finish(); return }

        Log.d(TAG, "✅ onCreate — user: $currentName ($currentUid)")
    }

    override fun provideFlutterEngine(ctx: Context): FlutterEngine? {
        val cache = FlutterEngineCache.getInstance()
        var eng = cache.get(BUBBLE_ENGINE_ID)

        if (eng != null && !eng.dartExecutor.isExecutingDart) {
            Log.w(TAG, "⚠️ Cached engine dead — recreating")
            cache.remove(BUBBLE_ENGINE_ID); eng = null
        }

        if (eng == null) {
            Log.d(TAG, "🔧 Creating new bubble engine")
            eng = FlutterEngine(ctx.applicationContext)
            eng.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            cache.put(BUBBLE_ENGINE_ID, eng)
        } else {
            Log.d(TAG, "♻️ Reusing bubble engine")
        }
        return eng
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        configureWindow()
        setupChannel(engine)
        setPending()
        scheduleNav(0)
    }

    override fun onResume() {
        super.onResume()
        val uid = pendingUid ?: return
        if (isFlutterReady && !navigatedUsers.contains(uid)) scheduleNav(0)
    }

    override fun onPause() {
        super.onPause()
        hideKeyboard()
    }

    // ĐÃ SỬA: Thêm bắt sự kiện khi người dùng nhấn nút Home
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        Log.d(TAG, "🏠 User pressed Home — closing bubble view")
        finish() // Thu nhỏ bong bóng về biểu tượng nổi thay vì vứt bỏ task
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val newUid  = intent.getStringExtra(EXTRA_UID)  ?: return
        val newName = intent.getStringExtra(EXTRA_NAME) ?: return

        // ĐÃ SỬA: Xóa return nếu newUid == currentUid. Xóa khỏi danh sách nav để tái kích hoạt sự kiện Navigate
        navigatedUsers.remove(newUid)

        Log.d(TAG, "🔄 New intent → $newName")
        currentUid    = newUid
        currentName   = newName
        currentAvatar = intent.getStringExtra(EXTRA_AVATAR)
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

        // ĐÃ SỬA: Kiểm tra channel an toàn trước khi scheduleNav
        if (isFlutterReady && channel != null) scheduleNav(0)
    }

    override fun onDestroy() {
        mainHandler.removeCallbacksAndMessages(null)
        channel?.setMethodCallHandler(null)
        channel = null
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
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "flutterReady" -> {
                    Log.d(TAG, "🟢 Flutter ready")
                    isFlutterReady = true
                    scheduleNav(0)
                    result.success(true)
                }
                // ĐÃ SỬA: Không dùng moveTaskToBack cho API 35+, dùng finish() để gập bubble
                "minimize"     -> { finish(); result.success(true) }
                "close"        -> { finish(); result.success(true) }
                "getUserInfo"  -> result.success(mapOf(
                    "userId"    to currentUid,
                    "userName"  to currentName,
                    "avatarUrl" to currentAvatar,
                ))
                "getBubbleMode" -> result.success(true)
                "showKeyboard"  -> {
                    mainHandler.postDelayed({ showKeyboard() }, 150L)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Fallback an toàn
        mainHandler.postDelayed({
            if (!isFlutterReady && !isFinishing) {
                Log.d(TAG, "⏰ Flutter ready (fallback)")
                isFlutterReady = true; scheduleNav(0)
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
        val uid   = pendingUid   ?: return
        val name  = pendingName  ?: return
        val av    = pendingAvatar ?: ""

        if (navigatedUsers.contains(uid)) return

        if (!isFlutterReady) {
            if (attempt >= MAX_RETRIES) {
                Log.e(TAG, "❌ Navigation timeout after $MAX_RETRIES retries"); return
            }
            mainHandler.postDelayed({ scheduleNav(attempt + 1) }, RETRY_INTERVAL_MS)
            return
        }

        // ĐÃ SỬA: Xác nhận lại channel không rỗng để tránh Null Pointer exception ngầm
        if (channel == null) return
        doNavigate(uid, name, av)
    }

    private fun doNavigate(uid: String, name: String, av: String) {
        if (isFinishing) return
        try {
            channel?.invokeMethod("navigateToChat", mapOf(
                "peerId"       to uid,
                "peerNickname" to name,
                "peerAvatar"   to av,
                "isBubbleMode" to true,
            ))

            if (navigatedUsers.size >= MAX_NAV_CACHE) {
                navigatedUsers.iterator().next().also { navigatedUsers.remove(it) }
            }
            navigatedUsers.add(uid)
            Log.d(TAG, "✅ Navigated → $name")

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

    // ─── Helpers ─────────────────────────────────────────────────────────

    private fun readExtras(i: Intent) {
        currentUid    = i.getStringExtra(EXTRA_UID)
        currentName   = i.getStringExtra(EXTRA_NAME)
        currentAvatar = i.getStringExtra(EXTRA_AVATAR)
    }

    private fun validateUser() =
        !currentUid.isNullOrEmpty() && !currentName.isNullOrEmpty()
}
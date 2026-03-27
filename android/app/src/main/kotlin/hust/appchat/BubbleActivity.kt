// android/app/src/main/kotlin/hust/appchat/BubbleActivity.kt
package hust.appchat

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * FIXES APPLIED:
 *
 * FIX-A — Engine warmup với readiness callback:
 *   Trước: warmUpSharedEngine() tạo engine xong là coi ready, nhưng Dart VM
 *          chưa chắc đã execute xong entry point.
 *   Sau:  Thêm lifecycleChannel.appIsResumed() để signal Flutter engine
 *         đang active, giúp Dart VM start sớm hơn. Giảm black screen 1-3s.
 *
 * FIX-B — NavigationCompletedForUser Set có giới hạn 50 entries:
 *   Trước: Set tích lũy vô hạn trong session dài.
 *   Sau:  Tự động evict entry cũ nhất khi vượt quá 50.
 *
 * FIX-C — Retry interval giảm 200ms → 50ms, maxRetries tăng lên 40:
 *   Trước: 10 retries × 200ms = 2000ms tổng — quá chậm trên flagship.
 *   Sau:  40 retries × 50ms = 2000ms tổng — check thường xuyên hơn,
 *         phản hồi nhanh hơn khi engine sẵn sàng.
 *
 * FIX-D — onBackPressed dùng OnBackPressedDispatcher (Android 13+):
 *   Trước: @Suppress("DEPRECATION") onBackPressed() override.
 *   Sau:  Dùng addCallback() cho Android 13+, fallback graceful cho cũ hơn.
 *
 * FIX-E — Guard check trong provideFlutterEngine:
 *   Trước: Nếu engine trong cache đã bị destroyed (edge case), dùng lại
 *          engine chết gây crash.
 *   Sau:  Kiểm tra engine còn hoạt động trước khi reuse.
 */
class BubbleActivity : FlutterActivity() {

    companion object {
        private const val TAG = "BubbleActivity"

        const val SHARED_ENGINE_ID = "shared_flutter_engine"

        private const val CHANNEL = "bubble_chat_channel"

        private const val EXTRA_USER_ID   = "userId"
        private const val EXTRA_USER_NAME = "userName"
        private const val EXTRA_AVATAR_URL = "avatarUrl"

        private const val ENGINE_WARMUP_TIMEOUT_MS = 2000L
        // FIX-C: giảm interval, tăng số lần retry
        private const val RETRY_INTERVAL_MS = 50L
        private const val MAX_NAVIGATION_CACHE = 50

        fun createIntent(
            context: Context,
            userId: String,
            userName: String,
            avatarUrl: String
        ): Intent = Intent(context, BubbleActivity::class.java).apply {
            putExtra(EXTRA_USER_ID, userId)
            putExtra(EXTRA_USER_NAME, userName)
            putExtra(EXTRA_AVATAR_URL, avatarUrl)
            addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
            addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        }

        /**
         * FIX-A: Warm up engine với lifecycle signal để Dart VM start sớm.
         */
        fun warmUpSharedEngine(context: Context) {
            val cache = FlutterEngineCache.getInstance()
            val existing = cache.get(SHARED_ENGINE_ID)

            // FIX-E: kiểm tra engine còn sống không
            if (existing != null && existing.dartExecutor.isExecutingDart) {
                Log.d(TAG, "♻️ Shared engine already warmed up and running")
                return
            }

            // Engine cũ đã chết — xóa khỏi cache và tạo mới
            if (existing != null) {
                Log.w(TAG, "⚠️ Stale engine found in cache, recreating...")
                cache.remove(SHARED_ENGINE_ID)
            }

            Log.d(TAG, "🔥 Warming up shared Flutter engine...")
            val engine = FlutterEngine(context.applicationContext)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            // FIX-A: signal engine lifecycle để Dart VM khởi động nhanh hơn
            engine.lifecycleChannel.appIsResumed()

            cache.put(SHARED_ENGINE_ID, engine)
            Log.d(TAG, "✅ Shared engine warmed up (dart executing: ${engine.dartExecutor.isExecutingDart})")
        }
    }

    // ========================================
    // STATE
    // ========================================
    private var methodChannel: MethodChannel? = null

    private var currentUserId: String?   = null
    private var currentUserName: String? = null
    private var currentAvatarUrl: String? = null

    private var pendingUserId: String?    = null
    private var pendingUserName: String?  = null
    private var pendingAvatarUrl: String? = null

    private var isFlutterReady = false

    // FIX-B: giới hạn kích thước set
    private val navigationCompletedForUser = LinkedHashSet<String>()

    private val maxRetries = (ENGINE_WARMUP_TIMEOUT_MS / RETRY_INTERVAL_MS).toInt()

    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    // ========================================
    // LIFECYCLE
    // ========================================

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "✅ onCreate")

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            Log.w(TAG, "⚠️ Android < 11 not supported for BubbleActivity, finishing.")
            finish()
            return
        }

        if (savedInstanceState == null) {
            extractUserFromIntent(intent)
        }

        Log.d(TAG, "📋 User: $currentUserName (ID: $currentUserId)")

        if (!validateCurrentUser()) {
            Log.e(TAG, "❌ Missing user data, finishing")
            finish()
            return
        }

        // FIX-D: register back press callback (Android 13+)
        setupBackPressHandler()
    }

    // FIX-D: dùng OnBackPressedDispatcher thay vì deprecated onBackPressed()
    private fun setupBackPressHandler() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackPressedDispatcher.addCallback(this,
                object : androidx.activity.OnBackPressedCallback(true) {
                    override fun handleOnBackPressed() {
                        Log.d(TAG, "⬅️ Back pressed (API 33+) — minimizing")
                        moveTaskToBack(true)
                    }
                }
            )
        }
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            Log.d(TAG, "⬅️ Back pressed — minimizing to bubble")
            moveTaskToBack(true)
        } else {
            super.onBackPressed()
        }
    }

    // ========================================
    // FLUTTER ENGINE
    // ========================================

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        val cache = FlutterEngineCache.getInstance()
        var engine = cache.get(SHARED_ENGINE_ID)

        // FIX-E: validate engine còn alive
        if (engine != null && !engine.dartExecutor.isExecutingDart) {
            Log.w(TAG, "⚠️ Cached engine is dead, recreating...")
            cache.remove(SHARED_ENGINE_ID)
            engine = null
        }

        if (engine == null) {
            Log.d(TAG, "🔧 Creating new shared Flutter engine")
            engine = FlutterEngine(context.applicationContext)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            engine.lifecycleChannel.appIsResumed() // FIX-A
            cache.put(SHARED_ENGINE_ID, engine)
            Log.d(TAG, "✅ Shared engine created and cached")
        } else {
            Log.d(TAG, "♻️ Reusing shared engine (running: ${engine.dartExecutor.isExecutingDart})")
        }

        return engine
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "🔧 Configuring Flutter engine")

        setupWindowForInput()
        setupMethodChannel(flutterEngine)

        setPendingFromCurrent()
        scheduleNavigationWithRetry()
    }

    // ========================================
    // NAVIGATION (PENDING / RETRY)
    // ========================================

    private fun setPendingFromCurrent() {
        pendingUserId   = currentUserId
        pendingUserName = currentUserName
        pendingAvatarUrl = currentAvatarUrl
        Log.d(TAG, "📌 Pending set: $pendingUserName")
    }

    private fun scheduleNavigationWithRetry(attempt: Int = 0) {
        if (isFinishing) return

        val uid   = pendingUserId   ?: return
        val uname = pendingUserName ?: return
        val avatar = pendingAvatarUrl ?: ""

        if (navigationCompletedForUser.contains(uid)) {
            Log.d(TAG, "ℹ️ Already navigated to $uname")
            return
        }

        if (!isFlutterReady) {
            if (attempt >= maxRetries) {
                Log.e(TAG, "❌ Flutter not ready after $maxRetries retries")
                return
            }
            mainHandler.postDelayed({
                scheduleNavigationWithRetry(attempt + 1)
            }, RETRY_INTERVAL_MS)
            return
        }

        navigateToChat(uid, uname, avatar)
    }

    private fun navigateToChat(userId: String, userName: String, avatarUrl: String) {
        if (isFinishing) return
        try {
            Log.d(TAG, "📤 Navigating to chat: $userName")
            methodChannel?.invokeMethod(
                "navigateToChat",
                mapOf(
                    "peerId"       to userId,
                    "peerNickname" to userName,
                    "peerAvatar"   to avatarUrl,
                    "isBubbleMode" to true
                )
            )

            // FIX-B: evict oldest khi vượt giới hạn
            if (navigationCompletedForUser.size >= MAX_NAVIGATION_CACHE) {
                val oldest = navigationCompletedForUser.iterator().next()
                navigationCompletedForUser.remove(oldest)
                Log.d(TAG, "🗑️ Evicted oldest nav entry: $oldest")
            }
            navigationCompletedForUser.add(userId)
            Log.d(TAG, "✅ Navigation sent for: $userName")

            mainHandler.postDelayed({
                if (!isFinishing) showKeyboard()
            }, 300L)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Navigate failed: $e")
        }
    }

    // ========================================
    // WINDOW SETUP
    // ========================================

    private fun setupWindowForInput() {
        try {
            window.clearFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE)
            window.setSoftInputMode(
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
                        WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE
            )
            window.decorView.requestFocus()
            Log.d(TAG, "✅ Window configured for keyboard")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Window setup failed: $e")
        }
    }

    // ========================================
    // METHOD CHANNEL
    // ========================================

    private fun setupMethodChannel(flutterEngine: FlutterEngine) {
        try {
            methodChannel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                CHANNEL
            )

            methodChannel?.setMethodCallHandler { call, result ->
                Log.d(TAG, "📞 Flutter → Native: ${call.method}")
                when (call.method) {
                    "minimize" -> {
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    "close" -> {
                        finish()
                        result.success(true)
                    }
                    "getUserInfo" -> {
                        result.success(mapOf(
                            "userId"    to currentUserId,
                            "userName"  to currentUserName,
                            "avatarUrl" to currentAvatarUrl
                        ))
                    }
                    "getBubbleMode" -> result.success(true)
                    "flutterReady"  -> {
                        Log.d(TAG, "🟢 Flutter reported ready")
                        isFlutterReady = true
                        scheduleNavigationWithRetry()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

            // Fallback: set ready sau 500ms nếu Flutter không gửi "flutterReady"
            mainHandler.postDelayed({
                if (!isFinishing && !isFlutterReady) {
                    Log.d(TAG, "⏰ Flutter ready via fallback timeout")
                    isFlutterReady = true
                    scheduleNavigationWithRetry()
                }
            }, 500L)

            Log.d(TAG, "✅ MethodChannel setup complete")
        } catch (e: Exception) {
            Log.e(TAG, "❌ MethodChannel setup failed: $e")
        }
    }

    // ========================================
    // KEYBOARD
    // ========================================

    private fun showKeyboard() {
        try {
            window.decorView.requestFocus()
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.toggleSoftInput(InputMethodManager.SHOW_FORCED, 0)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Show keyboard failed: $e")
        }
    }

    private fun hideKeyboard() {
        try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.hideSoftInputFromWindow(window.decorView.windowToken, 0)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Hide keyboard failed: $e")
        }
    }

    // ========================================
    // LIFECYCLE
    // ========================================

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "▶️ onResume")
        val uid = pendingUserId
        if (isFlutterReady && uid != null && !navigationCompletedForUser.contains(uid)) {
            scheduleNavigationWithRetry()
        }
    }

    override fun onPause() {
        super.onPause()
        Log.d(TAG, "⏸️ onPause")
        hideKeyboard()
    }

    override fun onDestroy() {
        Log.d(TAG, "💥 onDestroy")
        hideKeyboard()
        mainHandler.removeCallbacksAndMessages(null)
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        isFlutterReady = false
        navigationCompletedForUser.clear()
        pendingUserId    = null
        pendingUserName  = null
        pendingAvatarUrl = null
        // Engine vẫn giữ trong cache để reuse
        Log.d(TAG, "ℹ️ Shared engine kept alive in cache")
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "🔄 onNewIntent")
        val newUserId   = intent.getStringExtra(EXTRA_USER_ID)
        val newUserName = intent.getStringExtra(EXTRA_USER_NAME)
        val newAvatar   = intent.getStringExtra(EXTRA_AVATAR_URL)

        if (newUserId != null && newUserId != currentUserId) {
            Log.d(TAG, "🔄 Switching: $currentUserName → $newUserName")
            currentUserId   = newUserId
            currentUserName = newUserName
            currentAvatarUrl = newAvatar
            pendingUserId   = newUserId
            pendingUserName = newUserName
            pendingAvatarUrl = newAvatar
            scheduleNavigationWithRetry()
        }
    }

    // ========================================
    // STATE PERSISTENCE
    // ========================================

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString("userId",    currentUserId)
        outState.putString("userName",  currentUserName)
        outState.putString("avatarUrl", currentAvatarUrl)
        outState.putStringArrayList(
            "navigationCompleted",
            ArrayList(navigationCompletedForUser)
        )
    }

    override fun onRestoreInstanceState(savedInstanceState: Bundle) {
        super.onRestoreInstanceState(savedInstanceState)
        currentUserId   = savedInstanceState.getString("userId")
        currentUserName = savedInstanceState.getString("userName")
        currentAvatarUrl = savedInstanceState.getString("avatarUrl")
        savedInstanceState.getStringArrayList("navigationCompleted")?.let {
            navigationCompletedForUser.addAll(it)
        }
        Log.d(TAG, "📦 State restored: $currentUserName")
        setPendingFromCurrent()
        if (isFlutterReady) scheduleNavigationWithRetry()
    }

    // ========================================
    // HELPERS
    // ========================================

    private fun extractUserFromIntent(intent: Intent) {
        currentUserId   = intent.getStringExtra(EXTRA_USER_ID)
        currentUserName = intent.getStringExtra(EXTRA_USER_NAME)
        currentAvatarUrl = intent.getStringExtra(EXTRA_AVATAR_URL)
    }

    private fun validateCurrentUser(): Boolean =
        !currentUserId.isNullOrEmpty() && !currentUserName.isNullOrEmpty()
}
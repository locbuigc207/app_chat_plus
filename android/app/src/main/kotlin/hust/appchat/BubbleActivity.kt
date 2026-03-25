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
 * FIX #1 — navigationAttempted race condition:
 *   Trước: reset flag ngay khi onNewIntent, nhưng isFlutterReady có thể false
 *         → sendInitialDataToFlutter() bị skip và không retry.
 *   Sau:  dùng pendingUserId/Name/Avatar để lưu yêu cầu navigate mới nhất.
 *         Khi Flutter ready, luôn dùng pending values thay vì current values.
 *         navigationAttempted chỉ block duplicate cho CÙNG user, không block
 *         khi user thay đổi.
 *
 * FIX #2 — Engine ID conflict (BubbleActivity vs BubbleOverlayService):
 *   Trước: BubbleActivity dùng ENGINE_ID = "bubble_chat_engine"
 *          BubbleOverlayService dùng "mini_chat_engine"
 *          → 2 engine có thể active đồng thời, OOM trên thiết bị ít RAM.
 *   Sau:  Dùng ENGINE_ID chung = "shared_flutter_engine" — một engine duy nhất
 *         cho toàn app. BubbleOverlayService sẽ reuse cùng engine này.
 *         Engine được warm-up một lần, tái sử dụng nhiều lần.
 *
 * FIX #4 — @RequiresApi(R) không có fallback:
 *   Trước: Annotation class-level @RequiresApi(R) → nếu intent được resolve
 *          trên Android <11, ActivityNotFoundException hoặc class cast error.
 *   Sau:  Bỏ annotation class-level. Thêm Build.VERSION check trong onCreate().
 *         Activity vẫn được khai báo trong manifest nhưng chỉ hoạt động đúng
 *         khi SDK >= R. Dưới R → finish() ngay với log rõ ràng.
 *         BubbleNotificationService.showBubbleNotification() đã check SDK >= R
 *         trước khi start activity, nên path này thực tế không xảy ra production.
 */
class BubbleActivity : FlutterActivity() {

    companion object {
        private const val TAG = "BubbleActivity"

        // FIX #2: ENGINE_ID chung với BubbleOverlayService
        // BubbleOverlayService phải đổi MINI_CHAT_ENGINE_ID thành ENGINE_ID này
        const val SHARED_ENGINE_ID = "shared_flutter_engine"

        private const val CHANNEL = "bubble_chat_channel"

        private const val EXTRA_USER_ID = "userId"
        private const val EXTRA_USER_NAME = "userName"
        private const val EXTRA_AVATAR_URL = "avatarUrl"

        // Thời gian chờ tối đa để Flutter engine warm-up (ms)
        private const val ENGINE_WARMUP_TIMEOUT_MS = 2000L
        // Bước retry interval (ms)
        private const val RETRY_INTERVAL_MS = 200L

        fun createIntent(
            context: Context,
            userId: String,
            userName: String,
            avatarUrl: String
        ): Intent {
            return Intent(context, BubbleActivity::class.java).apply {
                putExtra(EXTRA_USER_ID, userId)
                putExtra(EXTRA_USER_NAME, userName)
                putExtra(EXTRA_AVATAR_URL, avatarUrl)
                addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT)
                addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
            }
        }

        /**
         * FIX #2: Warm up shared engine — gọi từ MainActivity.onCreate() hoặc
         * Application.onCreate() để engine sẵn sàng trước khi bubble mở.
         */
        fun warmUpSharedEngine(context: Context) {
            if (FlutterEngineCache.getInstance().contains(SHARED_ENGINE_ID)) {
                Log.d(TAG, "♻️ Shared engine already warmed up")
                return
            }
            Log.d(TAG, "🔥 Warming up shared Flutter engine...")
            val engine = FlutterEngine(context.applicationContext)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            FlutterEngineCache.getInstance().put(SHARED_ENGINE_ID, engine)
            Log.d(TAG, "✅ Shared engine warmed up and cached")
        }
    }

    // ========================================
    // STATE
    // ========================================
    private var methodChannel: MethodChannel? = null

    // Current values — dùng để track user đang hiển thị
    private var currentUserId: String? = null
    private var currentUserName: String? = null
    private var currentAvatarUrl: String? = null

    // FIX #1: Pending values — lưu yêu cầu navigate mới nhất
    // Tách biệt với current để tránh race condition
    private var pendingUserId: String? = null
    private var pendingUserName: String? = null
    private var pendingAvatarUrl: String? = null

    private var isFlutterReady = false

    // FIX #1: navigationAttempted giờ track theo userId, không phải boolean đơn
    // Key = userId, Value = true nếu đã navigate thành công
    private val navigationCompletedForUser = mutableSetOf<String>()

    // Số lần retry còn lại khi Flutter chưa ready
    private var retryCount = 0
    private val maxRetries = (ENGINE_WARMUP_TIMEOUT_MS / RETRY_INTERVAL_MS).toInt()

    // ========================================
    // LIFECYCLE
    // ========================================

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "✅ onCreate: BubbleActivity initialized")

        // FIX #4: Runtime check thay vì class-level annotation
        // Nếu device chạy Android < 11, activity không hoạt động đúng
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            Log.w(TAG, "⚠️ BubbleActivity requires Android 11+ (API 30), " +
                    "current SDK = ${Build.VERSION.SDK_INT}. Finishing.")
            finish()
            return
        }

        if (savedInstanceState == null) {
            extractUserFromIntent(intent)
        }

        Log.d(TAG, "📋 User: $currentUserName (ID: $currentUserId)")

        if (!validateCurrentUser()) {
            Log.e(TAG, "❌ Missing required user data, finishing activity")
            finish()
        }
    }

    // ========================================
    // FLUTTER ENGINE SETUP
    // ========================================

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        // FIX #2: Reuse shared engine, tạo mới nếu chưa có
        var engine = FlutterEngineCache.getInstance().get(SHARED_ENGINE_ID)

        if (engine == null) {
            Log.d(TAG, "🔧 Creating shared Flutter engine (first time)")
            engine = FlutterEngine(context.applicationContext)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            FlutterEngineCache.getInstance().put(SHARED_ENGINE_ID, engine)
            Log.d(TAG, "✅ Shared Flutter engine created and cached")
        } else {
            Log.d(TAG, "♻️ Reusing shared Flutter engine (ID: $SHARED_ENGINE_ID)")
        }

        return engine
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "🔧 Configuring Flutter engine for Bubble")

        setupWindowForInput()
        setupMethodChannel(flutterEngine)

        // FIX #1: Sau khi configure, set pending = current và bắt đầu retry loop
        // Không dùng fixed delay mà dùng retry mechanism
        setPendingFromCurrent()
        scheduleNavigationWithRetry()
    }

    // ========================================
    // FIX #1: PENDING/RETRY NAVIGATION MECHANISM
    // ========================================

    /**
     * Copy current user values vào pending để navigation lần đầu
     */
    private fun setPendingFromCurrent() {
        pendingUserId = currentUserId
        pendingUserName = currentUserName
        pendingAvatarUrl = currentAvatarUrl
        Log.d(TAG, "📌 Pending set: $pendingUserName")
    }

    /**
     * FIX #1: Retry loop — thử navigate mỗi RETRY_INTERVAL_MS
     * đến khi thành công hoặc hết maxRetries.
     * Dùng pending values chứ không phải current values.
     */
    private fun scheduleNavigationWithRetry(attempt: Int = 0) {
        if (isFinishing) return

        val uid = pendingUserId
        val uname = pendingUserName
        val avatar = pendingAvatarUrl

        if (uid == null || uname == null) {
            Log.w(TAG, "⚠️ No pending user to navigate to")
            return
        }

        // FIX #1: Chỉ skip nếu đã navigate THÀNH CÔNG cho đúng userId này
        if (navigationCompletedForUser.contains(uid)) {
            Log.d(TAG, "ℹ️ Already navigated to $uname, skipping")
            return
        }

        if (!isFlutterReady) {
            if (attempt >= maxRetries) {
                Log.e(TAG, "❌ Flutter never became ready after ${maxRetries} retries, giving up")
                return
            }
            Log.d(TAG, "⏳ Flutter not ready, retry ${attempt + 1}/$maxRetries in ${RETRY_INTERVAL_MS}ms")
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                scheduleNavigationWithRetry(attempt + 1)
            }, RETRY_INTERVAL_MS)
            return
        }

        navigateToChat(uid, uname, avatar ?: "")
    }

    private fun navigateToChat(userId: String, userName: String, avatarUrl: String) {
        if (isFinishing) return

        try {
            Log.d(TAG, "📤 Navigating Flutter to chat: $userName")

            methodChannel?.invokeMethod(
                "navigateToChat",
                mapOf(
                    "peerId" to userId,
                    "peerNickname" to userName,
                    "peerAvatar" to avatarUrl,
                    "isBubbleMode" to true
                )
            )

            // FIX #1: Mark thành công cho userId này
            navigationCompletedForUser.add(userId)
            Log.d(TAG, "✅ Navigation sent for: $userName")

            // Show keyboard sau khi navigate
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (!isFinishing) showKeyboard()
            }, 300L)

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to navigate: $e")
            // FIX #1: Không set navigationCompleted khi lỗi → cho phép retry
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
            Log.d(TAG, "✅ Window configured for keyboard input")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to configure window: $e")
        }
    }

    // ========================================
    // METHOD CHANNEL SETUP
    // ========================================

    private fun setupMethodChannel(flutterEngine: FlutterEngine) {
        try {
            methodChannel = MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                CHANNEL
            )

            methodChannel?.setMethodCallHandler { call, result ->
                Log.d(TAG, "📞 Method from Flutter: ${call.method}")
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
                            "userId" to currentUserId,
                            "userName" to currentUserName,
                            "avatarUrl" to currentAvatarUrl
                        ))
                    }
                    "getBubbleMode" -> {
                        result.success(true)
                    }
                    // FIX #1: Flutter báo sẵn sàng nhận lệnh navigate
                    "flutterReady" -> {
                        Log.d(TAG, "🟢 Flutter reported ready via channel")
                        isFlutterReady = true
                        scheduleNavigationWithRetry()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

            // FIX #1: Đặt isFlutterReady = true sau khi channel setup xong
            // Đây là dấu hiệu engine đã configure xong và có thể nhận method call
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (!isFinishing && !isFlutterReady) {
                    Log.d(TAG, "⏰ Setting Flutter ready via timeout fallback")
                    isFlutterReady = true
                    scheduleNavigationWithRetry()
                }
            }, 500L) // Fallback 500ms nếu Flutter không gửi "flutterReady"

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
            Log.e(TAG, "❌ Failed to show keyboard: $e")
        }
    }

    private fun hideKeyboard() {
        try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.hideSoftInputFromWindow(window.decorView.windowToken, 0)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to hide keyboard: $e")
        }
    }

    // ========================================
    // LIFECYCLE CALLBACKS
    // ========================================

    override fun onResume() {
        super.onResume()
        Log.d(TAG, "▶️ onResume")

        // FIX #1: Khi resume, retry navigation nếu pending user chưa được navigate
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
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        isFlutterReady = false

        // FIX #1: Clear tracking sets
        navigationCompletedForUser.clear()
        pendingUserId = null
        pendingUserName = null
        pendingAvatarUrl = null

        // FIX #2: KHÔNG destroy shared engine ở đây
        // Engine được quản lý bởi FlutterEngineCache và có thể được
        // reuse bởi BubbleOverlayService hoặc lần mở bubble tiếp theo.
        // Engine sẽ được giải phóng khi app process bị kill.
        Log.d(TAG, "ℹ️ Shared engine kept alive in cache for reuse")

        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "🔄 onNewIntent")

        val newUserId = intent.getStringExtra(EXTRA_USER_ID)
        val newUserName = intent.getStringExtra(EXTRA_USER_NAME)
        val newAvatarUrl = intent.getStringExtra(EXTRA_AVATAR_URL)

        if (newUserId != null && newUserId != currentUserId) {
            Log.d(TAG, "🔄 Switching user: $currentUserName → $newUserName")

            // Update current
            currentUserId = newUserId
            currentUserName = newUserName
            currentAvatarUrl = newAvatarUrl

            // FIX #1: Set pending = new user, kích hoạt navigation
            // navigationCompletedForUser KHÔNG bị clear hoàn toàn —
            // chỉ cần pending user mới chưa có trong set là đủ.
            pendingUserId = newUserId
            pendingUserName = newUserName
            pendingAvatarUrl = newAvatarUrl

            scheduleNavigationWithRetry()
        }
    }

    // ========================================
    // STATE PERSISTENCE
    // ========================================

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        outState.putString("userId", currentUserId)
        outState.putString("userName", currentUserName)
        outState.putString("avatarUrl", currentAvatarUrl)
        outState.putStringArrayList(
            "navigationCompleted",
            ArrayList(navigationCompletedForUser)
        )
        Log.d(TAG, "💾 State saved")
    }

    override fun onRestoreInstanceState(savedInstanceState: Bundle) {
        super.onRestoreInstanceState(savedInstanceState)
        currentUserId = savedInstanceState.getString("userId")
        currentUserName = savedInstanceState.getString("userName")
        currentAvatarUrl = savedInstanceState.getString("avatarUrl")

        // FIX #1: Restore navigation tracking
        savedInstanceState.getStringArrayList("navigationCompleted")?.let {
            navigationCompletedForUser.addAll(it)
        }

        Log.d(TAG, "📦 State restored for: $currentUserName")

        // FIX #1: Sau restore, set pending và retry
        setPendingFromCurrent()
        if (isFlutterReady) {
            scheduleNavigationWithRetry()
        }
    }

    // ========================================
    // BACK PRESS
    // ========================================

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        Log.d(TAG, "⬅️ Back pressed — minimizing to bubble")
        moveTaskToBack(true)
    }

    // ========================================
    // HELPERS
    // ========================================

    private fun extractUserFromIntent(intent: Intent) {
        currentUserId = intent.getStringExtra(EXTRA_USER_ID)
        currentUserName = intent.getStringExtra(EXTRA_USER_NAME)
        currentAvatarUrl = intent.getStringExtra(EXTRA_AVATAR_URL)
    }

    private fun validateCurrentUser(): Boolean {
        return !currentUserId.isNullOrEmpty() && !currentUserName.isNullOrEmpty()
    }
}
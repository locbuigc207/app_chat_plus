// android/app/src/main/kotlin/hust/appchat/BubbleActivity.kt
package hust.appchat

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * ✅ CRITICAL FIX #1: KEYBOARD INPUT WORKING
 * ✅ CRITICAL FIX #3: SMART NAVIGATION
 *
 * Changes:
 * - Removed FLAG_NOT_FOCUSABLE to allow keyboard input
 * - Added proper window focus management
 * - Force keyboard show after data sent
 * - Better lifecycle handling
 * - Smart navigation state management
 */
@RequiresApi(Build.VERSION_CODES.R)
class BubbleActivity : FlutterActivity() {

    companion object {
        private const val TAG = "BubbleActivity"
        private const val ENGINE_ID = "bubble_chat_engine"
        private const val CHANNEL = "bubble_chat_channel"

        private const val EXTRA_USER_ID = "userId"
        private const val EXTRA_USER_NAME = "userName"
        private const val EXTRA_AVATAR_URL = "avatarUrl"

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
    }

    // ========================================
    // STATE
    // ========================================
    private var methodChannel: MethodChannel? = null
    private var currentUserId: String? = null
    private var currentUserName: String? = null
    private var currentAvatarUrl: String? = null

    private var isFlutterReady = false
    private var navigationAttempted = false // ✅ FIX #3: Track navigation

    // ========================================
    // LIFECYCLE
    // ========================================

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "✅ onCreate: BubbleActivity initialized")

        // Extract user info
        if (savedInstanceState == null) {
            currentUserId = intent.getStringExtra(EXTRA_USER_ID)
            currentUserName = intent.getStringExtra(EXTRA_USER_NAME)
            currentAvatarUrl = intent.getStringExtra(EXTRA_AVATAR_URL)
        }

        Log.d(TAG, "📋 User: $currentUserName (ID: $currentUserId)")

        // Validate
        if (currentUserId.isNullOrEmpty() || currentUserName.isNullOrEmpty()) {
            Log.e(TAG, "❌ Missing required user data, finishing activity")
            finish()
            return
        }
    }

    // ========================================
    // FLUTTER ENGINE SETUP
    // ========================================

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        var engine = FlutterEngineCache.getInstance().get(ENGINE_ID)

        if (engine == null) {
            Log.d(TAG, "🔧 Creating new Flutter Engine for bubble")
            engine = FlutterEngine(context)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
            Log.d(TAG, "✅ Flutter Engine created and cached")
        } else {
            Log.d(TAG, "♻️ Reusing existing Flutter Engine")
        }

        return engine
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        Log.d(TAG, "🔧 Configuring Flutter Engine for Bubble")

        // ✅ CRITICAL FIX #1: ENABLE KEYBOARD INPUT
        setupWindowForInput()

        // Setup MethodChannel
        setupMethodChannel(flutterEngine)

        // Wait for Flutter to be ready, then send data
        android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
            if (!isFinishing) {
                isFlutterReady = true
                sendInitialDataToFlutter()
            }
        }, 800)
    }

    // ========================================
    // ✅ CRITICAL FIX #1: WINDOW SETUP FOR KEYBOARD
    // ========================================

    private fun setupWindowForInput() {
        try {
            // ✅ CRITICAL: Clear FLAG_NOT_FOCUSABLE to allow input
            window.clearFlags(WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE)

            // ✅ CRITICAL: Enable soft input adjustment
            window.setSoftInputMode(
                WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
                        WindowManager.LayoutParams.SOFT_INPUT_STATE_VISIBLE
            )

            // ✅ CRITICAL: Request window focus
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
                Log.d(TAG, "📞 Method called from Flutter: ${call.method}")

                when (call.method) {
                    "minimize" -> {
                        Log.d(TAG, "📦 Minimize bubble")
                        moveTaskToBack(true)
                        result.success(true)
                    }

                    "close" -> {
                        Log.d(TAG, "❌ Close bubble")
                        finish()
                        result.success(true)
                    }

                    "getUserInfo" -> {
                        Log.d(TAG, "📋 Get user info")
                        result.success(mapOf(
                            "userId" to currentUserId,
                            "userName" to currentUserName,
                            "avatarUrl" to currentAvatarUrl
                        ))
                    }

                    "getBubbleMode" -> {
                        result.success(true)
                    }

                    else -> {
                        Log.w(TAG, "⚠️ Unknown method: ${call.method}")
                        result.notImplemented()
                    }
                }
            }

            Log.d(TAG, "✅ MethodChannel setup complete")
        } catch (e: Exception) {
            Log.e(TAG, "❌ MethodChannel setup failed: $e")
        }
    }

    // ========================================
    // ✅ CRITICAL FIX #3: SMART NAVIGATION
    // ========================================

    private fun sendInitialDataToFlutter() {
        // Validate data
        if (currentUserId.isNullOrEmpty() || currentUserName.isNullOrEmpty()) {
            Log.w(TAG, "⚠️ Cannot send data: missing user info")
            return
        }

        // Check Flutter readiness
        if (!isFlutterReady) {
            Log.w(TAG, "⚠️ Flutter not ready yet")
            return
        }

        // Prevent duplicate navigation
        if (navigationAttempted) {
            Log.w(TAG, "ℹ️ Navigation already attempted, skipping")
            return
        }

        navigationAttempted = true

        try {
            Log.d(TAG, "📤 Sending initial data to Flutter")

            methodChannel?.invokeMethod(
                "navigateToChat",
                mapOf(
                    "peerId" to currentUserId!!,
                    "peerNickname" to currentUserName!!,
                    "peerAvatar" to (currentAvatarUrl ?: ""),
                    "isBubbleMode" to true
                )
            )

            Log.d(TAG, "✅ Initial data sent successfully")

            // ✅ CRITICAL FIX #1: Show keyboard after data sent
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (!isFinishing) {
                    showKeyboard()
                }
            }, 500)

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to send initial data: $e")
            navigationAttempted = false // Reset on failure

            // Retry once after delay
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (!isFinishing && !navigationAttempted) {
                    sendInitialDataToFlutter()
                }
            }, 500)
        }
    }

    // ========================================
    // ✅ CRITICAL FIX #1: KEYBOARD MANAGEMENT
    // ========================================

    private fun showKeyboard() {
        try {
            window.decorView.requestFocus()

            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.toggleSoftInput(InputMethodManager.SHOW_FORCED, 0)

            Log.d(TAG, "⌨️ Keyboard show requested")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to show keyboard: $e")
        }
    }

    private fun hideKeyboard() {
        try {
            val imm = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.hideSoftInputFromWindow(window.decorView.windowToken, 0)

            Log.d(TAG, "⌨️ Keyboard hidden")
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

        // Re-send data if Flutter was paused/resumed
        if (isFlutterReady && currentUserId != null && !navigationAttempted) {
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                if (!isFinishing) {
                    sendInitialDataToFlutter()
                }
            }, 300)
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

        // Cleanup
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        isFlutterReady = false
        navigationAttempted = false

        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "🔄 onNewIntent")

        // Update user info if changed
        val newUserId = intent.getStringExtra(EXTRA_USER_ID)
        val newUserName = intent.getStringExtra(EXTRA_USER_NAME)
        val newAvatarUrl = intent.getStringExtra(EXTRA_AVATAR_URL)

        if (newUserId != null && newUserId != currentUserId) {
            Log.d(TAG, "🔄 Switching user: $currentUserName -> $newUserName")

            currentUserId = newUserId
            currentUserName = newUserName
            currentAvatarUrl = newAvatarUrl
            navigationAttempted = false // ✅ FIX #3: Reset for new user

            // Re-send data to Flutter
            if (isFlutterReady) {
                sendInitialDataToFlutter()
            }
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
        outState.putBoolean("navigationAttempted", navigationAttempted) // ✅ FIX #3
        Log.d(TAG, "💾 State saved")
    }

    override fun onRestoreInstanceState(savedInstanceState: Bundle) {
        super.onRestoreInstanceState(savedInstanceState)
        currentUserId = savedInstanceState.getString("userId")
        currentUserName = savedInstanceState.getString("userName")
        currentAvatarUrl = savedInstanceState.getString("avatarUrl")
        navigationAttempted = savedInstanceState.getBoolean("navigationAttempted", false) // ✅ FIX #3
        Log.d(TAG, "📦 State restored")

        // Re-initialize if needed
        if (isFlutterReady && currentUserId != null && !navigationAttempted) {
            sendInitialDataToFlutter()
        }
    }

    // ========================================
    // BACK PRESS HANDLING
    // ========================================

    override fun onBackPressed() {
        Log.d(TAG, "⬅️ Back pressed - minimizing to bubble")
        moveTaskToBack(true)
    }
}
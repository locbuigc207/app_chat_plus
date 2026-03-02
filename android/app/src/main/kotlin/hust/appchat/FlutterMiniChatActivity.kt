// android/app/src/main/kotlin/hust/appchat/FlutterMiniChatActivity.kt
package hust.appchat

import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/**
 * ✅ Flutter Activity cho Mini Chat overlay
 * Render Flutter widget (ChatPage) trong WindowManager overlay
 */
class FlutterMiniChatActivity : FlutterActivity() {

    companion object {
        private const val ENGINE_ID = "mini_chat_engine"
        private const val CHANNEL = "mini_chat_overlay"

        // ✅ Intent extras
        private const val EXTRA_USER_ID = "userId"
        private const val EXTRA_USER_NAME = "userName"
        private const val EXTRA_AVATAR_URL = "avatarUrl"

        fun createIntent(
            context: Context,
            userId: String,
            userName: String,
            avatarUrl: String
        ): Intent {
            return Intent(context, FlutterMiniChatActivity::class.java).apply {
                putExtra(EXTRA_USER_ID, userId)
                putExtra(EXTRA_USER_NAME, userName)
                putExtra(EXTRA_AVATAR_URL, avatarUrl)

                // ✅ Flags for overlay
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION)
            }
        }
    }

    private var windowManager: WindowManager? = null
    private var overlayView: android.view.View? = null

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        // ✅ Reuse existing engine hoặc tạo mới
        return FlutterEngineCache.getInstance().get(ENGINE_ID)
            ?: super.provideFlutterEngine(context)?.also {
                FlutterEngineCache.getInstance().put(ENGINE_ID, it)
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ✅ Get user info from intent
        val userId = intent.getStringExtra(EXTRA_USER_ID) ?: return
        val userName = intent.getStringExtra(EXTRA_USER_NAME) ?: ""
        val avatarUrl = intent.getStringExtra(EXTRA_AVATAR_URL) ?: ""

        // ✅ Setup overlay window
        setupOverlayWindow()

        // ✅ Send data to Flutter
        sendDataToFlutter(userId, userName, avatarUrl)
    }

    private fun setupOverlayWindow() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val params = WindowManager.LayoutParams(
            (resources.displayMetrics.widthPixels * 0.9).toInt(),
            (resources.displayMetrics.heightPixels * 0.7).toInt(),
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER
        }

        // ✅ Add Flutter view to overlay
        overlayView = findViewById(android.R.id.content)
        try {
            windowManager?.addView(overlayView, params)
        } catch (e: Exception) {
            android.util.Log.e("FlutterMiniChat", "❌ Error adding overlay: $e")
        }
    }

    private fun sendDataToFlutter(userId: String, userName: String, avatarUrl: String) {
        flutterEngine?.dartExecutor?.let { executor ->
            MethodChannel(executor.binaryMessenger, CHANNEL).invokeMethod(
                "initMiniChat",
                mapOf(
                    "userId" to userId,
                    "userName" to userName,
                    "avatarUrl" to avatarUrl
                )
            )
        }
    }

    override fun onDestroy() {
        try {
            overlayView?.let { windowManager?.removeView(it) }
        } catch (e: Exception) {
            android.util.Log.e("FlutterMiniChat", "❌ Error removing overlay: $e")
        }
        super.onDestroy()
    }
}
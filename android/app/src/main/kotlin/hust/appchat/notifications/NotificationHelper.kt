// android/app/src/main/kotlin/hust/appchat/notifications/NotificationHelper.kt
package hust.appchat.notifications

import android.app.*
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.request.RequestOptions
import hust.appchat.BubbleActivity
import hust.appchat.MainActivity
import hust.appchat.R
import hust.appchat.shortcuts.AvatarLoader
import hust.appchat.shortcuts.ShortcutHelper
import kotlinx.coroutines.*

object NotificationHelper {
    private const val TAG = "NotificationHelper"

    private const val CHANNEL_ID = "chat_messages"
    private const val CHANNEL_NAME = "Chat Messages"
    private const val CHANNEL_DESC = "Notifications for chat messages"
    private const val BASE_NOTIFICATION_ID = 1000

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // ========================================
    // INITIALIZATION
    // ========================================

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = CHANNEL_DESC

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    setAllowBubbles(true)
                }

                enableLights(true)
                enableVibration(true)
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }

            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)

            Log.d(TAG, "✅ Notification channel created")
        }
    }

    // ========================================
    // NOTIFICATION & SHORTCUT MANAGEMENT
    // ========================================

    fun cancelNotification(context: Context, userId: String) {
        try {
            val notificationId = getNotificationId(userId)
            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.cancel(notificationId)

            ShortcutHelper.removeShortcut(context, userId)

            Log.d(TAG, "✅ Notification + shortcut cancelled: $userId")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Cancel notification failed: $e")
        }
    }

    fun cancelAllNotifications(context: Context) {
        try {
            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.cancelAll()

            ShortcutHelper.removeAllShortcuts(context)

            Log.d(TAG, "✅ All notifications + shortcuts cancelled")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Cancel all notifications failed: $e")
        }
    }

    private fun getNotificationId(userId: String): Int {
        return BASE_NOTIFICATION_ID + userId.hashCode() % 1000
    }

    // ========================================
    // AVATAR UTILITIES
    // ========================================

    @RequiresApi(Build.VERSION_CODES.M)
    fun preloadAvatar(
        context: Context,
        avatarUrl: String,
        userName: String
    ) {
        AvatarLoader.preloadAvatar(context, avatarUrl, userName)
        Log.d(TAG, "✅ Preloaded avatar: $userName")
    }

    @RequiresApi(Build.VERSION_CODES.M)
    suspend fun preloadAvatarsBatch(
        context: Context,
        users: List<Triple<String, String, String>>
    ) {
        val avatarList = users.map { (_, userName, avatarUrl) ->
            avatarUrl to userName
        }

        AvatarLoader.preloadAvatarsBatch(context, avatarList)
        Log.d(TAG, "✅ Batch preload complete: ${users.size} avatars")
    }

    fun clearAvatarCache(avatarUrl: String, userName: String) {
        AvatarLoader.clearCache(avatarUrl, userName)
        Log.d(TAG, "🗑️ Cleared avatar cache: $userName")
    }

    fun clearAllAvatarCache() {
        AvatarLoader.clearAllCache()
        Log.d(TAG, "🗑️ Cleared all avatar cache")
    }

    fun getAvatarCacheStats(): Map<String, Any> {
        return AvatarLoader.getCacheStats()
    }

    // ========================================
    // CLEANUP
    // ========================================

    fun cleanup() {
        scope.cancel()
        clearAllAvatarCache()
        ShortcutHelper.cleanup()
        Log.d(TAG, "✅ NotificationHelper cleanup complete")
    }
}
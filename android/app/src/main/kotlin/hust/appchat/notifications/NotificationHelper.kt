// android/app/src/main/kotlin/hust/appchat/notifications/NotificationHelper.kt
package hust.appchat.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import hust.appchat.shortcuts.AvatarLoader
import hust.appchat.shortcuts.ShortcutHelper
import kotlinx.coroutines.*
import kotlin.math.abs

/**
 * NotificationHelper — Utility layer on top of [NotificationManager].
 *
 * Responsibilities:
 * • Create / verify notification channels on first call.
 * • Cancel individual or all notifications.
 * • Delegate avatar cache management to [AvatarLoader].
 * • Provide coroutine-based batch avatar preloading.
 * • Check notification/bubble enablement status.
 *
 * Channels:
 * • CHANNEL_MESSAGES — high importance; allows bubbles; shows badge.
 * • CHANNEL_SERVICE  — min importance; used by foreground service; no sound.
 */
object NotificationHelper {

    private const val TAG = "NotificationHelper"

    const val CHANNEL_MESSAGES = "chat_messages"
    const val CHANNEL_SERVICE  = "chat_bubbles"

    private const val BASE_NOTIF_ID = 2_000

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var channelsCreated = false

    // ========================================
    // CHANNEL CREATION
    // ========================================

    fun createNotificationChannel(context: Context) {
        if (channelsCreated || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        try {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return

            // Messages channel — used for Bubble API notifications
            val msgChannel = NotificationChannel(
                CHANNEL_MESSAGES,
                "Tin nhắn",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Thông báo tin nhắn với bong bóng chat"
                enableLights(true)
                lightColor = 0xFF2196F3.toInt()
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 120, 60, 120)
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    setAllowBubbles(true)
                }
            }

            // Service channel — for foreground service notification (silent)
            val svcChannel = NotificationChannel(
                CHANNEL_SERVICE,
                "Dịch vụ bong bóng",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Duy trì bong bóng chat trong nền"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
            }

            nm.createNotificationChannels(listOf(msgChannel, svcChannel))
            channelsCreated = true
            Log.d(TAG, "✅ Notification channels created")

        } catch (e: Exception) {
            Log.e(TAG, "❌ createNotificationChannel: $e")
        }
    }

    // ========================================
    // CANCEL NOTIFICATIONS
    // ========================================

    fun cancelNotification(context: Context, userId: String) {
        try {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return
            nm.cancel(getNotificationId(userId))

            ShortcutHelper.removeShortcut(context, userId)
            Log.d(TAG, "✅ Notification and shortcut cancelled: $userId")
        } catch (e: Exception) {
            Log.e(TAG, "❌ cancelNotification failed: $e")
        }
    }

    fun cancelAllNotifications(context: Context) {
        try {
            context.getSystemService(NotificationManager::class.java)?.cancelAll()
            ShortcutHelper.removeAllShortcuts(context)
            Log.d(TAG, "✅ All notifications and shortcuts cancelled")
        } catch (e: Exception) {
            Log.e(TAG, "❌ cancelAllNotifications failed: $e")
        }
    }

    fun getNotificationId(userId: String): Int {
        return BASE_NOTIF_ID + (abs(userId.hashCode()) % 1_000)
    }

    // ========================================
    // AVATAR UTILITIES
    // ========================================

    fun preloadAvatar(context: Context, avatarUrl: String, userName: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        scope.launch {
            try {
                AvatarLoader.preloadAvatar(context, avatarUrl, userName)
            } catch (e: Exception) {
                Log.e(TAG, "❌ preloadAvatar failed: $e")
            }
        }
    }

    suspend fun preloadAvatarsBatch(
        context: Context,
        users: List<Triple<String, String, String>>
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        val avatarList = users.map { (_, userName, avatarUrl) -> avatarUrl to userName }
        AvatarLoader.preloadAvatarsBatch(context, avatarList)
    }

    fun clearAvatarCache(avatarUrl: String, userName: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AvatarLoader.clearCache(avatarUrl, userName)
            Log.d(TAG, "🗑️ Cleared avatar cache for: $userName")
        }
    }

    fun clearAllAvatarCache() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AvatarLoader.clearAllCache()
            Log.d(TAG, "🗑️ Cleared all avatar cache")
        }
    }

    fun getAvatarCacheStats(): Map<String, Any> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AvatarLoader.getCacheStats()
        } else {
            emptyMap()
        }
    }

    // ========================================
    // CHANNEL STATUS CHECKS
    // ========================================

    fun isBubbleChannelEnabled(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true

        return try {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                nm.areBubblesAllowed()
            } else {
                val channel = nm.getNotificationChannel(CHANNEL_MESSAGES) ?: return false
                channel.importance >= NotificationManager.IMPORTANCE_DEFAULT
            }
        } catch (e: Exception) {
            false
        }
    }

    fun areNotificationsEnabled(context: Context): Boolean {
        return try {
            context.getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() ?: true
        } catch (e: Exception) {
            true
        }
    }

    // ========================================
    // CLEANUP
    // ========================================

    fun cleanup() {
        scope.coroutineContext.cancelChildren() // Safely cancel ongoing jobs without killing the scope entirely
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AvatarLoader.clearAllCache()
        }
        ShortcutHelper.cleanup()
        channelsCreated = false
        Log.d(TAG, "✅ NotificationHelper cleanup complete")
    }
}
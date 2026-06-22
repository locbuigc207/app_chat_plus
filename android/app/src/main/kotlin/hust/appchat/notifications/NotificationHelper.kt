// android/app/src/main/kotlin/hust/appchat/notifications/NotificationHelper.kt
package hust.appchat.notifications

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.content.Context
import android.os.Build
import android.util.Log
import hust.appchat.shortcuts.AvatarLoader
import hust.appchat.shortcuts.ShortcutHelper
import kotlinx.coroutines.*

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
 * (Đã dọn dẹp CHANNEL_SERVICE do BubbleOverlayService không còn tồn tại ở minSdk 30)
 */
object NotificationHelper {

    private const val TAG = "NotificationHelper"

    const val CHANNEL_MESSAGES = "chat_messages"
    private const val GROUP_CONVERSATIONS = "conversations_group"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var channelsCreated = false

    // ========================================
    // CHANNEL CREATION
    // ========================================

    fun createNotificationChannel(context: Context) {
        if (channelsCreated) return

        try {
            val nm = context.getSystemService(NotificationManager::class.java) ?: return

            // [SỬA LỖI FINAL]: Tạo NotificationChannelGroup để gom nhóm trực quan trong Cài đặt
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                nm.createNotificationChannelGroup(
                    NotificationChannelGroup(GROUP_CONVERSATIONS, "Trò chuyện")
                )
            }

            // Messages channel — used for Bubble API notifications
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
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
                    group = GROUP_CONVERSATIONS

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        setAllowBubbles(true) // Luôn áp dụng trên Android 10+
                    }

                    // [SỬA LỖI FINAL]: Bổ sung Conversation Channel để định danh luồng nhắn tin (Yêu cầu cho Android 12+)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                        setConversationId(CHANNEL_MESSAGES, "default_conversation")
                    }
                }
                nm.createNotificationChannel(msgChannel)
            }

            channelsCreated = true
            Log.d(TAG, "✅ Notification channel created (Conversation Support: true)")

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

    // Gộp công thức tính ID về một nguồn duy nhất (Single Source of Truth)
    fun getNotificationId(userId: String): Int {
        return BubbleNotificationManager.notifId(userId)
    }

    // ========================================
    // AVATAR UTILITIES
    // ========================================

    fun preloadAvatar(context: Context, avatarUrl: String, userName: String) {
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
        val avatarList = users.map { (_, userName, avatarUrl) -> avatarUrl to userName }
        AvatarLoader.preloadAvatarsBatch(context, avatarList)
    }

    fun clearAvatarCache(avatarUrl: String, userName: String) {
        AvatarLoader.clearCache(avatarUrl, userName)
        Log.d(TAG, "🗑️ Cleared avatar cache for: $userName")
    }

    fun clearAllAvatarCache() {
        AvatarLoader.clearAllCache()
        Log.d(TAG, "🗑️ Cleared all avatar cache")
    }

    fun getAvatarCacheStats(): Map<String, Any> {
        return AvatarLoader.getCacheStats()
    }

    // ========================================
    // CHANNEL STATUS CHECKS
    // ========================================

    fun isBubbleChannelEnabled(context: Context): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val nm = context.getSystemService(NotificationManager::class.java) ?: return false
                val channel = nm.getNotificationChannel(CHANNEL_MESSAGES) ?: return false

                // Dùng canBubble() kết hợp areNotificationsEnabled() là phương pháp chuẩn
                // và ổn định nhất để kiểm tra trạng thái Bubble API trên Android 11+.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    channel.importance >= NotificationManager.IMPORTANCE_DEFAULT &&
                            nm.areNotificationsEnabled() &&
                            channel.canBubble()
                } else {
                    channel.importance >= NotificationManager.IMPORTANCE_DEFAULT &&
                            nm.areNotificationsEnabled()
                }
            } else {
                true
            }
        } catch (e: Exception) {
            true // Mặc định trả về true để hệ thống tự quyết định việc hiển thị nếu kiểm tra lỗi
        }
    }

    fun areNotificationsEnabled(context: Context): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                context.getSystemService(NotificationManager::class.java)?.areNotificationsEnabled() ?: true
            } else {
                true
            }
        } catch (e: Exception) {
            true
        }
    }

    // ========================================
    // CLEANUP
    // ========================================

    fun cleanup() {
        scope.coroutineContext.cancelChildren() // Hủy an toàn các tác vụ con đang chạy
        AvatarLoader.clearAllCache()
        ShortcutHelper.cleanup()
        channelsCreated = false
        Log.d(TAG, "✅ NotificationHelper cleanup complete")
    }
}
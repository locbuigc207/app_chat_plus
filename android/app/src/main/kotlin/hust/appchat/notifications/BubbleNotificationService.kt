// android/app/src/main/kotlin/hust/appchat/notifications/BubbleNotificationService.kt
package hust.appchat.notifications

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import hust.appchat.bubble.BubbleManager
import hust.appchat.shortcuts.AvatarLoader
import hust.appchat.shortcuts.ShortcutHelper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

object BubbleNotificationService {
    internal const val TAG = "BubbleNotifService"

    internal val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    internal var isInitialized = false

    internal val activeBubbleNotifications = mutableSetOf<String>()

    // ========================================
    // INITIALIZATION
    // ========================================

    fun init(context: Context) {
        if (isInitialized) {
            Log.d(TAG, "ℹ️ Already initialized")
            return
        }

        try {
            NotificationHelper.createNotificationChannel(context)

            if (ShortcutHelper.isShortcutsSupported()) {
                Log.d(TAG, "✅ Shortcuts supported")

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    preloadRecentAvatars(context)
                }
            } else {
                Log.w(TAG, "⚠️ Shortcuts not supported on this device")
            }

            isInitialized = true
            Log.d(TAG, "✅ BubbleNotificationService initialized")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Initialization failed: $e")
        }
    }

    // ========================================
    // AVATAR PRELOADING
    // ========================================

    @RequiresApi(Build.VERSION_CODES.M)
    private fun preloadRecentAvatars(context: Context) {
        scope.launch {
            try {
                Log.d(TAG, "🔄 Preloading recent avatars...")

                val activeBubbles = BubbleManager.getActiveBubbles()

                if (activeBubbles.isNotEmpty()) {
                    val userList = activeBubbles.map { (_, bubble) ->
                        bubble.avatarUrl to bubble.userName
                    }

                    AvatarLoader.preloadAvatarsBatch(context, userList)
                    Log.d(TAG, "✅ Preloaded ${activeBubbles.size} avatars")
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ Avatar preload failed: $e")
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    suspend fun preloadAvatarForNotification(
        context: Context,
        avatarUrl: String,
        userName: String
    ) {
        try {
            AvatarLoader.loadAvatarIconAsync(
                context = context,
                avatarUrl = avatarUrl,
                userName = userName
            )
            Log.d(TAG, "✅ Avatar preloaded for: $userName")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Preload failed: $e")
        }
    }

    // ========================================
    // BUBBLE NOTIFICATION WITH MESSAGE HISTORY
    // ========================================

    fun showBubbleNotification(
        context: Context,
        userId: String,
        userName: String,
        message: String,
        avatarUrl: String
    ) {
        if (!isInitialized) {
            Log.w(TAG, "⚠️ Service not initialized, initializing now...")
            init(context)
        }

        scope.launch {
            try {
                Log.d(TAG, "🎈 Creating bubble notification: $userName")

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        preloadAvatarForNotification(context, avatarUrl, userName)
                    }

                    val shortcutExists = ShortcutHelper.shortcutExists(context, userId)

                    if (!shortcutExists) {
                        Log.d(TAG, "🔗 Shortcut missing, creating for: $userName")

                        ShortcutHelper.createShortcut(
                            context = context,
                            userId = userId,
                            userName = userName,
                            avatarUrl = avatarUrl
                        )

                        delay(500)

                        val verifyShortcut = ShortcutHelper.shortcutExists(context, userId)
                        if (!verifyShortcut) {
                            Log.e(TAG, "❌ Failed to create shortcut for: $userName")
                            BubbleManager.showBubble(
                                context = context,
                                userId = userId,
                                userName = userName,
                                avatarUrl = avatarUrl,
                                message = message
                            )
                            return@launch
                        }
                    } else {
                        Log.d(TAG, "✅ Shortcut already exists for: $userName")
                    }

                    BubbleNotificationManager.addMessage(
                        context = context,
                        userId = userId,
                        userName = userName,
                        message = message,
                        avatarUrl = avatarUrl,
                        isFromUser = false,
                        messageType = BubbleNotificationManager.MessageType.TEXT
                    )

                    activeBubbleNotifications.add(userId)
                    Log.d(TAG, "✅ Bubble notification created with message history")

                } else {
                    Log.d(TAG, "⚠️ Android < 11, using WindowManager fallback")
                    BubbleManager.showBubble(
                        context = context,
                        userId = userId,
                        userName = userName,
                        avatarUrl = avatarUrl,
                        message = message
                    )
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to create bubble notification: $e")

                try {
                    BubbleManager.showBubble(
                        context = context,
                        userId = userId,
                        userName = userName,
                        avatarUrl = avatarUrl,
                        message = message
                    )
                    Log.d(TAG, "✅ Fallback to WindowManager successful")
                } catch (fallbackError: Exception) {
                    Log.e(TAG, "❌ Fallback also failed: $fallbackError")
                }
            }
        }
    }

    fun updateBubbleNotification(
        context: Context,
        userId: String,
        userName: String,
        message: String,
        avatarUrl: String
    ) {
        scope.launch {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                    activeBubbleNotifications.contains(userId)) {

                    ShortcutHelper.ensureShortcutForNotification(
                        context = context,
                        userId = userId,
                        userName = userName,
                        avatarUrl = avatarUrl
                    )

                    BubbleNotificationManager.addMessage(
                        context = context,
                        userId = userId,
                        userName = userName,
                        message = message,
                        avatarUrl = avatarUrl,
                        isFromUser = false,
                        messageType = BubbleNotificationManager.MessageType.TEXT
                    )

                    Log.d(TAG, "✅ Bubble notification updated: $userName")

                } else {
                    BubbleManager.showBubble(
                        context = context,
                        userId = userId,
                        userName = userName,
                        avatarUrl = avatarUrl,
                        message = message
                    )
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Update bubble notification failed: $e")
            }
        }
    }

    // ========================================
    // SEND MESSAGE FROM USER
    // ========================================

    fun sendMessage(
        context: Context,
        userId: String,
        userName: String,
        message: String,
        avatarUrl: String,
        messageType: BubbleNotificationManager.MessageType = BubbleNotificationManager.MessageType.TEXT
    ) {
        scope.launch {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    BubbleNotificationManager.addMessage(
                        context = context,
                        userId = userId,
                        userName = userName,
                        message = message,
                        avatarUrl = avatarUrl,
                        isFromUser = true,
                        messageType = messageType
                    )

                    Log.d(TAG, "✅ User message added to bubble: $message")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to send message: $e")
            }
        }
    }

    // ========================================
    // DISMISSAL WITH CLEANUP
    // ========================================

    fun dismissBubble(context: Context, userId: String) {
        scope.launch {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    BubbleNotificationManager.clearHistory(userId)

                    Log.d(TAG, "🗑️ Removing shortcut for: $userId")
                    ShortcutHelper.removeShortcut(context, userId)

                    NotificationHelper.cancelNotification(context, userId)

                    activeBubbleNotifications.remove(userId)
                    Log.d(TAG, "✅ Bubble dismissed")
                }

                BubbleManager.removeBubble(context, userId)

            } catch (e: Exception) {
                Log.e(TAG, "❌ Dismiss bubble failed: $e")
            }
        }
    }

    fun dismissAllBubbles(context: Context) {
        scope.launch {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    BubbleNotificationManager.clearAllHistory()

                    Log.d(TAG, "🗑️ Removing all shortcuts")
                    ShortcutHelper.removeAllShortcuts(context)

                    NotificationHelper.cancelAllNotifications(context)

                    activeBubbleNotifications.clear()
                }

                BubbleManager.cleanup()

                Log.d(TAG, "✅ All bubbles dismissed")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Dismiss all bubbles failed: $e")
            }
        }
    }

    // ========================================
    // STATE QUERIES
    // ========================================

    fun isBubbleActive(userId: String): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activeBubbleNotifications.contains(userId)
        } else {
            BubbleManager.isBubbleActive(userId)
        }
    }

    fun getActiveBubbleCount(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activeBubbleNotifications.size
        } else {
            BubbleManager.getActiveBubbles().size
        }
    }

    fun getActiveBubbleUserIds(): Set<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activeBubbleNotifications.toSet()
        } else {
            BubbleManager.getActiveBubbles().keys.toSet()
        }
    }

    // ========================================
    // STATISTICS
    // ========================================

    fun getBubbleStats(): Map<String, Any> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            BubbleNotificationManager.getStats()
        } else {
            mapOf(
                "implementation" to "WindowManager",
                "activeBubbles" to BubbleManager.getActiveBubbles().size
            )
        }
    }

    fun logBubbleState() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            BubbleNotificationManager.logState()
        }

        Log.d(TAG, "Active bubble notifications: ${activeBubbleNotifications.size}")
        activeBubbleNotifications.forEach { userId ->
            val count = BubbleNotificationManager.getMessageCount(userId)
            val lastMsg = BubbleNotificationManager.getLastMessage(userId)
            Log.d(TAG, "  - $userId: $count messages, last: ${lastMsg?.text?.take(30)}")
        }
    }

    // ========================================
    // AVATAR CACHE UTILITIES
    // ========================================

    fun getAvatarCacheStats(): Map<String, Any> {
        return AvatarLoader.getCacheStats()
    }

    fun clearAvatarCache() {
        AvatarLoader.clearAllCache()
        Log.d(TAG, "🗑️ Avatar cache cleared")
    }

    fun refreshAvatar(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String
    ) {
        scope.launch {
            try {
                AvatarLoader.clearCache(avatarUrl, userName)

                ShortcutHelper.refreshShortcutAvatar(
                    context = context,
                    userId = userId,
                    userName = userName,
                    avatarUrl = avatarUrl
                )

                Log.d(TAG, "✅ Avatar refreshed for: $userName")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Avatar refresh failed: $e")
            }
        }
    }

    // ========================================
    // SHORTCUT UTILITIES
    // ========================================

    fun getShortcutCount(context: Context): Int {
        return ShortcutHelper.getShortcutCount(context)
    }

    fun canCreateMoreShortcuts(context: Context): Boolean {
        return ShortcutHelper.canCreateMoreShortcuts(context)
    }

    fun isShortcutsSupported(): Boolean {
        return ShortcutHelper.isShortcutsSupported()
    }

    fun syncShortcuts(context: Context) {
        scope.launch {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    Log.d(TAG, "🔄 Syncing shortcuts with active bubbles")

                    val activeBubbles = BubbleManager.getActiveBubbles()

                    activeBubbles.forEach { (userId, bubble) ->
                        ShortcutHelper.ensureShortcutForNotification(
                            context = context,
                            userId = userId,
                            userName = bubble.userName,
                            avatarUrl = bubble.avatarUrl
                        )
                    }

                    Log.d(TAG, "✅ Shortcuts synced: ${activeBubbles.size} shortcuts")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Sync shortcuts failed: $e")
            }
        }
    }

    // ========================================
    // UTILITIES
    // ========================================

    fun shouldUseBubbleApi(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.R
    }

    fun getImplementationType(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            "Bubble API + Shortcuts + Avatar Cache + Message History"
        } else {
            "WindowManager"
        }
    }

    // ========================================
    // LIFECYCLE
    // ========================================

    fun onAppPaused() {
        Log.d(TAG, "⏸️ App paused")
    }

    fun onAppResumed(context: Context) {
        Log.d(TAG, "▶️ App resumed")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            syncBubbleState(context)
            syncShortcuts(context)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                preloadRecentAvatars(context)
            }
        } else {
            BubbleManager.onAppResumed(context)
        }
    }

    private fun syncBubbleState(context: Context) {
        scope.launch {
            try {
                val managerBubbles = BubbleManager.getActiveBubbles()

                activeBubbleNotifications.clear()
                activeBubbleNotifications.addAll(managerBubbles.keys)

                Log.d(TAG, "✅ Bubble state synced: ${activeBubbleNotifications.size} active")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Sync bubble state failed: $e")
            }
        }
    }

    // ========================================
    // CLEANUP
    // ========================================

    fun cleanup(context: Context) {
        try {
            dismissAllBubbles(context)
            NotificationHelper.cleanup()
            ShortcutHelper.cleanup()

            activeBubbleNotifications.clear()
            isInitialized = false

            Log.d(TAG, "✅ Cleanup complete")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Cleanup failed: $e")
        }
    }
}
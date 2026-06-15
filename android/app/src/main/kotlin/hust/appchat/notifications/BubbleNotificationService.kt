// android/app/src/main/kotlin/hust/appchat/notifications/BubbleNotificationService.kt
package hust.appchat.notifications

import android.content.Context
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import hust.appchat.bubble.BubbleManager
import hust.appchat.shortcuts.AvatarLoader
import hust.appchat.shortcuts.ShortcutHelper
import kotlinx.coroutines.*

@android.annotation.SuppressLint("NewApi")
object BubbleNotificationService {

    internal const val TAG = "BubbleNotifService"

    // Use IO dispatcher for background operations like shortcut creation and cache access
    internal val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    @Volatile
    var isInitialized = false
        private set

    // userId -> true means a Bubble-API notification exists for that user.
    internal val activeBubbles = LinkedHashSet<String>()

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

    private fun preloadRecentAvatars(context: Context) {
        scope.launch {
            try {
                val bubbles = BubbleManager.getActiveBubbles()
                if (bubbles.isEmpty()) return@launch

                Log.d(TAG, "🔄 Preloading recent avatars...")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    val userList = bubbles.map { (_, b) -> b.avatarUrl to b.userName }
                    AvatarLoader.preloadAvatarsBatch(context, userList)
                    Log.d(TAG, "✅ Preloaded ${bubbles.size} avatars")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Avatar preload failed: $e")
            }
        }
    }

    // ========================================
    // BUBBLE NOTIFICATION SHOW/UPDATE
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
                    showModernBubble(context, userId, userName, message, avatarUrl)
                } else {
                    Log.d(TAG, "⚠️ Android < 11, using WindowManager fallback")
                    BubbleManager.showBubble(context, userId, userName, avatarUrl, message)
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to create bubble notification: $e")
                fallbackToOverlay(context, userId, userName, avatarUrl, message)
            }
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private suspend fun showModernBubble(
        context: Context,
        userId: String,
        userName: String,
        message: String,
        avatarUrl: String
    ) {
        // ĐÃ SỬA: Bao bọc try-catch và timeout để tránh văng app ngầm nếu quá tải mạng khi tải ảnh
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                withTimeout(3000L) {
                    AvatarLoader.loadAvatarIconAsync(context, avatarUrl, userName)
                }
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ Failed to load avatar async, using fallback: $e")
            }
        }

        // 2. Ensure shortcut exists (required for Bubble API)
        ensureShortcut(context, userId, userName, avatarUrl)

        // 3. Push notification with bubble metadata
        BubbleNotificationManager.addMessage(
            context = context,
            userId = userId,
            userName = userName,
            message = message,
            avatarUrl = avatarUrl,
            fromUser = false,
            type = BubbleNotificationManager.MessageType.TEXT
        )

        synchronized(activeBubbles) { activeBubbles.add(userId) }
        Log.d(TAG, "✅ Modern bubble shown: $userName")
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
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && isBubbleActive(userId)) {
                    ensureShortcut(context, userId, userName, avatarUrl)
                    BubbleNotificationManager.addMessage(
                        context = context,
                        userId = userId,
                        userName = userName,
                        message = message,
                        avatarUrl = avatarUrl,
                        fromUser = false,
                        type = BubbleNotificationManager.MessageType.TEXT
                    )
                    Log.d(TAG, "✅ Bubble notification updated: $userName")
                } else {
                    BubbleManager.showBubble(context, userId, userName, avatarUrl, message)
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Update bubble notification failed: $e")
            }
        }
    }

    private fun fallbackToOverlay(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String,
        message: String
    ) {
        try {
            BubbleManager.showBubble(context, userId, userName, avatarUrl, message)
            Log.d(TAG, "✅ Fallback to WindowManager successful for $userName")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Fallback also failed: $e")
        }
    }

    // ========================================
    // SEND MESSAGE FROM USER (OUTGOING)
    // ========================================

    fun sendMessage(
        context: Context,
        userId: String,
        userName: String,
        message: String,
        avatarUrl: String,
        messageType: BubbleNotificationManager.MessageType = BubbleNotificationManager.MessageType.TEXT
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return

        scope.launch {
            try {
                BubbleNotificationManager.addMessage(
                    context = context,
                    userId = userId,
                    userName = userName,
                    message = message,
                    avatarUrl = avatarUrl,
                    fromUser = true,
                    type = messageType
                )
                Log.d(TAG, "✅ User message added to bubble: $message")
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

                    synchronized(activeBubbles) { activeBubbles.remove(userId) }
                }
                BubbleManager.removeBubble(context, userId)
                Log.d(TAG, "✅ Bubble dismissed: $userId")
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

                    synchronized(activeBubbles) { activeBubbles.clear() }
                }
                BubbleManager.cleanup()
                Log.d(TAG, "✅ All bubbles dismissed")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Dismiss all bubbles failed: $e")
            }
        }
    }

    // ========================================
    // SHORTCUT UTILITIES
    // ========================================

    @RequiresApi(Build.VERSION_CODES.R)
    private suspend fun ensureShortcut(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String
    ) {
        if (ShortcutHelper.shortcutExists(context, userId)) {
            Log.d(TAG, "✅ Shortcut already exists for: $userName")
            return
        }

        Log.d(TAG, "🔗 Shortcut missing, creating for: $userName")
        ShortcutHelper.createShortcut(context, userId, userName, avatarUrl)

        // ĐÃ SỬA: Chờ tối đa 2 giây bằng Polling thay vì hard-delay 400ms dễ gây lỗi crash
        var attempts = 0
        while (!ShortcutHelper.shortcutExists(context, userId) && attempts < 40) {
            delay(50)
            attempts++
        }

        if (!ShortcutHelper.shortcutExists(context, userId)) {
            Log.e(TAG, "❌ Shortcut creation failed/timeout for $userName")
            throw IllegalStateException("Shortcut not created")
        }
    }

    fun syncShortcuts(context: Context) {
        scope.launch {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    Log.d(TAG, "🔄 Syncing shortcuts with active bubbles")
                    val managerBubbles = BubbleManager.getActiveBubbles()
                    managerBubbles.forEach { (uid, b) ->
                        ShortcutHelper.ensureShortcutForNotification(
                            context = context,
                            userId = uid,
                            userName = b.userName,
                            avatarUrl = b.avatarUrl
                        )
                    }
                    Log.d(TAG, "✅ Shortcuts synced: ${managerBubbles.size} shortcuts")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Sync shortcuts failed: $e")
            }
        }
    }

    fun getShortcutCount(context: Context): Int = ShortcutHelper.getShortcutCount(context)
    fun canCreateMoreShortcuts(context: Context): Boolean = ShortcutHelper.canCreateMoreShortcuts(context)
    fun isShortcutsSupported(): Boolean = ShortcutHelper.isShortcutsSupported()

    // ========================================
    // STATE QUERIES & STATS
    // ========================================

    fun isBubbleActive(userId: String): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            synchronized(activeBubbles) { activeBubbles.contains(userId) }
        } else {
            BubbleManager.isBubbleActive(userId)
        }
    }

    fun getActiveBubbleCount(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            synchronized(activeBubbles) { activeBubbles.size }
        } else {
            BubbleManager.getActiveBubbles().size
        }
    }

    fun getActiveBubbleUserIds(): Set<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            synchronized(activeBubbles) { activeBubbles.toSet() }
        } else {
            BubbleManager.getActiveBubbles().keys.toSet()
        }
    }

    fun getBubbleStats(): Map<String, Any> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            BubbleNotificationManager.getStats() + mapOf(
                "implementation" to "BubbleAPI",
                "activeBubbles"  to getActiveBubbleCount()
            )
        } else {
            mapOf(
                "implementation" to "WindowManager",
                "activeBubbles"  to BubbleManager.getActiveBubbles().size
            )
        }
    }

    fun logBubbleState() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            BubbleNotificationManager.logState()
        }

        Log.d(TAG, "Active bubble notifications: ${getActiveBubbleCount()}")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            synchronized(activeBubbles) {
                activeBubbles.forEach { userId ->
                    val count = BubbleNotificationManager.getMessageCount(userId)
                    val lastMsg = BubbleNotificationManager.getLastMessage(userId)
                    Log.d(TAG, "  - $userId: $count messages, last: ${lastMsg?.text?.take(30)}")
                }
            }
        }
    }

    // ========================================
    // AVATAR CACHE UTILITIES
    // ========================================

    fun getAvatarCacheStats(): Map<String, Any> = AvatarLoader.getCacheStats()

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
    // UTILITIES
    // ========================================

    fun shouldUseBubbleApi(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

    fun getImplementationType(): String {
        return if (shouldUseBubbleApi()) {
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
            syncState(context)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                preloadRecentAvatars(context)
            }
        } else {
            BubbleManager.onAppResumed(context)
        }
    }

    private fun syncState(context: Context) {
        scope.launch {
            try {
                val managerBubbles = BubbleManager.getActiveBubbles()
                val managerKeys = managerBubbles.keys

                synchronized(activeBubbles) {
                    activeBubbles.clear()
                    activeBubbles.addAll(managerKeys)
                }

                syncShortcuts(context)

                // ĐÃ SỬA: Restore (vẽ lại) bong bóng chat bằng Bubble API cho thiết bị Android 11+
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    managerBubbles.forEach { (uid, bubbleData) ->
                        val lastMsg = BubbleNotificationManager.getLastMessage(uid)?.text ?: ""
                        updateBubbleNotification(context, uid, bubbleData.userName, lastMsg, bubbleData.avatarUrl)
                    }
                }

                Log.d(TAG, "✅ State synced & restored: ${managerKeys.size} bubbles active")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Sync bubble state failed: $e")
            }
        }
    }

    fun cleanup(context: Context) {
        try {
            dismissAllBubbles(context)
            NotificationHelper.cleanup()
            ShortcutHelper.cleanup()

            synchronized(activeBubbles) { activeBubbles.clear() }
            isInitialized = false

            Log.d(TAG, "✅ Cleanup complete")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Cleanup failed: $e")
        }
    }
}
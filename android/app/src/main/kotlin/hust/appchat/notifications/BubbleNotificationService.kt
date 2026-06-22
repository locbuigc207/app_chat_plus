// android/app/src/main/kotlin/hust/appchat/notifications/BubbleNotificationService.kt
package hust.appchat.notifications

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import hust.appchat.shortcuts.AvatarLoader
import hust.appchat.shortcuts.ShortcutHelper
import kotlinx.coroutines.*
import java.util.concurrent.atomic.AtomicBoolean

@RequiresApi(Build.VERSION_CODES.R)
object BubbleNotificationService {

    internal const val TAG = "BubbleNotifService"

    // Use IO dispatcher for background operations like shortcut creation and cache access
    internal val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // [FIX P1]: Thread-safe initialization sử dụng AtomicBoolean thay vì @Volatile
    private val _isInitialized = AtomicBoolean(false)

    val isInitialized: Boolean
        get() = _isInitialized.get()

    // userId -> true means a Bubble-API notification exists for that user.
    internal val activeBubbles = LinkedHashSet<String>()

    // ========================================
    // INITIALIZATION
    // ========================================

    fun init(context: Context) {
        // [FIX P1]: Đảm bảo tính Atomicity (Thread-safe) tuyệt đối khi nhiều thread gọi init() cùng lúc
        if (!_isInitialized.compareAndSet(false, true)) {
            Log.d(TAG, "ℹ️ Already initialized")
            return
        }

        try {
            NotificationHelper.createNotificationChannel(context)

            if (ShortcutHelper.isShortcutsSupported()) {
                Log.d(TAG, "✅ Shortcuts supported")
                preloadRecentAvatars(context)
            } else {
                Log.w(TAG, "⚠️ Shortcuts not supported on this device")
            }

            Log.d(TAG, "✅ BubbleNotificationService initialized")
        } catch (e: Exception) {
            // Revert lại trạng thái nếu khởi tạo thất bại
            _isInitialized.set(false)
            Log.e(TAG, "❌ Initialization failed: $e")
        }
    }

    // ========================================
    // AVATAR PRELOADING
    // ========================================

    private fun preloadRecentAvatars(context: Context) {
        scope.launch {
            try {
                // Sử dụng activeBubbles thay vì BubbleManager cũ
                val currentKeys = synchronized(activeBubbles) { activeBubbles.toList() }
                if (currentKeys.isEmpty()) return@launch

                Log.d(TAG, "🔄 Preloading recent avatars...")
                val userList = currentKeys.mapNotNull { uid ->
                    val meta = BubbleNotificationManager.getMeta(uid)
                    if (meta != null) Pair(meta.second, meta.first) else null
                }

                if (userList.isNotEmpty()) {
                    AvatarLoader.preloadAvatarsBatch(context, userList)
                    Log.d(TAG, "✅ Preloaded ${userList.size} avatars")
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
        avatarUrl: String,
        messageType: BubbleNotificationManager.MessageType = BubbleNotificationManager.MessageType.TEXT
    ) {
        if (!isInitialized) {
            Log.w(TAG, "⚠️ Service not initialized, initializing now...")
            init(context)
        }

        scope.launch {
            try {
                Log.d(TAG, "🎈 Creating modern bubble notification: $userName")
                showModernBubble(context, userId, userName, message, avatarUrl, messageType)
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to create bubble notification: $e")
            }
        }
    }

    // Hàm dành riêng cho Background FCM
    fun showBubbleNotificationOnly(
        context: Context,
        userId: String,
        userName: String,
        message: String,
        avatarUrl: String,
        messageType: BubbleNotificationManager.MessageType = BubbleNotificationManager.MessageType.TEXT
    ) {
        if (!isInitialized) init(context)

        scope.launch {
            try {
                showModernBubble(context, userId, userName, message, avatarUrl, messageType)
            } catch (e: Exception) {
                Log.e(TAG, "❌ showBubbleNotificationOnly failed: $e")
                // Fallback nếu ngoại lệ cấp cao
                BubbleNotificationManager.addMessage(
                    context = context,
                    userId = userId,
                    userName = userName,
                    message = message,
                    avatarUrl = avatarUrl,
                    fromUser = false,
                    type = messageType
                )
            }
        }
    }

    private suspend fun showModernBubble(
        context: Context,
        userId: String,
        userName: String,
        message: String,
        avatarUrl: String,
        messageType: BubbleNotificationManager.MessageType
    ) {
        try {
            withTimeout(3000L) {
                AvatarLoader.loadAvatarIconAsync(context, avatarUrl, userName)
            }
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Failed to load avatar async, using fallback: $e")
        }

        try {
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
                type = messageType
            )

            synchronized(activeBubbles) { activeBubbles.add(userId) }
            Log.d(TAG, "✅ Modern bubble shown: $userName")

        } catch (e: IllegalStateException) {
            // Bắt lỗi ensureShortcut timeout/thất bại
            Log.e(TAG, "❌ ensureShortcut failed: ${e.message}. Fallback to normal notification.")

            // Gửi sự kiện lỗi qua Broadcast để MainActivity (hoặc Dart) có thể bắt và báo lỗi lên UI
            val intent = Intent("CHAT_BUBBLE_ERROR").apply {
                putExtra("userId", userId)
                putExtra("error", "Lỗi tạo bong bóng cho $userName: ${e.message}")
            }
            context.sendBroadcast(intent)

            // Fallback gửi notification thường
            postFallbackNotification(context, userId, userName, message)
        }
    }

    fun updateBubbleNotification(
        context: Context,
        userId: String,
        userName: String,
        message: String,
        avatarUrl: String,
        messageType: BubbleNotificationManager.MessageType = BubbleNotificationManager.MessageType.TEXT
    ) {
        scope.launch {
            try {
                if (isBubbleActive(userId)) {
                    try {
                        ensureShortcut(context, userId, userName, avatarUrl)
                        BubbleNotificationManager.addMessage(
                            context = context,
                            userId = userId,
                            userName = userName,
                            message = message,
                            avatarUrl = avatarUrl,
                            fromUser = false,
                            type = messageType
                        )
                        Log.d(TAG, "✅ Bubble notification updated: $userName")
                    } catch (e: IllegalStateException) {
                        Log.e(TAG, "❌ ensureShortcut failed on update: ${e.message}")
                        postFallbackNotification(context, userId, userName, message)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Update bubble notification failed: $e")
            }
        }
    }

    // ========================================
    // FALLBACK NOTIFICATION
    // ========================================

    private fun postFallbackNotification(context: Context, userId: String, userName: String, message: String) {
        try {
            val notificationId = userId.hashCode()

            // Intent mở app/mở chat
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra("userId", userId)
            }

            val pendingIntent = PendingIntent.getActivity(
                context,
                notificationId,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Giả định dùng chung channel với message, khai báo sẵn trong NotificationHelper
            val channelId = "chat_messages"

            val builder = NotificationCompat.Builder(context, channelId)
                // Sử dụng icon mặc định có sẵn (có thể đổi thành R.drawable.ic_notification của app bạn)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(userName)
                .setContentText(message)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setContentIntent(pendingIntent)
                .setAutoCancel(true)
                .addAction(0, "Mở chat", pendingIntent)

            NotificationManagerCompat.from(context).notify(notificationId, builder.build())
            Log.d(TAG, "✅ Fallback notification posted for $userName")
        } catch (e: SecurityException) {
            Log.e(TAG, "❌ Missing notification permission for fallback: $e")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to post fallback notification: $e")
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
                BubbleNotificationManager.clearHistory(userId)

                Log.d(TAG, "🗑️ Removing shortcut for: $userId")
                ShortcutHelper.removeShortcut(context, userId)
                NotificationHelper.cancelNotification(context, userId)

                synchronized(activeBubbles) { activeBubbles.remove(userId) }
                Log.d(TAG, "✅ Bubble dismissed: $userId")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Dismiss bubble failed: $e")
            }
        }
    }

    fun dismissAllBubbles(context: Context) {
        scope.launch {
            try {
                BubbleNotificationManager.clearAllHistory()

                Log.d(TAG, "🗑️ Removing all shortcuts")
                ShortcutHelper.removeAllShortcuts(context)
                NotificationHelper.cancelAllNotifications(context)

                synchronized(activeBubbles) { activeBubbles.clear() }
                Log.d(TAG, "✅ All bubbles dismissed")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Dismiss all bubbles failed: $e")
            }
        }
    }

    // ========================================
    // SHORTCUT UTILITIES
    // ========================================

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

        ShortcutHelper.createShortcutSuspend(context, userId, userName, avatarUrl)

        var attempts = 0
        while (!ShortcutHelper.shortcutExists(context, userId) && attempts < 20) {
            delay(100)
            attempts++
        }

        if (!ShortcutHelper.shortcutExists(context, userId)) {
            Log.e(TAG, "❌ Shortcut creation failed/timeout for $userName")
            throw IllegalStateException("Shortcut timeout (sau ~2s) - Không thể tạo shortcut kịp thời")
        }
    }

    fun syncShortcuts(context: Context) {
        scope.launch {
            try {
                Log.d(TAG, "🔄 Syncing shortcuts with active bubbles")
                val currentKeys = synchronized(activeBubbles) { activeBubbles.toList() }

                currentKeys.forEach { uid ->
                    val meta = BubbleNotificationManager.getMeta(uid)
                    if (meta != null) {
                        ShortcutHelper.ensureShortcutForNotification(
                            context = context,
                            userId = uid,
                            userName = meta.first,
                            avatarUrl = meta.second
                        )
                    }
                }
                Log.d(TAG, "✅ Shortcuts synced: ${currentKeys.size} shortcuts")
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
        return synchronized(activeBubbles) { activeBubbles.contains(userId) }
    }

    fun getActiveBubbleCount(): Int {
        return synchronized(activeBubbles) { activeBubbles.size }
    }

    fun getActiveBubbleUserIds(): Set<String> {
        return synchronized(activeBubbles) { activeBubbles.toSet() }
    }

    fun getBubbleStats(): Map<String, Any> {
        return BubbleNotificationManager.getStats() + mapOf(
            "implementation" to "BubbleAPI Native (Android 11+)",
            "activeBubbles"  to getActiveBubbleCount()
        )
    }

    fun logBubbleState() {
        BubbleNotificationManager.logState()
        Log.d(TAG, "Active bubble notifications: ${getActiveBubbleCount()}")
        synchronized(activeBubbles) {
            activeBubbles.forEach { userId ->
                val count = BubbleNotificationManager.getMessageCount(userId)
                val lastMsg = BubbleNotificationManager.getLastMessage(userId)
                Log.d(TAG, "  - $userId: $count messages, last: ${lastMsg?.text?.take(30)}")
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

    fun shouldUseBubbleApi(): Boolean = true

    fun getImplementationType(): String {
        return "Bubble API + Shortcuts + Avatar Cache + Message History"
    }

    // ========================================
    // LIFECYCLE
    // ========================================

    fun onAppPaused() {
        Log.d(TAG, "⏸️ App paused")
    }

    fun onAppResumed(context: Context) {
        Log.d(TAG, "▶️ App resumed")
        syncState(context)
        preloadRecentAvatars(context)
    }

    // KHÔNG clear activeBubbles. Đồng bộ dựa vào bộ nhớ hiện hành
    // và lấy Meta Data từ BubbleNotificationManager để tạo lại đúng tên và ảnh.
    private fun syncState(context: Context) {
        scope.launch {
            try {
                val currentKeys = synchronized(activeBubbles) { activeBubbles.toSet() }
                syncShortcuts(context)

                currentKeys.forEach { uid ->
                    val lastMsg = BubbleNotificationManager.getLastMessage(uid)
                    val meta = BubbleNotificationManager.getMeta(uid)

                    if (lastMsg != null && meta != null) {
                        updateBubbleNotification(
                            context = context,
                            userId = uid,
                            userName = meta.first,
                            message = lastMsg.text,
                            avatarUrl = meta.second,
                            messageType = lastMsg.type
                        )
                    }
                }

                Log.d(TAG, "✅ State synced: ${currentKeys.size} bubbles active")
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

            // [FIX P1]: Set lại giá trị AtomicBoolean
            _isInitialized.set(false)

            Log.d(TAG, "✅ Cleanup complete")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Cleanup failed: $e")
        }
    }
}
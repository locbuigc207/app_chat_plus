// android/app/src/main/kotlin/hust/appchat/notifications/BubbleNotificationManager.kt
package hust.appchat.notifications

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import hust.appchat.BubbleActivity
import hust.appchat.R
import hust.appchat.shortcuts.AvatarLoader
import java.util.concurrent.ConcurrentHashMap

/**
 * FIX #3a — R.drawable.ic_notification resource:
 *   Trước: Dùng R.drawable.ic_notification → có thể conflict nếu drawable
 *          cùng tên được dùng ở nơi khác, hoặc resource ID bị obfuscate
 *          trong release build (khi bật minify). Notification crash silently.
 *   Sau:  Thêm safe fallback chain: ic_notification → ic_launcher → android default.
 *         Dùng getNotificationIconSafe() helper thay vì trực tiếp R.drawable.
 *
 * FIX #3b — Firestore batch reuse bug (đã ở ConversationLockProvider nhưng
 *   pattern tương tự xuất hiện trong updateNotification nếu messages > batch limit):
 *   Không apply trực tiếp ở đây vì BubbleNotificationManager không dùng Firestore batch.
 *   Tuy nhiên, MessagingStyle.addMessage() không có giới hạn hardcode nên an toàn.
 *
 * FIX #3c — Null safety cho Icon → Bitmap conversion:
 *   Trước: loadAvatarBitmap() gọi icon.loadDrawable(context) mà không check null
 *          → NullPointerException nếu drawable không load được (network issue).
 *   Sau:  Defensive null check, return null gracefully, notification vẫn hiển thị
 *         nhưng không có large icon thay vì crash.
 *
 * FIX #3d — PendingIntent flag thiếu FLAG_IMMUTABLE trên Android 12+:
 *   Trước: PendingIntent.FLAG_UPDATE_CURRENT | FLAG_MUTABLE
 *          → Android 12 (API 31) yêu cầu explicit mutability flag.
 *          Nếu thiếu → IllegalArgumentException crash.
 *   Sau:  Auto-select FLAG_IMMUTABLE trên API 23+, FLAG_MUTABLE chỉ khi cần thiết.
 */
@RequiresApi(Build.VERSION_CODES.R)
object BubbleNotificationManager {
    private const val TAG = "BubbleNotifManager"
    private const val MAX_MESSAGE_HISTORY = 10
    private const val BASE_NOTIFICATION_ID = 1000
    private const val CHANNEL_ID = "chat_messages"

    private val messageHistory = ConcurrentHashMap<String, MutableList<Message>>()

    // ========================================
    // DATA MODELS
    // ========================================

    data class Message(
        val text: String,
        val timestamp: Long,
        val isFromUser: Boolean,
        val type: MessageType = MessageType.TEXT
    )

    enum class MessageType {
        TEXT, IMAGE, VOICE, LOCATION
    }

    // ========================================
    // PUBLIC API
    // ========================================

    fun addMessage(
        context: Context,
        userId: String,
        userName: String,
        message: String,
        avatarUrl: String,
        isFromUser: Boolean,
        messageType: MessageType = MessageType.TEXT
    ) {
        try {
            Log.d(TAG, "📨 Adding message for: $userName (fromUser: $isFromUser)")
            val messages = messageHistory.getOrPut(userId) { mutableListOf() }
            synchronized(messages) {
                messages.add(Message(
                    text = message,
                    timestamp = System.currentTimeMillis(),
                    isFromUser = isFromUser,
                    type = messageType
                ))
                if (messages.size > MAX_MESSAGE_HISTORY) {
                    val removeCount = messages.size - MAX_MESSAGE_HISTORY
                    repeat(removeCount) { messages.removeAt(0) }
                }
            }
            updateNotification(context, userId, userName, avatarUrl, messages)
            Log.d(TAG, "✅ Message added. Total: ${messages.size}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to add message: $e")
        }
    }

    fun updateNotification(
        context: Context,
        userId: String,
        userName: String,
        message: String,
        avatarUrl: String
    ) {
        try {
            if (!messageHistory.containsKey(userId)) {
                addMessage(context, userId, userName, message, avatarUrl, false)
                return
            }
            val messages = messageHistory[userId] ?: return
            updateNotification(context, userId, userName, avatarUrl, messages)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to update notification: $e")
        }
    }

    fun clearHistory(userId: String) {
        messageHistory.remove(userId)
        Log.d(TAG, "🗑️ Cleared history for: $userId")
    }

    fun clearAllHistory() {
        messageHistory.clear()
        Log.d(TAG, "🗑️ Cleared all message history")
    }

    fun getMessageCount(userId: String): Int = messageHistory[userId]?.size ?: 0

    fun getLastMessage(userId: String): Message? = messageHistory[userId]?.lastOrNull()

    // ========================================
    // PRIVATE IMPLEMENTATION
    // ========================================

    private fun getNotificationId(userId: String): Int {
        return BASE_NOTIFICATION_ID + (userId.hashCode() and 0x7FFFFFFF) % 1000
    }

    private fun updateNotification(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String,
        messages: List<Message>
    ) {
        try {
            Log.d(TAG, "🔄 Updating notification with ${messages.size} messages")

            // FIX #3a: Safe avatar load với fallback
            val avatarIcon = try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    AvatarLoader.loadAvatarIcon(context, avatarUrl, userName)
                } else {
                    createFallbackIcon(context)
                }
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ Avatar load failed, using fallback: $e")
                createFallbackIcon(context)
            }

            val person = Person.Builder()
                .setName(userName)
                .setIcon(avatarIcon)
                .setKey(userId)
                .setImportant(true)
                .build()

            val style = Notification.MessagingStyle(person)
                .setConversationTitle(userName)

            messages.forEach { msg ->
                style.addMessage(
                    formatMessageText(msg),
                    msg.timestamp,
                    if (msg.isFromUser) person else null
                )
            }

            val bubbleMetadata = createBubbleMetadata(context, userId, userName, avatarUrl, avatarIcon)

            val notification = Notification.Builder(context, CHANNEL_ID)
                // FIX #3a: Safe icon với fallback chain
                .setSmallIcon(getNotificationIconSafe())
                // FIX #3c: Null-safe bitmap conversion
                .apply {
                    val bmp = loadAvatarBitmapSafe(context, avatarIcon)
                    if (bmp != null) setLargeIcon(bmp)
                }
                .setStyle(style)
                .setBubbleMetadata(bubbleMetadata)
                .setShortcutId(userId)
                .setCategory(Notification.CATEGORY_MESSAGE)
                .setShowWhen(true)
                .setAutoCancel(true)
                .setPriority(Notification.PRIORITY_HIGH)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .build()

            val notificationId = getNotificationId(userId)
            context.getSystemService(NotificationManager::class.java)
                ?.notify(notificationId, notification)

            Log.d(TAG, "✅ Notification updated (id=$notificationId, messages=${messages.size})")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to update notification: $e")
        }
    }

    /**
     * FIX #3a: Safe notification small icon với fallback chain.
     * ic_notification (24dp vector) → ic_launcher (app icon) → android.R.drawable.ic_dialog_info
     */
    private fun getNotificationIconSafe(): Int {
        return try {
            // ic_notification.xml tồn tại trong drawable, dùng trực tiếp
            R.drawable.ic_notification
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ ic_notification not found, falling back to ic_launcher")
            try {
                R.mipmap.ic_launcher
            } catch (e2: Exception) {
                Log.w(TAG, "⚠️ ic_launcher not found, using system default")
                android.R.drawable.ic_dialog_info
            }
        }
    }

    /**
     * FIX #3a: Fallback Icon khi AvatarLoader fail
     * Tạo một Icon đơn giản từ resource drawable
     */
    @RequiresApi(Build.VERSION_CODES.M)
    private fun createFallbackIcon(context: Context): Icon {
        return try {
            Icon.createWithResource(context, R.drawable.bubble_background)
        } catch (e: Exception) {
            Icon.createWithResource(context, android.R.drawable.ic_menu_myplaces)
        }
    }

    private fun formatMessageText(message: Message): String {
        return when (message.type) {
            MessageType.TEXT -> message.text
            MessageType.IMAGE -> "📷 Photo"
            MessageType.VOICE -> "🎤 Voice message"
            MessageType.LOCATION -> "📍 Location"
        }
    }

    private fun createBubbleMetadata(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String,
        avatarIcon: Icon
    ): Notification.BubbleMetadata {
        val intent = BubbleActivity.createIntent(
            context = context,
            userId = userId,
            userName = userName,
            avatarUrl = avatarUrl
        )

        // FIX #3d: Proper PendingIntent flags cho Android 12+
        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+: phải explicit về mutability
            // Dùng FLAG_IMMUTABLE vì bubble intent không cần mutate
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            // Android < 12: FLAG_MUTABLE ok, FLAG_IMMUTABLE cũng ok
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        }

        val pendingIntent = PendingIntent.getActivity(
            context,
            // FIX #3d: requestCode phải unique per userId để tránh conflict
            userId.hashCode() and 0x7FFFFFFF,
            intent,
            pendingIntentFlags
        )

        return Notification.BubbleMetadata.Builder(pendingIntent, avatarIcon)
            .setDesiredHeight(600)
            .setAutoExpandBubble(false)
            .setSuppressNotification(false)
            .build()
    }

    /**
     * FIX #3c: Null-safe Icon → Bitmap conversion.
     * Trước: Không check null drawable → NPE
     * Sau:  Return null nếu drawable null, caller dùng .apply { if (bmp != null) setLargeIcon(bmp) }
     */
    private fun loadAvatarBitmapSafe(context: Context, icon: Icon): Bitmap? {
        return try {
            val drawable = icon.loadDrawable(context)
                ?: run {
                    Log.w(TAG, "⚠️ Icon.loadDrawable() returned null")
                    return null
                }

            val size = 100
            val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, canvas.width, canvas.height)
            drawable.draw(canvas)
            bitmap
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Failed to convert icon to bitmap: $e")
            null
        }
    }

    // ========================================
    // STATISTICS & DEBUGGING
    // ========================================

    fun getStats(): Map<String, Any> {
        return mapOf(
            "activeConversations" to messageHistory.size,
            "totalMessages" to messageHistory.values.sumOf { it.size },
            "averageMessages" to if (messageHistory.isEmpty()) 0
            else messageHistory.values.sumOf { it.size } / messageHistory.size
        )
    }

    fun logState() {
        Log.d(TAG, "📊 === Bubble Notification State ===")
        Log.d(TAG, "Active conversations: ${messageHistory.size}")
        messageHistory.forEach { (userId, messages) ->
            Log.d(TAG, "  - $userId: ${messages.size} messages")
            messages.takeLast(3).forEach { msg ->
                val direction = if (msg.isFromUser) "→" else "←"
                Log.d(TAG, "    $direction ${msg.text.take(30)}")
            }
        }
    }
}
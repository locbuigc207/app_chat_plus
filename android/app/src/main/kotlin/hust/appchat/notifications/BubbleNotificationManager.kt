// android/app/src/main/kotlin/hust/appchat/notifications/BubbleNotificationManager.kt
package hust.appchat.notifications

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.content.Intent
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
 * ✅ GIAI ĐOẠN 7: Bubble Notification Manager with Message History
 *
 * Features:
 * - Track message history per conversation (last 10 messages)
 * - Update notifications with MessagingStyle
 * - Support both sent and received messages
 * - Auto-cleanup old messages
 * - Thread-safe message storage
 */
@RequiresApi(Build.VERSION_CODES.R)
object BubbleNotificationManager {
    private const val TAG = "BubbleNotifManager"
    private const val MAX_MESSAGE_HISTORY = 10
    private const val BASE_NOTIFICATION_ID = 1000

    // ✅ FIX 2: Add CHANNEL_ID constant (required for notifications)
    private const val CHANNEL_ID = "chat_messages"

    // Thread-safe message storage
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
        TEXT,
        IMAGE,
        VOICE,
        LOCATION
    }

    // ========================================
    // PUBLIC API
    // ========================================

    /**
     * Add a new message to conversation and update notification
     *
     * @param context Android context
     * @param userId Conversation user ID
     * @param userName User display name
     * @param message Message content
     * @param avatarUrl User avatar URL
     * @param isFromUser true if message is from current user (sent), false if received
     * @param messageType Type of message (text, image, etc)
     */
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

            // Get or create message history
            val messages = messageHistory.getOrPut(userId) { mutableListOf() }

            // Add new message
            synchronized(messages) {
                messages.add(
                    Message(
                        text = message,
                        timestamp = System.currentTimeMillis(),
                        isFromUser = isFromUser,
                        type = messageType
                    )
                )

                // Keep only last MAX_MESSAGE_HISTORY messages
                if (messages.size > MAX_MESSAGE_HISTORY) {
                    val removeCount = messages.size - MAX_MESSAGE_HISTORY
                    repeat(removeCount) {
                        messages.removeAt(0)
                    }
                    Log.d(TAG, "🗑️ Trimmed to $MAX_MESSAGE_HISTORY messages")
                }
            }

            // Update notification
            updateNotification(context, userId, userName, avatarUrl, messages)

            Log.d(TAG, "✅ Message added. Total: ${messages.size}")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to add message: $e")
        }
    }

    /**
     * Update existing notification with message history
     */
    fun updateNotification(
        context: Context,
        userId: String,
        userName: String,
        message: String,
        avatarUrl: String
    ) {
        try {
            // If no history exists, create it with this message
            if (!messageHistory.containsKey(userId)) {
                addMessage(
                    context = context,
                    userId = userId,
                    userName = userName,
                    message = message,
                    avatarUrl = avatarUrl,
                    isFromUser = false
                )
                return
            }

            // Otherwise update with existing history
            val messages = messageHistory[userId] ?: return
            updateNotification(context, userId, userName, avatarUrl, messages)

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to update notification: $e")
        }
    }

    /**
     * Clear message history for user
     */
    fun clearHistory(userId: String) {
        messageHistory.remove(userId)
        Log.d(TAG, "🗑️ Cleared history for: $userId")
    }

    /**
     * Clear all message history
     */
    fun clearAllHistory() {
        messageHistory.clear()
        Log.d(TAG, "🗑️ Cleared all message history")
    }

    /**
     * Get message count for user
     */
    fun getMessageCount(userId: String): Int {
        return messageHistory[userId]?.size ?: 0
    }

    /**
     * Get last message for user
     */
    fun getLastMessage(userId: String): Message? {
        return messageHistory[userId]?.lastOrNull()
    }

    // ========================================
    // PRIVATE IMPLEMENTATION
    // ========================================

    private fun getNotificationIdForUser(userId: String): Int {
        // Generate consistent notification ID from userId
        return BASE_NOTIFICATION_ID + userId.hashCode() % 1000
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

            // Load avatar
            val avatarIcon = AvatarLoader.loadAvatarIcon(
                context = context,
                avatarUrl = avatarUrl,
                userName = userName
            )

            // Create Person
            val person = Person.Builder()
                .setName(userName)
                .setIcon(avatarIcon)
                .setKey(userId)
                .setImportant(true)
                .build()

            // Build MessagingStyle
            val style = Notification.MessagingStyle(person)
                .setConversationTitle(userName)

            // Add messages to style
            messages.forEach { msg ->
                val messageText = formatMessageText(msg)

                style.addMessage(
                    messageText,
                    msg.timestamp,
                    if (msg.isFromUser) person else null // null = other person
                )
            }

            // Get bubble metadata
            val bubbleMetadata = createBubbleMetadata(
                context = context,
                userId = userId,
                userName = userName,
                avatarUrl = avatarUrl,
                avatarIcon = avatarIcon
            )

            // Build notification
            val notification = Notification.Builder(context, CHANNEL_ID) // ✅ FIX 3: Use local CHANNEL_ID
                .setSmallIcon(R.drawable.ic_notification)
                .setLargeIcon(loadAvatarBitmap(context, avatarIcon))
                .setStyle(style)
                .setBubbleMetadata(bubbleMetadata)
                .setShortcutId(userId)
                .setCategory(Notification.CATEGORY_MESSAGE)
                .setShowWhen(true)
                .setAutoCancel(true)
                .setPriority(Notification.PRIORITY_HIGH)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .build()

            // Show notification
            val notificationId = getNotificationIdForUser(userId)
            val manager = context.getSystemService(NotificationManager::class.java)
            manager?.notify(notificationId, notification)

            Log.d(TAG, "✅ Notification updated with ${messages.size} messages")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to update notification: $e")
        }
    }

    /**
     * Format message text based on type
     */
    private fun formatMessageText(message: Message): String {
        return when (message.type) {
            MessageType.TEXT -> message.text
            MessageType.IMAGE -> "📷 Photo"
            MessageType.VOICE -> "🎤 Voice message"
            MessageType.LOCATION -> "📍 Location"
        }
    }

    /**
     * Create bubble metadata helper
     */
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

        val pendingIntent = PendingIntent.getActivity(
            context,
            userId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        return Notification.BubbleMetadata.Builder(pendingIntent, avatarIcon)
            .setDesiredHeight(600)
            .setAutoExpandBubble(false)
            .setSuppressNotification(false)
            .build()
    }

    /**
     * Load avatar as bitmap
     */
    private fun loadAvatarBitmap(
        context: Context,
        icon: Icon
    ): Bitmap? {
        return try {
            val drawable = icon.loadDrawable(context)
            val bitmap = Bitmap.createBitmap(100, 100, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable?.setBounds(0, 0, canvas.width, canvas.height)
            drawable?.draw(canvas)
            bitmap
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to convert icon to bitmap: $e")
            null
        }
    }

    // ========================================
    // STATISTICS
    // ========================================

    /**
     * Get conversation statistics
     */
    fun getStats(): Map<String, Any> {
        return mapOf(
            "activeConversations" to messageHistory.size,
            "totalMessages" to messageHistory.values.sumOf { it.size },
            "averageMessages" to if (messageHistory.isEmpty()) 0 else
                messageHistory.values.sumOf { it.size } / messageHistory.size
        )
    }

    /**
     * Log current state (for debugging)
     */
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
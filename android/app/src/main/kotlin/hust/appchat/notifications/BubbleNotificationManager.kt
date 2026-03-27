// android/app/src/main/kotlin/hust/appchat/notifications/BubbleNotificationManager.kt
package hust.appchat.notifications

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.Context
import android.content.res.Resources
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
 * FIXES APPLIED:
 *
 * FIX-A — getNotificationIconSafe() dùng Resources.getIdentifier() thực sự:
 *   Trước: try { R.drawable.ic_notification } catch — vô nghĩa vì
 *          R.drawable.ic_notification là compile-time constant, không throw.
 *   Sau:  Dùng Resources.getIdentifier() để check resource tồn tại runtime.
 *         Fallback chain: ic_notification → ic_launcher → android default.
 *
 * FIX-B — loadAvatarBitmapSafe() null-safe với drawable bounds check:
 *   Trước: drawable.setBounds() không check width/height > 0 → có thể
 *          tạo bitmap 0×0 gây IllegalArgumentException.
 *   Sau:  Kiểm tra drawable intrinsicWidth/Height, dùng fallback 100×100
 *         nếu không có kích thước hợp lệ.
 *
 * FIX-C — PendingIntent requestCode unique per userId:
 *   Đã đúng nhưng thêm abs() để tránh negative hashCode.
 *
 * FIX-D — Thread-safe message history với synchronized blocks:
 *   ConcurrentHashMap đã được dùng nhưng list bên trong vẫn cần sync.
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
            Log.d(TAG, "📨 Adding message for: $userName")
            val messages = messageHistory.getOrPut(userId) { mutableListOf() }
            // FIX-D: sync trên list riêng
            synchronized(messages) {
                messages.add(Message(
                    text       = message,
                    timestamp  = System.currentTimeMillis(),
                    isFromUser = isFromUser,
                    type       = messageType
                ))
                while (messages.size > MAX_MESSAGE_HISTORY) {
                    messages.removeAt(0)
                }
            }
            val snapshot: List<Message> = synchronized(messages) { messages.toList() }
            updateNotification(context, userId, userName, avatarUrl, snapshot)
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
            val snapshot: List<Message> = synchronized(messages) { messages.toList() }
            updateNotification(context, userId, userName, avatarUrl, snapshot)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to update notification: $e")
        }
    }

    fun clearHistory(userId: String) {
        messageHistory.remove(userId)
        Log.d(TAG, "🗑️ Cleared history: $userId")
    }

    fun clearAllHistory() {
        messageHistory.clear()
        Log.d(TAG, "🗑️ Cleared all history")
    }

    fun getMessageCount(userId: String): Int = messageHistory[userId]?.size ?: 0

    fun getLastMessage(userId: String): Message? {
        val messages = messageHistory[userId] ?: return null
        return synchronized(messages) { messages.lastOrNull() }
    }

    // ========================================
    // PRIVATE IMPLEMENTATION
    // ========================================

    private fun getNotificationId(userId: String): Int =
        BASE_NOTIFICATION_ID + (userId.hashCode() and 0x7FFFFFFF) % 1000

    private fun updateNotification(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String,
        messages: List<Message>
    ) {
        try {
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

            val bubbleMetadata = createBubbleMetadata(
                context, userId, userName, avatarUrl, avatarIcon)

            val notification = Notification.Builder(context, CHANNEL_ID)
                .setSmallIcon(getNotificationIconSafe(context))
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

            Log.d(TAG, "✅ Notification updated (id=$notificationId, count=${messages.size})")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to update notification: $e")
        }
    }

    /**
     * FIX-A: Dùng Resources.getIdentifier() để check resource tồn tại thực sự.
     * R.drawable.xxx là compile-time constant → không thể dùng try-catch để detect.
     */
    private fun getNotificationIconSafe(context: Context): Int {
        val res = context.resources
        val pkg = context.packageName

        // Thử ic_notification trước
        val icNotif = res.getIdentifier("ic_notification", "drawable", pkg)
        if (icNotif != 0) return icNotif

        Log.w(TAG, "⚠️ ic_notification not found, falling back to ic_launcher")

        // Fallback: ic_launcher từ mipmap
        val icLauncher = res.getIdentifier("ic_launcher", "mipmap", pkg)
        if (icLauncher != 0) return icLauncher

        Log.w(TAG, "⚠️ ic_launcher not found, using system default")
        return android.R.drawable.ic_dialog_info
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun createFallbackIcon(context: Context): Icon {
        return try {
            // FIX-A: dùng getNotificationIconSafe thay vì hardcode R.drawable
            val iconRes = getNotificationIconSafe(context)
            Icon.createWithResource(context, iconRes)
        } catch (e: Exception) {
            Icon.createWithResource(context, android.R.drawable.ic_menu_myplaces)
        }
    }

    private fun formatMessageText(message: Message): String = when (message.type) {
        MessageType.TEXT     -> message.text
        MessageType.IMAGE    -> "📷 Photo"
        MessageType.VOICE    -> "🎤 Voice message"
        MessageType.LOCATION -> "📍 Location"
    }

    private fun createBubbleMetadata(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String,
        avatarIcon: Icon
    ): Notification.BubbleMetadata {
        val intent = BubbleActivity.createIntent(
            context   = context,
            userId    = userId,
            userName  = userName,
            avatarUrl = avatarUrl
        )

        // FIX-C: abs() để đảm bảo requestCode không âm
        val requestCode = Math.abs(userId.hashCode()) % Int.MAX_VALUE

        val pendingIntentFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        }

        val pendingIntent = PendingIntent.getActivity(
            context, requestCode, intent, pendingIntentFlags)

        return Notification.BubbleMetadata.Builder(pendingIntent, avatarIcon)
            .setDesiredHeight(600)
            .setAutoExpandBubble(false)
            .setSuppressNotification(false)
            .build()
    }

    /**
     * FIX-B: Null-safe + bounds check trước khi tạo Bitmap.
     */
    private fun loadAvatarBitmapSafe(context: Context, icon: Icon): Bitmap? {
        return try {
            val drawable = icon.loadDrawable(context) ?: run {
                Log.w(TAG, "⚠️ Icon.loadDrawable() returned null")
                return null
            }

            // FIX-B: check kích thước hợp lệ
            val w = if (drawable.intrinsicWidth  > 0) drawable.intrinsicWidth  else 100
            val h = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 100

            val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
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
    // STATS & DEBUG
    // ========================================

    fun getStats(): Map<String, Any> = mapOf(
        "activeConversations" to messageHistory.size,
        "totalMessages"       to messageHistory.values.sumOf { it.size },
        "averageMessages"     to if (messageHistory.isEmpty()) 0
        else messageHistory.values.sumOf { it.size } / messageHistory.size
    )

    fun logState() {
        Log.d(TAG, "📊 === Bubble Notification State ===")
        Log.d(TAG, "Active conversations: ${messageHistory.size}")
        messageHistory.forEach { (userId, messages) ->
            val snapshot = synchronized(messages) { messages.takeLast(3).toList() }
            Log.d(TAG, "  - $userId: ${messages.size} messages")
            snapshot.forEach { msg ->
                val dir = if (msg.isFromUser) "→" else "←"
                Log.d(TAG, "    $dir ${msg.text.take(30)}")
            }
        }
    }
}
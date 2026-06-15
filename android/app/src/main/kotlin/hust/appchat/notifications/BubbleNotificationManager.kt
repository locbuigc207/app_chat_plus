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
import hust.appchat.shortcuts.AvatarLoader
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList

@RequiresApi(Build.VERSION_CODES.R)
object BubbleNotificationManager {

    private const val TAG              = "BubbleNotifManager"
    private const val MAX_HISTORY      = 12
    private const val BASE_ID          = 2_000
    private const val CHANNEL_MESSAGES = "chat_messages"

    private val history      = ConcurrentHashMap<String, CopyOnWriteArrayList<Message>>()
    private val expandedUsers = ConcurrentHashMap.newKeySet<String>()

    data class Message(
        val text     : String,
        val timestamp: Long,
        val fromUser : Boolean,
        val type     : MessageType = MessageType.TEXT,
    )

    enum class MessageType { TEXT, IMAGE, VOICE, LOCATION }

    // ═════════════════════════════════════════════════════════════════════
    // PUBLIC API
    // ═════════════════════════════════════════════════════════════════════

    fun addMessage(
        context  : Context,
        userId   : String,
        userName : String,
        message  : String,
        avatarUrl: String,
        fromUser : Boolean,
        type     : MessageType = MessageType.TEXT,
    ): Int {
        val msgs = history.getOrPut(userId) { CopyOnWriteArrayList() }
        msgs.add(Message(message, System.currentTimeMillis(), fromUser, type))
        while (msgs.size > MAX_HISTORY) msgs.removeAt(0)

        val notifId = notifId(userId)
        postNotification(context, userId, userName, avatarUrl, msgs.toList(), notifId)
        return notifId
    }

    fun updateNotification(
        context  : Context,
        userId   : String,
        userName : String,
        message  : String,
        avatarUrl: String,
    ) {
        if (!history.containsKey(userId)) {
            addMessage(context, userId, userName, message, avatarUrl, fromUser = false)
            return
        }
        val msgs = history[userId] ?: return
        postNotification(context, userId, userName, avatarUrl, msgs.toList(), notifId(userId))
    }

    fun markExpanded(userId: String)  { expandedUsers.add(userId) }
    fun markCollapsed(userId: String) { expandedUsers.remove(userId) }
    fun isExpanded(userId: String)    = expandedUsers.contains(userId)

    fun clearHistory(userId: String) {
        history.remove(userId)
        expandedUsers.remove(userId)
        Log.d(TAG, "🗑️ History cleared: $userId")
    }

    fun clearAllHistory() {
        history.clear()
        expandedUsers.clear()
    }

    fun getMessageCount(userId: String) = history[userId]?.size ?: 0
    fun getLastMessage(userId: String)  = history[userId]?.lastOrNull()

    fun getStats(): Map<String, Any> = mapOf(
        "conversations" to history.size,
        "totalMessages" to history.values.sumOf { it.size },
        "expandedCount" to expandedUsers.size,
    )

    fun logState() {
        Log.d(TAG, "📊 BubbleNotifManager — ${history.size} conversations")
        history.forEach { (uid, msgs) ->
            Log.d(TAG, "  $uid: ${msgs.size} msg — last: ${msgs.lastOrNull()?.text?.take(30)}")
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // PRIVATE IMPLEMENTATION
    // ═════════════════════════════════════════════════════════════════════

    private fun postNotification(
        context  : Context,
        userId   : String,
        userName : String,
        avatarUrl: String,
        messages : List<Message>,
        notifId  : Int,
    ) {
        try {
            val avatarIcon = safeLoadIcon(context, avatarUrl, userName)
            val person     = buildPerson(userName, userId, avatarIcon)
            val style      = buildStyle(person, userName, messages)
            val bubbleMeta = buildBubble(context, userId, userName, avatarUrl, avatarIcon)

            val notif = Notification.Builder(context, CHANNEL_MESSAGES)
                .setSmallIcon(notifIconRes(context))
                .setLargeIcon(iconToBitmap(context, avatarIcon))
                .setStyle(style)
                .setBubbleMetadata(bubbleMeta)
                .setShortcutId(userId)
                .setCategory(Notification.CATEGORY_MESSAGE)
                .setPriority(Notification.PRIORITY_HIGH)
                .setShowWhen(true)
                .setAutoCancel(false)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .build()

            context.getSystemService(NotificationManager::class.java)
                ?.notify(notifId, notif)

            Log.d(TAG, "✅ Notification posted id=$notifId user=$userName msgs=${messages.size}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ postNotification: $e")
        }
    }

    private fun buildPerson(name: String, key: String, icon: Icon): Person =
        Person.Builder()
            .setName(name)
            .setKey(key)
            .setIcon(icon)
            .setImportant(true)
            .build()

    private fun buildStyle(
        person  : Person,
        title   : String,
        messages: List<Message>,
    ): Notification.MessagingStyle {
        val style = Notification.MessagingStyle(person).setConversationTitle(title)
        messages.forEach { m ->
            style.addMessage(
                formatText(m),
                m.timestamp,
                if (!m.fromUser) person else null,
            )
        }
        return style
    }

    private fun buildBubble(
        context  : Context,
        userId   : String,
        userName : String,
        avatarUrl: String,
        icon     : Icon,
    ): Notification.BubbleMetadata {
        val intent = BubbleActivity.createIntent(context, userId, userName, avatarUrl)

        // ĐÃ SỬA: Dùng toán tử bitwise AND để tránh ngoại lệ Math.abs(Int.MIN_VALUE) gây tràn số âm
        val reqCode = (userId.hashCode() and 0x7FFFFFFF)

        // FIX: bubble PendingIntent BẮT BUỘC phải MUTABLE
        // FLAG_IMMUTABLE khiến Android reject toàn bộ bubble notification
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                    PendingIntent.FLAG_MUTABLE
                else 0

        val pi = PendingIntent.getActivity(context, reqCode, intent, flags)

        // FIX: dùng adaptive bitmap icon thay vì raw bitmap
        // Bubble API hoạt động tốt nhất với TYPE_URI hoặc TYPE_URI_ADAPTIVE_BITMAP
        // Fallback: wrap bitmap thành adaptive bitmap
        val bubbleIcon = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val bmp = iconToBitmap(context, icon)
            if (bmp != null) Icon.createWithAdaptiveBitmap(bmp) else icon
        } else icon

        return Notification.BubbleMetadata.Builder(pi, bubbleIcon)
            .setDesiredHeight(640)
            .setAutoExpandBubble(false)
            .setSuppressNotification(isExpanded(userId))
            .build()
    }

    private fun formatText(m: Message) = when (m.type) {
        MessageType.TEXT     -> m.text
        MessageType.IMAGE    -> "📷 Hình ảnh"
        MessageType.VOICE    -> "🎤 Tin nhắn thoại"
        MessageType.LOCATION -> "📍 Vị trí"
    }

    // ─── Icon helpers ──────────────────────────────────────────────────────

    private fun notifIconRes(ctx: Context): Int {
        val r   = ctx.resources
        val pkg = ctx.packageName
        val id  = r.getIdentifier("ic_notification", "drawable", pkg)
        if (id != 0) return id
        val lc = r.getIdentifier("ic_launcher", "mipmap", pkg)
        if (lc != 0) return lc
        Log.w(TAG, "⚠️ ic_notification not found; using android default")
        return android.R.drawable.ic_dialog_info
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun safeLoadIcon(ctx: Context, url: String, name: String): Icon {
        return try {
            AvatarLoader.loadAvatarIcon(ctx, url, name)
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Avatar icon load failed: $e")
            fallbackIcon(ctx)
        }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun fallbackIcon(ctx: Context): Icon =
        Icon.createWithResource(ctx, notifIconRes(ctx))

    private fun iconToBitmap(ctx: Context, icon: Icon): Bitmap? {
        return try {
            val drawable = icon.loadDrawable(ctx) ?: return null
            val w = if (drawable.intrinsicWidth  > 0) drawable.intrinsicWidth  else 100
            val h = if (drawable.intrinsicHeight > 0) drawable.intrinsicHeight else 100
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bmp)
            drawable.setBounds(0, 0, w, h)
            drawable.draw(canvas)
            bmp
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ iconToBitmap failed: $e")
            null
        }
    }

    // ĐÃ SỬA: Đồng bộ cách tính notifId bằng bitwise AND để không bị lệch ID khi gọi NotificationHelper.cancelNotification()
    private fun notifId(userId: String) =
        BASE_ID + ((userId.hashCode() and 0x7FFFFFFF) % 1_000)
}
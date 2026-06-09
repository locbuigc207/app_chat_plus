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
import hust.appchat.shortcuts.AvatarLoader
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList

/**
 * BubbleNotificationManager — Android 11+ Bubble API.
 *
 * Architecture & Fixes:
 * • FIX-A (Resource Safety): getNotificationIconSafe() uses Resources.getIdentifier()
 * at runtime to avoid try-catch on compile-time constants.
 * • FIX-B (Bitmap Bounds): iconToBitmap() guards against zero-size intrinsic
 * dimensions, producing a 100×100 fallback bitmap to prevent crashes.
 * • FIX-C (PendingIntent): requestCode uses Math.abs(hashCode) to avoid negative IDs.
 * • FIX-D (Thread-Safety): Message history uses CopyOnWriteArrayList for lock-free,
 * safe iteration across threads.
 * • FIX-E (Smart Suppression): Tracks expanded state via `expandedUsers` to dynamically
 * suppress Heads-Up notifications if the conversation bubble is already open.
 */
@RequiresApi(Build.VERSION_CODES.R)
object BubbleNotificationManager {

    private const val TAG                = "BubbleNotifManager"
    private const val MAX_HISTORY        = 12
    private const val BASE_ID            = 2_000
    private const val CHANNEL_MESSAGES   = "chat_messages"

    // Thread-safe message history tracking
    private val history = ConcurrentHashMap<String, CopyOnWriteArrayList<Message>>()

    // Users whose bubble window is currently expanded
    private val expandedUsers = ConcurrentHashMap.newKeySet<String>()

    // ─── Data models ──────────────────────────────────────────────────────

    data class Message(
        val text      : String,
        val timestamp : Long,
        val fromUser  : Boolean,
        val type      : MessageType = MessageType.TEXT,
    )

    enum class MessageType { TEXT, IMAGE, VOICE, LOCATION }

    // ═════════════════════════════════════════════════════════════════════
    // PUBLIC API
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Add an incoming message and refresh the bubble notification.
     * Returns the notification ID for the conversation.
     */
    fun addMessage(
        context   : Context,
        userId    : String,
        userName  : String,
        message   : String,
        avatarUrl : String,
        fromUser  : Boolean,
        type      : MessageType = MessageType.TEXT,
    ): Int {
        val msgs = history.getOrPut(userId) { CopyOnWriteArrayList() }
        msgs.add(Message(message, System.currentTimeMillis(), fromUser, type))

        // Trim to max history size
        while (msgs.size > MAX_HISTORY) msgs.removeAt(0)

        val notifId = notifId(userId)
        postNotification(context, userId, userName, avatarUrl, msgs.toList(), notifId)
        return notifId
    }

    fun updateNotification(
        context   : Context,
        userId    : String,
        userName  : String,
        message   : String,
        avatarUrl : String,
    ) {
        if (!history.containsKey(userId)) {
            addMessage(context, userId, userName, message, avatarUrl, fromUser = false)
            return
        }
        val msgs = history[userId] ?: return
        postNotification(context, userId, userName, avatarUrl, msgs.toList(), notifId(userId))
    }

    fun markExpanded(userId: String)   { expandedUsers.add(userId) }
    fun markCollapsed(userId: String)  { expandedUsers.remove(userId) }
    fun isExpanded(userId: String)     = expandedUsers.contains(userId)

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
        context   : Context,
        userId    : String,
        userName  : String,
        avatarUrl : String,
        messages  : List<Message>,
        notifId   : Int,
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
        context   : Context,
        userId    : String,
        userName  : String,
        avatarUrl : String,
        icon      : Icon,
    ): Notification.BubbleMetadata {
        val intent = BubbleActivity.createIntent(context, userId, userName, avatarUrl)

        // FIX-C: Math.abs() to prevent negative request codes
        val reqCode = Math.abs(userId.hashCode()) % Int.MAX_VALUE
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE

        val pi = PendingIntent.getActivity(context, reqCode, intent, flags)

        return Notification.BubbleMetadata.Builder(pi, icon)
            .setDesiredHeight(640)
            .setAutoExpandBubble(false)
            // Suppress heads-up banner when bubble window is already open
            .setSuppressNotification(isExpanded(userId))
            .build()
    }

    private fun formatText(m: Message) = when (m.type) {
        MessageType.TEXT     -> m.text
        MessageType.IMAGE    -> "📷 Hình ảnh"
        MessageType.VOICE    -> "🎤 Tin nhắn thoại"
        MessageType.LOCATION -> "📍 Vị trí"
    }

    // ─── Icon helpers ─────────────────────────────────────────────────────

    /** FIX-A: Runtime resource check via getIdentifier() */
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

    /** FIX-B: Guard against zero-size intrinsic dimensions */
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

    private fun notifId(userId: String) =
        BASE_ID + (Math.abs(userId.hashCode()) % 1_000)
}
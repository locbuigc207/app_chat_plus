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
import hust.appchat.shortcuts.ShortcutHelper
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArrayList

@RequiresApi(Build.VERSION_CODES.R)
object BubbleNotificationManager {

    private const val TAG              = "BubbleNotifManager"
    private const val MAX_HISTORY      = 12
    private const val CHANNEL_MESSAGES = "chat_messages"

    // Tăng base ID và dải chia dư để dứt điểm vụ trùng lặp Notification ID
    private const val BASE_ID          = 10_000

    private val history       = ConcurrentHashMap<String, CopyOnWriteArrayList<Message>>()
    private val expandedUsers = ConcurrentHashMap.newKeySet<String>()

    // [GIẢI QUYẾT LỖI P0]: Thêm map lưu trữ Meta Data để giải quyết triệt để lỗi
    // quên tên (userName) và ảnh (avatarUrl) trên các phiên bản Android 11+
    private val conversationMeta = ConcurrentHashMap<String, Pair<String, String>>() // userId -> (userName, avatarUrl)

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

    // [GIẢI QUYẾT LỖI P0]: Các hàm truy xuất và lưu trữ Meta Data
    fun rememberMeta(userId: String, userName: String, avatarUrl: String) {
        conversationMeta[userId] = Pair(userName, avatarUrl)
    }

    fun getMeta(userId: String): Pair<String, String>? = conversationMeta[userId]

    fun addMessage(
        context  : Context,
        userId   : String,
        userName : String,
        message  : String,
        avatarUrl: String,
        fromUser : Boolean,
        type     : MessageType = MessageType.TEXT,
    ): Int {
        // Lưu metadata ngay khi có tin nhắn mới để các luồng update sau (syncState) có dữ liệu để dùng
        rememberMeta(userId, userName, avatarUrl)

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

        // Cập nhật lại metadata phòng trường hợp người dùng đổi tên/avatar
        rememberMeta(userId, userName, avatarUrl)

        val msgs = history[userId] ?: return
        postNotification(context, userId, userName, avatarUrl, msgs.toList(), notifId(userId))
    }

    fun markExpanded(userId: String)  { expandedUsers.add(userId) }
    fun markCollapsed(userId: String) { expandedUsers.remove(userId) }
    fun isExpanded(userId: String)    = expandedUsers.contains(userId)

    fun clearHistory(userId: String) {
        history.remove(userId)
        expandedUsers.remove(userId)
        conversationMeta.remove(userId) // [GIẢI QUYẾT LỖI P2]: Dọn dẹp metadata để tránh leak memory
        Log.d(TAG, "🗑️ History cleared: $userId")
    }

    fun clearAllHistory() {
        history.clear()
        expandedUsers.clear()
        conversationMeta.clear()
    }

    fun getMessageCount(userId: String) = history[userId]?.size ?: 0
    fun getLastMessage(userId: String)  = history[userId]?.lastOrNull()

    fun getStats(): Map<String, Any> = mapOf(
        "conversations" to history.size,
        "totalMessages" to history.values.sumOf { it.size },
        "expandedCount" to expandedUsers.size,
        "metaCount"     to conversationMeta.size
    )

    fun logState() {
        Log.d(TAG, "📊 BubbleNotifManager — ${history.size} conversations")
        history.forEach { (uid, msgs) ->
            Log.d(TAG, "  $uid: ${msgs.size} msg — last: ${msgs.lastOrNull()?.text?.take(30)}")
        }
    }

    // [GIẢI QUYẾT LỖI P0]: Đổi thành hàm public để NotificationHelper có thể gọi chung,
    // loại bỏ tình trạng có 2 công thức tính Notification ID chạy song song
    fun notifId(userId: String): Int =
        BASE_ID + ((userId.hashCode() and 0x7FFFFFFF) % 50_000)

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

            val builder = Notification.Builder(context, CHANNEL_MESSAGES)
                .setSmallIcon(notifIconRes(context))
                .setLargeIcon(iconToBitmap(context, avatarIcon))
                .setStyle(style)
                .setShortcutId(userId)
                .setCategory(Notification.CATEGORY_MESSAGE)
                .setPriority(Notification.PRIORITY_HIGH)
                .setShowWhen(true)
                .setAutoCancel(false)
                .setVisibility(Notification.VISIBILITY_PUBLIC)

            // [SỬA LỖI]: Log cảnh báo rõ ràng khi bubbleMeta là null do shortcut chưa kịp tạo,
            // đồng thời vẫn post Notification dạng thường để người dùng không bị mất tin nhắn.
            if (bubbleMeta != null) {
                builder.setBubbleMetadata(bubbleMeta)
            } else {
                Log.w(TAG, "⚠️ CẢNH BÁO: buildBubble() trả về null cho userId=$userId. Shortcut có thể chưa được tạo kịp. Đang fallback gửi notification thường để tránh mất thông báo!")
            }

            val notif = builder.build()

            context.getSystemService(NotificationManager::class.java)
                ?.notify(notifId, notif)

            Log.d(TAG, "✅ Notification posted id=$notifId user=$userName msgs=${messages.size} (isBubble: ${bubbleMeta != null})")
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
    ): Notification.BubbleMetadata? {

        // Kiểm tra kỹ shortcut trước khi build BubbleMetadata framework API.
        // Trên Android 15/16, shortcut bắt buộc phải được publish trước.
        if (!ShortcutHelper.shortcutExists(context, userId)) {
            Log.w(TAG, "⚠️ Shortcut missing for $userId — deferring bubble metadata")
            return null
        }

        val intent = BubbleActivity.createIntent(context, userId, userName, avatarUrl)
        val reqCode = (userId.hashCode() and 0x7FFFFFFF)

        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                    PendingIntent.FLAG_MUTABLE
                else 0

        val pi = PendingIntent.getActivity(context, reqCode, intent, flags)

        val bubbleIcon = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val bmp = iconToBitmap(context, icon)
            if (bmp != null) Icon.createWithAdaptiveBitmap(bmp) else icon
        } else icon

        // Safety check trước khi build để ngăn crash ngầm nếu Icon fallback thất bại
        if (bubbleIcon == null) {
            Log.e(TAG, "❌ Bubble icon null — abort bubble metadata")
            return null
        }

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

    // [GIẢI QUYẾT LỖI P1]: Hàm này có thể được tách ra Util chung trong tương lai.
    // Hiện tại giữ ở dạng private scope để đảm bảo an toàn biên dịch cho file này.
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
}
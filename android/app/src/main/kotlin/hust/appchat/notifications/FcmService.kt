// android/app/src/main/kotlin/hust/appchat/notifications/FcmService.kt
package hust.appchat.notifications

import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import hust.appchat.shortcuts.ShortcutHelper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.Collections

@RequiresApi(Build.VERSION_CODES.R)
class FcmService : FirebaseMessagingService() {

    companion object {
        private const val TAG = "FcmService"

        // Well-known data payload keys — must match server-side
        private const val KEY_SENDER_ID    = "senderId"
        private const val KEY_SENDER_NAME  = "senderName"
        private const val KEY_AVATAR_URL   = "avatarUrl"
        private const val KEY_MESSAGE      = "message"
        private const val KEY_MESSAGE_TYPE = "messageType"
        private const val KEY_TOKEN_FIELD  = "fcmToken"     // Firestore field name

        // Message types that match BubbleNotificationManager.MessageType
        private const val TYPE_TEXT     = "text"
        private const val TYPE_IMAGE    = "image"
        private const val TYPE_VOICE    = "voice"
        private const val TYPE_LOCATION = "location"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // [SỬA LỖI P1]: Bộ đệm LRU lưu 50 messageId gần nhất để chống FCM redeliver (gửi lặp)
    private val processedMessageIds = Collections.newSetFromMap(
        object : java.util.LinkedHashMap<String, Boolean>(50, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Boolean>?): Boolean {
                return size > 50
            }
        }
    )

    // ═════════════════════════════════════════════════════════════════════
    // FCM CALLBACKS
    // ═════════════════════════════════════════════════════════════════════

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)

        val msgId = message.messageId
        Log.d(TAG, "📨 FCM received — id: $msgId, from: ${message.from}")

        // Kiểm tra và loại bỏ tin nhắn trùng lặp
        if (msgId != null) {
            synchronized(processedMessageIds) {
                if (!processedMessageIds.add(msgId)) {
                    Log.d(TAG, "♻️ Duplicate message ignored: $msgId")
                    return
                }
            }
        }

        // Phân loại xử lý payload
        val data = message.data
        if (data.isEmpty()) {
            handleNotificationMessage(message)
            return
        }

        handleDataMessage(data, message)
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        Log.d(TAG, "🔑 FCM token refreshed: ${token.take(20)}…")
        persistTokenToFirestore(token)
    }

    // ═════════════════════════════════════════════════════════════════════
    // MESSAGE HANDLERS
    // ═════════════════════════════════════════════════════════════════════

    private fun handleDataMessage(
        data: Map<String, String>,
        raw: RemoteMessage,
    ) {
        val senderId   = data[KEY_SENDER_ID]   ?: run { logMissing(KEY_SENDER_ID); return }
        val senderName = data[KEY_SENDER_NAME] ?: raw.notification?.title ?: "Unknown"
        val avatarUrl  = data[KEY_AVATAR_URL]  ?: ""
        val body       = data[KEY_MESSAGE]     ?: raw.notification?.body  ?: ""
        val typeStr    = data[KEY_MESSAGE_TYPE] ?: TYPE_TEXT

        Log.d(TAG, "📩 Data message — sender: $senderName, type: $typeStr, body: ${body.take(40)}")

        val preview = formatPreview(body, typeStr)

        // [SỬA LỖI P0]: Gọi hàm bóc tách Type thực sự để truyền xuống dưới thay vì bỏ quên
        val resolvedType = resolveType(typeStr)

        scope.launch {
            try {
                // 1. Đảm bảo service đã được khởi tạo (trường hợp app bị kill lạnh)
                BubbleNotificationService.init(applicationContext)

                // 2. Tạo hoặc làm mới Shortcut cho Bubble API
                if (ShortcutHelper.isShortcutsSupported()) {
                    ShortcutHelper.ensureShortcutForNotification(
                        applicationContext, senderId, senderName, avatarUrl)
                }

                // 3. Đẩy thông báo Bubble (Luôn dùng showBubbleNotificationOnly vì FCM chạy ngầm)
                BubbleNotificationService.showBubbleNotificationOnly(
                    context     = applicationContext,
                    userId      = senderId,
                    userName    = senderName,
                    message     = preview,
                    avatarUrl   = avatarUrl,
                    messageType = resolvedType // Truyền đúng Type để hiển thị "Hình ảnh", "Voice" thay vì Text rỗng
                )

                Log.d(TAG, "✅ Bubble notification request dispatched for $senderName")

            } catch (e: Exception) {
                Log.e(TAG, "❌ handleDataMessage: $e")
                showFallbackNotification(senderId, senderName, preview)
            }
        }
    }

    /**
     * Called when a purely notification message arrives and the app is in the
     * foreground. The system already shows a heads-up banner.
     */
    private fun handleNotificationMessage(raw: RemoteMessage) {
        val notif  = raw.notification ?: return
        val title  = notif.title ?: return
        val body   = notif.body  ?: ""
        Log.d(TAG, "🔔 Notification message (Foreground): $title — $body")

        // Ghi chú: Nếu backend gửi payload có định dạng đúng (data payload),
        // nó sẽ không đi vào luồng thuần notification này.
    }

    // ═════════════════════════════════════════════════════════════════════
    // TOKEN PERSISTENCE
    // ═════════════════════════════════════════════════════════════════════

    private fun persistTokenToFirestore(token: String) {
        scope.launch {
            try {
                val db   = com.google.firebase.firestore.FirebaseFirestore.getInstance()
                val auth = com.google.firebase.auth.FirebaseAuth.getInstance()
                val uid  = auth.currentUser?.uid ?: return@launch

                db.collection("users").document(uid)
                    .update(KEY_TOKEN_FIELD, token)
                    .addOnSuccessListener {
                        Log.d(TAG, "✅ FCM token saved to Firestore")
                    }
                    .addOnFailureListener { e ->
                        Log.e(TAG, "❌ Token save failed: $e")
                    }
            } catch (e: Exception) {
                Log.e(TAG, "❌ persistTokenToFirestore: $e")
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // FALLBACK NOTIFICATION
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Last-resort plain notification when the full bubble pipeline fails.
     */
    private fun showFallbackNotification(
        userId: String, userName: String, message: String,
    ) {
        try {
            val nm = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager

            val notif = androidx.core.app.NotificationCompat
                .Builder(applicationContext, NotificationHelper.CHANNEL_MESSAGES)
                .setContentTitle(userName)
                .setContentText(message)
                .setSmallIcon(hust.appchat.R.drawable.ic_notification)
                .setPriority(androidx.core.app.NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .build()

            nm.notify(userId.hashCode(), notif)
            Log.d(TAG, "✅ Fallback notification shown for $userName")
        } catch (e: Exception) {
            Log.e(TAG, "❌ showFallbackNotification: $e")
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═════════════════════════════════════════════════════════════════════

    private fun resolveType(typeStr: String): BubbleNotificationManager.MessageType =
        when (typeStr.lowercase()) {
            TYPE_IMAGE    -> BubbleNotificationManager.MessageType.IMAGE
            TYPE_VOICE    -> BubbleNotificationManager.MessageType.VOICE
            TYPE_LOCATION -> BubbleNotificationManager.MessageType.LOCATION
            else          -> BubbleNotificationManager.MessageType.TEXT
        }

    private fun formatPreview(body: String, typeStr: String): String =
        when (typeStr.lowercase()) {
            TYPE_IMAGE    -> "📷 Hình ảnh"
            TYPE_VOICE    -> "🎤 Tin nhắn thoại"
            TYPE_LOCATION -> "📍 Vị trí"
            else          -> if (body.length > 80) "${body.take(80)}…" else body
        }

    private fun logMissing(key: String) {
        Log.w(TAG, "⚠️ Missing required payload key: $key")
    }

    override fun onDestroy() {
        super.onDestroy()
    }
}
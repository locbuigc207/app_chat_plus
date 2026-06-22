// android/app/src/main/kotlin/hust/appchat/notifications/FcmService.kt
package hust.appchat.notifications

import android.os.Build
import android.os.PowerManager
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
        private const val KEY_TYPE         = "type"         // General payload type (chat vs call)
        private const val KEY_TOKEN_FIELD  = "fcmToken"     // Firestore field name

        // Message types that match BubbleNotificationManager.MessageType
        private const val TYPE_TEXT     = "text"
        private const val TYPE_IMAGE    = "image"
        private const val TYPE_VOICE    = "voice"
        private const val TYPE_LOCATION = "location"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // Bộ đệm LRU lưu 50 messageId gần nhất để chống FCM redeliver (gửi lặp)
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

        val data = message.data

        // [SỬA LỖI MỚI 3]: Cảnh báo nếu backend gửi nhầm payload có object "notification"
        if (message.notification != null && data.containsKey(KEY_SENDER_ID)) {
            Log.w(TAG, "⚠️ CẢNH BÁO: Payload chứa cả field 'notification' và 'data'. " +
                    "Khi app bị kill, tin nhắn này sẽ không chạy vào FcmService mà bị System handle (không tạo được Bubble). " +
                    "Khuyến nghị sửa Firebase Cloud Functions sang Data-only payload!")
        }

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
        // [SỬA LỖI P2]: Guard chặn luồng Call Notifications biến thành Bubble
        val msgType = data[KEY_TYPE] ?: ""
        if (msgType == "incoming_call" || msgType == "group_call_invite" ||
            msgType == "missed_call" || msgType == "call_ended") {
            Log.d(TAG, "📞 Call notification detected — skip bubble pipeline")
            return
        }

        val senderId   = data[KEY_SENDER_ID]   ?: run { logMissing(KEY_SENDER_ID); return }
        val senderName = data[KEY_SENDER_NAME] ?: raw.notification?.title ?: "Unknown"
        val avatarUrl  = data[KEY_AVATAR_URL]  ?: ""
        val body       = data[KEY_MESSAGE]     ?: raw.notification?.body  ?: ""
        val typeStr    = data[KEY_MESSAGE_TYPE] ?: TYPE_TEXT

        Log.d(TAG, "📩 Data message — sender: $senderName, type: $typeStr, body: ${body.take(40)}")

        val preview = formatPreview(body, typeStr)
        val resolvedType = resolveType(typeStr)

        // Acquire WakeLock để giữ CPU chạy trong lúc xử lý ảnh đại diện / DB (Kiến trúc bổ sung)
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        val wakeLock = powerManager.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "FcmService::BubbleLock")
        wakeLock.acquire(10000L) // Giữ tối đa 10s

        scope.launch {
            try {
                // 1. Đảm bảo service đã được khởi tạo
                BubbleNotificationService.init(applicationContext)

                // 2. Tạo hoặc làm mới Shortcut cho Bubble API
                if (ShortcutHelper.isShortcutsSupported()) {
                    ShortcutHelper.ensureShortcutForNotification(
                        applicationContext, senderId, senderName, avatarUrl)
                }

                // 3. Đẩy thông báo Bubble
                BubbleNotificationService.showBubbleNotificationOnly(
                    context     = applicationContext,
                    userId      = senderId,
                    userName    = senderName,
                    message     = preview,
                    avatarUrl   = avatarUrl,
                    messageType = resolvedType
                )

                Log.d(TAG, "✅ Bubble notification request dispatched for $senderName")

            } catch (e: Exception) {
                Log.e(TAG, "❌ handleDataMessage: $e")
                showFallbackNotification(senderId, senderName, preview)
            } finally {
                if (wakeLock.isHeld) wakeLock.release()
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

            // [SỬA LỖI MỚI 8]: Đồng bộ ID giữa fallback và bubble notification để cancel đúng
            nm.notify(BubbleNotificationManager.notifId(userId), notif)
            Log.d(TAG, "✅ Fallback notification shown for $userName")
        } catch (e: Exception) {
            Log.e(TAG, "❌ showFallbackNotification: $e")
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═════════════════════════════════════════════════════════════════════

    // [SỬA LỖI P2]: Map thêm các chuỗi dạng số tương ứng với code của Dart
    private fun resolveType(typeStr: String): BubbleNotificationManager.MessageType =
        when (typeStr.lowercase()) {
            TYPE_IMAGE, "1"    -> BubbleNotificationManager.MessageType.IMAGE
            "2"                -> BubbleNotificationManager.MessageType.TEXT // Video fallback về text
            TYPE_VOICE, "3"    -> BubbleNotificationManager.MessageType.VOICE
            TYPE_LOCATION, "5" -> BubbleNotificationManager.MessageType.LOCATION
            else               -> BubbleNotificationManager.MessageType.TEXT
        }

    private fun formatPreview(body: String, typeStr: String): String =
        when (typeStr.lowercase()) {
            TYPE_IMAGE, "1"    -> "📷 Hình ảnh"
            "2"                -> "🎥 Video"
            TYPE_VOICE, "3"    -> "🎤 Tin nhắn thoại"
            TYPE_LOCATION, "5" -> "📍 Vị trí"
            else               -> if (body.length > 80) "${body.take(80)}…" else body
        }

    private fun logMissing(key: String) {
        Log.w(TAG, "⚠️ Missing required payload key: $key")
    }

    override fun onDestroy() {
        super.onDestroy()
    }
}
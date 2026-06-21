// android/app/src/main/kotlin/hust/appchat/notifications/BubbleNotificationActionReceiver.kt
package hust.appchat.notifications

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FieldValue
import hust.appchat.R
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await

/**
 * BubbleNotificationActionReceiver — handles quick actions from the notification shade.
 * * [SỬA LỖI TUÂN THỦ ANDROID 12+]:
 * Receiver này ĐÃ ĐƯỢC DỌN DẸP. Tuyệt đối KHÔNG chứa bất kỳ lệnh gọi startActivity() nào
 * bên trong onReceive() để tránh vi phạm chính sách "Notification Trampoline".
 * Các action mở UI (ví dụ: "Mở chat") phải được cấu hình bằng PendingIntent.getActivity()
 * trực tiếp từ lúc build Notification ở BubbleNotificationManager.
 * * Receiver này chỉ giữ lại các tác vụ chạy ngầm (Background Actions):
 * ──────────────────
 * REPLY      : Gửi tin nhắn lên Firestore, cập nhật Notification, gửi event về Dart.
 * MARK_READ  : Hủy notification, xóa lịch sử, gửi event về Dart.
 * DISMISS    : Xóa notification do user vuốt bỏ, gửi event về Dart.
 */
class BubbleNotificationActionReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "BubbleActionReceiver"

        // Broadcast actions
        const val ACTION_REPLY     = "hust.appchat.BUBBLE_REPLY"
        const val ACTION_MARK_READ = "hust.appchat.BUBBLE_MARK_READ"
        const val ACTION_DISMISS   = "hust.appchat.BUBBLE_DISMISS"

        // Intent extras
        const val EXTRA_USER_ID    = "userId"
        const val EXTRA_USER_NAME  = "userName"
        const val EXTRA_AVATAR_URL = "avatarUrl"
        const val EXTRA_NOTIF_ID   = "notifId"

        // RemoteInput key (must match in createReplyAction)
        const val KEY_REPLY_TEXT   = "key_reply_text"

        // ─── Action builders ─────────────────────────────────────────────

        /** Creates an inline-reply action for a notification. */
        fun createReplyAction(
            ctx       : Context,
            userId    : String,
            userName  : String,
            avatarUrl : String,
            notifId   : Int,
        ): NotificationCompat.Action {
            val remoteInput = RemoteInput.Builder(KEY_REPLY_TEXT)
                .setLabel("Trả lời $userName…")
                .build()

            val intent = Intent(ACTION_REPLY).apply {
                setPackage(ctx.packageName)
                putExtra(EXTRA_USER_ID,    userId)
                putExtra(EXTRA_USER_NAME,  userName)
                putExtra(EXTRA_AVATAR_URL, avatarUrl)
                putExtra(EXTRA_NOTIF_ID,   notifId)
            }

            // Giãn cách Request Code bằng hàm băm để chống va chạm Intent
            val reqCode = (ACTION_REPLY + userId).hashCode()

            val pi = PendingIntent.getBroadcast(
                ctx, reqCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )

            return NotificationCompat.Action.Builder(
                R.drawable.ic_send, "Trả lời", pi)
                .addRemoteInput(remoteInput)
                .setAllowGeneratedReplies(true)
                .build()
        }

        /** Creates a "Mark as read" action button. */
        fun createMarkReadAction(
            ctx    : Context,
            userId : String,
            notifId: Int,
        ): NotificationCompat.Action {
            val intent = Intent(ACTION_MARK_READ).apply {
                setPackage(ctx.packageName)
                putExtra(EXTRA_USER_ID,  userId)
                putExtra(EXTRA_NOTIF_ID, notifId)
            }

            val reqCode = (ACTION_MARK_READ + userId).hashCode()

            val pi = PendingIntent.getBroadcast(
                ctx, reqCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            return NotificationCompat.Action.Builder(
                R.drawable.ic_notification, "Đã đọc", pi).build()
        }

        /** Creates a dismiss delete-intent for setDeleteIntent(). */
        fun createDismissPendingIntent(
            ctx    : Context,
            userId : String,
            notifId: Int,
        ): PendingIntent {
            val intent = Intent(ACTION_DISMISS).apply {
                setPackage(ctx.packageName)
                putExtra(EXTRA_USER_ID,  userId)
                putExtra(EXTRA_NOTIF_ID, notifId)
            }

            val reqCode = (ACTION_DISMISS + userId).hashCode()

            return PendingIntent.getBroadcast(
                ctx, reqCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        }
    }

    // ─── Coroutine scope ─────────────────────────────────────────────────
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // ═════════════════════════════════════════════════════════════════════
    // RECEIVE
    // ═════════════════════════════════════════════════════════════════════

    override fun onReceive(context: Context, intent: Intent) {
        val userId   = intent.getStringExtra(EXTRA_USER_ID)   ?: return
        val userName = intent.getStringExtra(EXTRA_USER_NAME) ?: ""
        val avatar   = intent.getStringExtra(EXTRA_AVATAR_URL) ?: ""
        val notifId  = intent.getIntExtra(EXTRA_NOTIF_ID, 0)

        Log.d(TAG, "📬 Action: ${intent.action} for $userName")

        when (intent.action) {
            ACTION_REPLY     -> handleReply(context, intent, userId, userName, avatar, notifId)
            ACTION_MARK_READ -> handleMarkRead(context, userId, notifId)
            ACTION_DISMISS   -> handleDismiss(context, userId, notifId)
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // REPLY
    // ═════════════════════════════════════════════════════════════════════

    private fun handleReply(
        ctx    : Context,
        intent : Intent,
        userId : String,
        name   : String,
        avatar : String,
        notifId: Int,
    ) {
        val replyText = RemoteInput.getResultsFromIntent(intent)
            ?.getCharSequence(KEY_REPLY_TEXT)
            ?.toString()
            ?.trim()
            ?: return

        Log.d(TAG, "💬 Reply from notification: ${replyText.take(40)}")

        scope.launch {
            try {
                // Chờ kết quả ghi Firestore để chắc chắn thành công
                sendMessageToFirestore(ctx, userId, replyText)

                // Update MessagingStyle notification
                updateNotificationWithReply(ctx, userId, name, avatar, replyText, notifId)

                // Forward to Flutter EventSink via broadcast
                ctx.sendBroadcast(Intent("CHAT_BUBBLE_MESSAGE").apply {
                    putExtra("userId",  userId)
                    putExtra("message", replyText)
                })

                Log.d(TAG, "✅ Reply sent and notification updated")
            } catch (e: Exception) {
                Log.e(TAG, "❌ handleReply failed: $e")

                // Nếu lỗi gửi, cập nhật Bubble Notification với dòng cảnh báo lỗi
                // để người dùng biết tin nhắn chưa đi.
                updateNotificationWithReply(
                    ctx = ctx,
                    userId = userId,
                    name = name,
                    avatar = avatar,
                    reply = "[Lỗi, chưa gửi] $replyText",
                    notifId = notifId
                )
            }
        }
    }

    // Sử dụng await() từ thư viện kotlinx-coroutines-play-services
    private suspend fun sendMessageToFirestore(
        ctx    : Context,
        peerId : String,
        message: String,
    ) {
        val db   = FirebaseFirestore.getInstance()
        val auth = FirebaseAuth.getInstance()
        val myId = auth.currentUser?.uid ?: throw IllegalStateException("User not logged in")

        val convId = if (myId < peerId) "$myId-$peerId" else "$peerId-$myId"
        val ts     = System.currentTimeMillis().toString()

        val msgData = hashMapOf(
            "idFrom"    to myId,
            "idTo"      to peerId,
            "timestamp" to ts,
            "content"   to message,
            "type"      to 0,   // text
            "isRead"    to false,
        )

        db.collection("messages")
            .document(convId)
            .collection(convId)
            .document(ts)
            .set(msgData).await()

        db.collection("conversations").document(convId)
            .update(mapOf(
                "lastMessage"  to message,
                "lastSenderId" to myId,
                "updatedAt"    to FieldValue.serverTimestamp(),
            )).await()

        Log.d(TAG, "✅ Message saved to Firestore")
    }

    private fun updateNotificationWithReply(
        ctx    : Context,
        userId : String,
        name   : String,
        avatar : String,
        reply  : String,
        notifId: Int,
    ) {
        try {
            val auth = FirebaseAuth.getInstance()
            // Check auth state just to be safe before updating UI
            auth.currentUser?.uid ?: return

            // Add "Tôi: <reply>" to message history then re-render
            BubbleNotificationManager.addMessage(
                context   = ctx,
                userId    = userId,
                userName  = name,
                message   = reply,
                avatarUrl = avatar,
                fromUser  = true,
            )

            Log.d(TAG, "✅ Notification updated with reply")
        } catch (e: Exception) {
            Log.e(TAG, "❌ updateNotificationWithReply: $e")
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // MARK READ
    // ═════════════════════════════════════════════════════════════════════

    private fun handleMarkRead(ctx: Context, userId: String, notifId: Int) {
        try {
            val nm = ctx.getSystemService(NotificationManager::class.java)
            nm?.cancel(notifId)
            BubbleNotificationManager.clearHistory(userId)
            broadcastDismiss(ctx, userId)
            Log.d(TAG, "✅ Marked as read: $userId")
        } catch (e: Exception) {
            Log.e(TAG, "❌ handleMarkRead: $e")
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // DISMISS
    // ═════════════════════════════════════════════════════════════════════

    private fun handleDismiss(ctx: Context, userId: String, notifId: Int) {
        try {
            BubbleNotificationManager.clearHistory(userId)
            broadcastDismiss(ctx, userId)
            Log.d(TAG, "✅ Dismissed: $userId")
        } catch (e: Exception) {
            Log.e(TAG, "❌ handleDismiss: $e")
        }
    }

    // ─── Helper ──────────────────────────────────────────────────────────

    private fun broadcastDismiss(ctx: Context, userId: String) {
        ctx.sendBroadcast(Intent("CHAT_BUBBLE_DISMISS").apply {
            putExtra("userId", userId)
        })
    }
}
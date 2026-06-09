// android/app/src/main/kotlin/hust/appchat/notifications/BubbleNotificationActionReceiver.kt
package hust.appchat.notifications

import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.app.RemoteInput
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.FieldValue
import hust.appchat.R
import hust.appchat.shortcuts.AvatarLoader
import hust.appchat.shortcuts.ShortcutHelper
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * BubbleNotificationActionReceiver — handles quick actions from the notification shade.
 *
 * Actions supported
 * ──────────────────
 * REPLY      : User typed a reply in the notification inline-reply input.
 *              → Sends the message to Firestore.
 *              → Updates the MessagingStyle notification with the sent message.
 *              → Forwards event to Flutter via broadcast.
 *
 * MARK_READ  : User tapped "Mark as read" action button.
 *              → Cancels the notification.
 *              → Clears BubbleNotificationManager history.
 *              → Broadcasts CHAT_BUBBLE_DISMISS to Flutter EventSink.
 *
 * DISMISS    : User swiped the notification away.
 *              → Same as MARK_READ.
 *
 * AndroidManifest registration (add inside <application>):
 * ─────────────────────────────────────────────────────────
 * <receiver
 *     android:name=".notifications.BubbleNotificationActionReceiver"
 *     android:exported="false">
 *     <intent-filter>
 *         <action android:name="hust.appchat.BUBBLE_REPLY" />
 *         <action android:name="hust.appchat.BUBBLE_MARK_READ" />
 *         <action android:name="hust.appchat.BUBBLE_DISMISS" />
 *     </intent-filter>
 * </receiver>
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
            val pi = PendingIntent.getBroadcast(
                ctx, notifId + 1, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                            PendingIntent.FLAG_MUTABLE else 0
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
            val pi = PendingIntent.getBroadcast(
                ctx, notifId + 2, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                            PendingIntent.FLAG_IMMUTABLE else 0
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
            return PendingIntent.getBroadcast(
                ctx, notifId + 3, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                            PendingIntent.FLAG_IMMUTABLE else 0
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

        // 1. Send to Firestore
        scope.launch {
            try {
                sendMessageToFirestore(ctx, userId, replyText)

                // 2. Update MessagingStyle notification on API 30+
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    updateNotificationWithReply(ctx, userId, name, avatar, replyText, notifId)
                }

                // 3. Forward to Flutter EventSink via broadcast
                ctx.sendBroadcast(Intent("CHAT_BUBBLE_MESSAGE").apply {
                    putExtra("userId",  userId)
                    putExtra("message", replyText)
                })

                Log.d(TAG, "✅ Reply sent and notification updated")
            } catch (e: Exception) {
                Log.e(TAG, "❌ handleReply: $e")
            }
        }
    }

    private suspend fun sendMessageToFirestore(
        ctx    : Context,
        peerId : String,
        message: String,
    ) {
        val db   = FirebaseFirestore.getInstance()
        val auth = FirebaseAuth.getInstance()
        val myId = auth.currentUser?.uid ?: return

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
            .set(msgData)

        // Update conversation metadata
        db.collection("conversations").document(convId)
            .update(mapOf(
                "lastMessage"  to message,
                "lastSenderId" to myId,
                "updatedAt"    to FieldValue.serverTimestamp(),
            ))

        Log.d(TAG, "✅ Message saved to Firestore")
    }

    @RequiresApi(Build.VERSION_CODES.R)
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
            val myId = auth.currentUser?.uid ?: return

            val myIcon = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                AvatarLoader.loadAvatarIcon(ctx, "", "Tôi")
            else return

            val mePerson = Person.Builder()
                .setName("Tôi")
                .setKey(myId)
                .setIcon(myIcon)
                .build()

            // Add "Tôi: <reply>" to message history then re-render
            BubbleNotificationManager.addMessage(
                context   = ctx,
                userId    = userId,
                userName  = name,
                message   = reply,
                avatarUrl = avatar,
                fromUser  = true,
            )

            // Mark sending animation complete — just cancel the "sending" spinner
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                BubbleNotificationManager.clearHistory(userId)
            }
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                BubbleNotificationManager.clearHistory(userId)
            }
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
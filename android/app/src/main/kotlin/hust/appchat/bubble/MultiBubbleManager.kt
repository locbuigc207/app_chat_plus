// android/app/src/main/kotlin/hust/appchat/bubble/MultiBubbleManager.kt
package hust.appchat.bubble

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.view.WindowManager
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration

/**
 * CHANGES vs original:
 *
 * FIX-DISPLAY — Thay deprecated windowManager.defaultDisplay.getMetrics() bằng
 *   currentWindowMetrics (API 30+) với fallback displayMetrics cho API 24-29.
 *   defaultDisplay.getMetrics() bị deprecated từ API 30 và trả về kích thước SAI
 *   trên Android 11+ (không tính display cutout, insets, multi-window).
 */
object MultiBubbleManager {

    private const val MAX_BUBBLES = 5
    private const val BUBBLE_SIZE = 64
    private const val VERTICAL_SPACING = 80
    private const val HORIZONTAL_MARGIN = 20

    private val activeBubbles = mutableMapOf<String, BubbleInfo>()
    private val messageListeners = mutableMapOf<String, ListenerRegistration>()

    private var firestore: FirebaseFirestore? = null
    private var auth: FirebaseAuth? = null

    private var screenWidth = 0
    private var screenHeight = 0

    private var nextYPosition = 200
    private var isLeftSide = true

    data class BubbleInfo(
        val userId: String,
        val userName: String,
        val avatarUrl: String,
        var unreadCount: Int = 0,
        var lastMessage: String = "",
        var timestamp: Long = System.currentTimeMillis(),
        var priority: Int = 0,
        var position: Position = Position(0, 0)
    )

    data class Position(var x: Int, var y: Int)

    // ========================================
    // INITIALIZATION
    // ========================================
    fun init(context: Context) {
        try {
            firestore = FirebaseFirestore.getInstance()
            auth = FirebaseAuth.getInstance()

            // FIX-DISPLAY: Dùng API phù hợp với SDK version
            val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val size = getScreenSize(windowManager, context)
            screenWidth = size.first
            screenHeight = size.second

            Log.d("MultiBubbleManager", "✅ Initialized: ${screenWidth}x${screenHeight}")
        } catch (e: Exception) {
            Log.e("MultiBubbleManager", "❌ Init failed: $e")
        }
    }

    /**
     * FIX-DISPLAY: Lấy screen size đúng cách theo SDK version.
     * - API 30+ (Android 11+): dùng currentWindowMetrics.bounds — bao gồm insets,
     *   chính xác trong multi-window và foldable.
     * - API 24-29: dùng displayMetrics (deprecated nhưng không còn lựa chọn nào khác).
     */
    private fun getScreenSize(wm: WindowManager, context: Context): Pair<Int, Int> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = wm.currentWindowMetrics.bounds
            Pair(bounds.width(), bounds.height())
        } else {
            val dm = context.resources.displayMetrics
            Pair(dm.widthPixels, dm.heightPixels)
        }
    }

    // ========================================
    // BUBBLE MANAGEMENT
    // ========================================

    fun addBubble(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String,
        message: String? = null,
        priority: Int = 0
    ): Boolean {
        if (activeBubbles.size >= MAX_BUBBLES) {
            Log.w("MultiBubbleManager", "⚠️ Max bubbles reached ($MAX_BUBBLES)")
            val lowestPriority = activeBubbles.values.minByOrNull { it.priority }
            if (lowestPriority != null && priority > lowestPriority.priority) {
                removeBubble(context, lowestPriority.userId)
            } else {
                return false
            }
        }

        if (activeBubbles.containsKey(userId)) {
            Log.d("MultiBubbleManager", "ℹ️ Bubble exists, updating: $userId")
            updateBubble(userId, message ?: "")
            return true
        }

        Log.d("MultiBubbleManager", "🎈 Adding bubble: $userName (priority: $priority)")

        val position = calculateOptimalPosition(priority)

        val bubbleInfo = BubbleInfo(
            userId = userId,
            userName = userName,
            avatarUrl = avatarUrl,
            lastMessage = message ?: "",
            priority = priority,
            position = position
        )

        activeBubbles[userId] = bubbleInfo

        val intent = Intent(context, BubbleOverlayService::class.java).apply {
            action = BubbleOverlayService.ACTION_SHOW_BUBBLE
            putExtra("userId", userId)
            putExtra("userName", userName)
            putExtra("avatarUrl", avatarUrl)
            putExtra("unreadCount", 0)
            putExtra("lastMessage", message ?: "")
            putExtra("positionX", position.x)
            putExtra("positionY", position.y)
        }

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
            setupMessageListener(context, userId)
            rearrangeBubbles(context)
            true
        } catch (e: Exception) {
            Log.e("MultiBubbleManager", "❌ Failed to add bubble: $e")
            activeBubbles.remove(userId)
            false
        }
    }

    fun removeBubble(context: Context, userId: String) {
        Log.d("MultiBubbleManager", "🗑️ Removing bubble: $userId")

        activeBubbles.remove(userId)
        messageListeners.remove(userId)?.remove()

        val intent = Intent(context, BubbleOverlayService::class.java).apply {
            action = BubbleOverlayService.ACTION_HIDE_BUBBLE
            putExtra("userId", userId)
        }

        try {
            context.startService(intent)
            rearrangeBubbles(context)
        } catch (e: Exception) {
            Log.e("MultiBubbleManager", "❌ Failed to remove bubble: $e")
        }
    }

    fun updateBubble(userId: String, message: String) {
        activeBubbles[userId]?.let { bubble ->
            bubble.lastMessage = message
            bubble.unreadCount++
            bubble.timestamp = System.currentTimeMillis()
        }
    }

    fun removeAllBubbles(context: Context) {
        Log.d("MultiBubbleManager", "🗑️ Removing all bubbles")

        messageListeners.values.forEach { it.remove() }
        messageListeners.clear()
        activeBubbles.clear()

        val intent = Intent(context, BubbleOverlayService::class.java).apply {
            action = "HIDE_ALL_BUBBLES"
        }

        try {
            context.startService(intent)
        } catch (e: Exception) {
            Log.e("MultiBubbleManager", "❌ Failed to remove all: $e")
        }

        resetPositioning()
    }

    // ========================================
    // SMART POSITIONING
    // ========================================

    private fun calculateOptimalPosition(priority: Int): Position {
        val x = if (isLeftSide) {
            HORIZONTAL_MARGIN
        } else {
            screenWidth - BUBBLE_SIZE - HORIZONTAL_MARGIN
        }

        val baseY = 200
        val priorityOffset = -priority * 50

        var y = baseY + priorityOffset + (activeBubbles.size * VERTICAL_SPACING)

        val maxY = screenHeight - BUBBLE_SIZE - 100
        if (y > maxY) {
            y = maxY
            isLeftSide = !isLeftSide
        }

        return Position(x, y)
    }

    private fun rearrangeBubbles(context: Context) {
        if (activeBubbles.isEmpty()) {
            resetPositioning()
            return
        }

        Log.d("MultiBubbleManager", "📍 Rearranging ${activeBubbles.size} bubbles")

        val sortedBubbles = activeBubbles.values.sortedByDescending { it.priority }

        var yPos = 200
        val side = if (isLeftSide) HORIZONTAL_MARGIN else screenWidth - BUBBLE_SIZE - HORIZONTAL_MARGIN

        sortedBubbles.forEach { bubble ->
            bubble.position.x = side
            bubble.position.y = yPos

            val intent = Intent(context, BubbleOverlayService::class.java).apply {
                action = "UPDATE_BUBBLE_POSITION"
                putExtra("userId", bubble.userId)
                putExtra("positionX", bubble.position.x)
                putExtra("positionY", bubble.position.y)
            }

            try {
                context.startService(intent)
            } catch (e: Exception) {
                Log.e("MultiBubbleManager", "❌ Failed to update position: $e")
            }

            yPos += VERTICAL_SPACING
            if (yPos > screenHeight - BUBBLE_SIZE - 100) {
                yPos = 200
            }
        }
    }

    private fun resetPositioning() {
        nextYPosition = 200
        isLeftSide = true
    }

    // ========================================
    // MESSAGE LISTENING
    // ========================================

    private fun setupMessageListener(context: Context, userId: String) {
        val currentUserId = BubbleManager.getCurrentUserId() ?: return

        val conversationId = if (currentUserId < userId) {
            "$currentUserId-$userId"
        } else {
            "$userId-$currentUserId"
        }

        try {
            val listener = firestore
                ?.collection("messages")
                ?.document(conversationId)
                ?.collection(conversationId)
                ?.whereEqualTo("idFrom", userId)
                ?.whereEqualTo("isRead", false)
                ?.addSnapshotListener { snapshot, error ->
                    if (error != null) {
                        Log.e("MultiBubbleManager", "❌ Listen error: $error")
                        return@addSnapshotListener
                    }

                    snapshot?.documentChanges?.forEach { change ->
                        if (change.type == com.google.firebase.firestore.DocumentChange.Type.ADDED) {
                            val message = change.document.getString("content") ?: ""
                            updateBubble(userId, message)

                            val intent = Intent(context, BubbleOverlayService::class.java).apply {
                                action = BubbleOverlayService.ACTION_UPDATE_BUBBLE
                                putExtra("userId", userId)
                                putExtra("unreadCount", activeBubbles[userId]?.unreadCount ?: 0)
                                putExtra("lastMessage", message)
                            }

                            try {
                                context.startService(intent)
                            } catch (e: Exception) {
                                Log.e("MultiBubbleManager", "❌ Update failed: $e")
                            }
                        }
                    }
                }

            listener?.let { messageListeners[userId] = it }
            Log.d("MultiBubbleManager", "✅ Listener setup: $userId")
        } catch (e: Exception) {
            Log.e("MultiBubbleManager", "❌ Listener setup failed: $e")
        }
    }

    // ========================================
    // STATE MANAGEMENT
    // ========================================

    fun getActiveBubbles(): Map<String, BubbleInfo> = activeBubbles.toMap()

    fun getBubbleCount(): Int = activeBubbles.size

    fun isBubbleActive(userId: String): Boolean = activeBubbles.containsKey(userId)

    fun getUnreadCount(userId: String): Int = activeBubbles[userId]?.unreadCount ?: 0

    fun markAsRead(userId: String) {
        activeBubbles[userId]?.unreadCount = 0
    }

    fun getBubblesByPriority(): List<BubbleInfo> =
        activeBubbles.values.sortedByDescending { it.priority }

    fun updatePriority(context: Context, userId: String, newPriority: Int) {
        activeBubbles[userId]?.let { bubble ->
            bubble.priority = newPriority
            rearrangeBubbles(context)
            Log.d("MultiBubbleManager", "📊 Priority updated: $userId = $newPriority")
        }
    }

    // ========================================
    // PERSISTENCE
    // ========================================

    fun saveState(context: Context) {
        try {
            val prefs = context.getSharedPreferences("bubble_state", Context.MODE_PRIVATE)
            val editor = prefs.edit()
            editor.putInt("bubble_count", activeBubbles.size)
            activeBubbles.values.forEachIndexed { index, bubble ->
                editor.putString("bubble_${index}_userId", bubble.userId)
                editor.putString("bubble_${index}_userName", bubble.userName)
                editor.putString("bubble_${index}_avatarUrl", bubble.avatarUrl)
                editor.putInt("bubble_${index}_priority", bubble.priority)
            }
            editor.apply()
            Log.d("MultiBubbleManager", "💾 State saved: ${activeBubbles.size} bubbles")
        } catch (e: Exception) {
            Log.e("MultiBubbleManager", "❌ Save state failed: $e")
        }
    }

    fun restoreState(context: Context) {
        try {
            val prefs = context.getSharedPreferences("bubble_state", Context.MODE_PRIVATE)
            val count = prefs.getInt("bubble_count", 0)
            if (count == 0) return

            Log.d("MultiBubbleManager", "📦 Restoring $count bubbles")
            repeat(count) { index ->
                val userId = prefs.getString("bubble_${index}_userId", null) ?: return@repeat
                val userName = prefs.getString("bubble_${index}_userName", "") ?: ""
                val avatarUrl = prefs.getString("bubble_${index}_avatarUrl", "") ?: ""
                val priority = prefs.getInt("bubble_${index}_priority", 0)
                addBubble(context, userId, userName, avatarUrl, priority = priority)
            }
            Log.d("MultiBubbleManager", "✅ State restored")
        } catch (e: Exception) {
            Log.e("MultiBubbleManager", "❌ Restore state failed: $e")
        }
    }

    fun clearState(context: Context) {
        try {
            context.getSharedPreferences("bubble_state", Context.MODE_PRIVATE)
                .edit().clear().apply()
            Log.d("MultiBubbleManager", "🗑️ State cleared")
        } catch (e: Exception) {
            Log.e("MultiBubbleManager", "❌ Clear state failed: $e")
        }
    }

    // ========================================
    // CLEANUP
    // ========================================

    fun cleanup() {
        Log.d("MultiBubbleManager", "🧹 Cleanup")
        messageListeners.values.forEach {
            try { it.remove() } catch (e: Exception) {
                Log.e("MultiBubbleManager", "❌ Cleanup error: $e")
            }
        }
        messageListeners.clear()
        activeBubbles.clear()
        resetPositioning()
    }
}
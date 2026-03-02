// android/app/src/main/kotlin/hust/appchat/bubble/MultiBubbleManager.kt
package hust.appchat.bubble

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.DisplayMetrics
import android.view.WindowManager
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration

/**
 * ✅ MULTI-BUBBLE MANAGER
 *
 * Quản lý nhiều chat bubbles cùng lúc với:
 * - Smart positioning (tránh chồng lấn)
 * - Auto-arrange khi thêm/xóa bubble
 * - Priority system (bubble quan trọng hơn ở vị trí dễ thấy)
 * - Max bubble limit (để tránh quá tải)
 * - Persistence (lưu state khi app restart)
 * - Memory optimization
 */
object MultiBubbleManager {

    private const val MAX_BUBBLES = 5
    private const val BUBBLE_SIZE = 64 // dp
    private const val VERTICAL_SPACING = 80 // dp
    private const val HORIZONTAL_MARGIN = 20 // dp

    private val activeBubbles = mutableMapOf<String, BubbleInfo>()
    private val messageListeners = mutableMapOf<String, ListenerRegistration>()

    private var firestore: FirebaseFirestore? = null
    private var auth: FirebaseAuth? = null

    // Screen dimensions
    private var screenWidth = 0
    private var screenHeight = 0

    // Layout configuration
    private var nextYPosition = 200
    private var isLeftSide = true

    data class BubbleInfo(
        val userId: String,
        val userName: String,
        val avatarUrl: String,
        var unreadCount: Int = 0,
        var lastMessage: String = "",
        var timestamp: Long = System.currentTimeMillis(),
        var priority: Int = 0, // Higher priority = better position
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

            // Get screen dimensions
            val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            val displayMetrics = DisplayMetrics()
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getMetrics(displayMetrics)
            screenWidth = displayMetrics.widthPixels
            screenHeight = displayMetrics.heightPixels

            android.util.Log.d("MultiBubbleManager", "✅ Initialized: ${screenWidth}x${screenHeight}")
        } catch (e: Exception) {
            android.util.Log.e("MultiBubbleManager", "❌ Init failed: $e")
        }
    }

    // ========================================
    // BUBBLE MANAGEMENT
    // ========================================

    /**
     * Add bubble with smart positioning
     */
    fun addBubble(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String,
        message: String? = null,
        priority: Int = 0
    ): Boolean {
        // Check max limit
        if (activeBubbles.size >= MAX_BUBBLES) {
            android.util.Log.w("MultiBubbleManager", "⚠️ Max bubbles reached ($MAX_BUBBLES)")

            // Remove lowest priority bubble if new one has higher priority
            val lowestPriority = activeBubbles.values.minByOrNull { it.priority }
            if (lowestPriority != null && priority > lowestPriority.priority) {
                removeBubble(context, lowestPriority.userId)
            } else {
                return false
            }
        }

        // Check if bubble already exists
        if (activeBubbles.containsKey(userId)) {
            android.util.Log.d("MultiBubbleManager", "ℹ️ Bubble exists, updating: $userId")
            updateBubble(userId, message ?: "")
            return true
        }

        android.util.Log.d("MultiBubbleManager", "🎈 Adding bubble: $userName (priority: $priority)")

        // Calculate optimal position
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

        // Create bubble via service
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

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }

            // Setup message listener
            setupMessageListener(context, userId)

            // Rearrange existing bubbles
            rearrangeBubbles(context)

            return true
        } catch (e: Exception) {
            android.util.Log.e("MultiBubbleManager", "❌ Failed to add bubble: $e")
            activeBubbles.remove(userId)
            return false
        }
    }

    /**
     * Remove bubble and rearrange
     */
    fun removeBubble(context: Context, userId: String) {
        android.util.Log.d("MultiBubbleManager", "🗑️ Removing bubble: $userId")

        activeBubbles.remove(userId)
        messageListeners.remove(userId)?.remove()

        val intent = Intent(context, BubbleOverlayService::class.java).apply {
            action = BubbleOverlayService.ACTION_HIDE_BUBBLE
            putExtra("userId", userId)
        }

        try {
            context.startService(intent)

            // Rearrange remaining bubbles
            rearrangeBubbles(context)
        } catch (e: Exception) {
            android.util.Log.e("MultiBubbleManager", "❌ Failed to remove bubble: $e")
        }
    }

    /**
     * Update existing bubble
     */
    fun updateBubble(userId: String, message: String) {
        activeBubbles[userId]?.let { bubble ->
            bubble.lastMessage = message
            bubble.unreadCount++
            bubble.timestamp = System.currentTimeMillis()

            android.util.Log.d("MultiBubbleManager", "📨 Updated bubble: $userId (unread: ${bubble.unreadCount})")
        }
    }

    /**
     * Remove all bubbles
     */
    fun removeAllBubbles(context: Context) {
        android.util.Log.d("MultiBubbleManager", "🗑️ Removing all bubbles")

        messageListeners.values.forEach { it.remove() }
        messageListeners.clear()
        activeBubbles.clear()

        val intent = Intent(context, BubbleOverlayService::class.java).apply {
            action = "HIDE_ALL_BUBBLES"
        }

        try {
            context.startService(intent)
        } catch (e: Exception) {
            android.util.Log.e("MultiBubbleManager", "❌ Failed to remove all: $e")
        }

        resetPositioning()
    }

    // ========================================
    // SMART POSITIONING
    // ========================================

    /**
     * Calculate optimal position based on priority and available space
     */
    private fun calculateOptimalPosition(priority: Int): Position {
        val x = if (isLeftSide) {
            HORIZONTAL_MARGIN
        } else {
            screenWidth - BUBBLE_SIZE - HORIZONTAL_MARGIN
        }

        // Higher priority bubbles get better positions (higher on screen)
        val baseY = 200
        val priorityOffset = -priority * 50 // Higher priority = lower Y (higher on screen)

        var y = baseY + priorityOffset + (activeBubbles.size * VERTICAL_SPACING)

        // Ensure within screen bounds
        val maxY = screenHeight - BUBBLE_SIZE - 100
        if (y > maxY) {
            y = maxY
            // Switch to other side if needed
            isLeftSide = !isLeftSide
        }

        return Position(x, y)
    }

    /**
     * Rearrange all bubbles optimally
     */
    private fun rearrangeBubbles(context: Context) {
        if (activeBubbles.isEmpty()) {
            resetPositioning()
            return
        }

        android.util.Log.d("MultiBubbleManager", "📍 Rearranging ${activeBubbles.size} bubbles")

        // Sort by priority (highest first)
        val sortedBubbles = activeBubbles.values.sortedByDescending { it.priority }

        var yPos = 200
        val side = if (isLeftSide) HORIZONTAL_MARGIN else screenWidth - BUBBLE_SIZE - HORIZONTAL_MARGIN

        sortedBubbles.forEach { bubble ->
            bubble.position.x = side
            bubble.position.y = yPos

            // Update position via service
            val intent = Intent(context, BubbleOverlayService::class.java).apply {
                action = "UPDATE_BUBBLE_POSITION"
                putExtra("userId", bubble.userId)
                putExtra("positionX", bubble.position.x)
                putExtra("positionY", bubble.position.y)
            }

            try {
                context.startService(intent)
            } catch (e: Exception) {
                android.util.Log.e("MultiBubbleManager", "❌ Failed to update position: $e")
            }

            yPos += VERTICAL_SPACING

            // Check if exceeding screen
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
                        android.util.Log.e("MultiBubbleManager", "❌ Listen error: $error")
                        return@addSnapshotListener
                    }

                    snapshot?.documentChanges?.forEach { change ->
                        if (change.type == com.google.firebase.firestore.DocumentChange.Type.ADDED) {
                            val message = change.document.getString("content") ?: ""
                            updateBubble(userId, message)

                            // Notify service to update bubble UI
                            val intent = Intent(context, BubbleOverlayService::class.java).apply {
                                action = BubbleOverlayService.ACTION_UPDATE_BUBBLE
                                putExtra("userId", userId)
                                putExtra("unreadCount", activeBubbles[userId]?.unreadCount ?: 0)
                                putExtra("lastMessage", message)
                            }

                            try {
                                context.startService(intent)
                            } catch (e: Exception) {
                                android.util.Log.e("MultiBubbleManager", "❌ Update failed: $e")
                            }
                        }
                    }
                }

            listener?.let { messageListeners[userId] = it }
            android.util.Log.d("MultiBubbleManager", "✅ Listener setup: $userId")
        } catch (e: Exception) {
            android.util.Log.e("MultiBubbleManager", "❌ Listener setup failed: $e")
        }
    }

    // ========================================
    // STATE MANAGEMENT
    // ========================================

    fun getActiveBubbles(): Map<String, BubbleInfo> {
        return activeBubbles.toMap()
    }

    fun getBubbleCount(): Int {
        return activeBubbles.size
    }

    fun isBubbleActive(userId: String): Boolean {
        return activeBubbles.containsKey(userId)
    }

    fun getUnreadCount(userId: String): Int {
        return activeBubbles[userId]?.unreadCount ?: 0
    }

    fun markAsRead(userId: String) {
        activeBubbles[userId]?.unreadCount = 0
    }

    /**
     * Get bubble info sorted by priority
     */
    fun getBubblesByPriority(): List<BubbleInfo> {
        return activeBubbles.values.sortedByDescending { it.priority }
    }

    /**
     * Update bubble priority and rearrange
     */
    fun updatePriority(context: Context, userId: String, newPriority: Int) {
        activeBubbles[userId]?.let { bubble ->
            bubble.priority = newPriority
            rearrangeBubbles(context)
            android.util.Log.d("MultiBubbleManager", "📊 Priority updated: $userId = $newPriority")
        }
    }

    // ========================================
    // PERSISTENCE
    // ========================================

    /**
     * Save bubble state to SharedPreferences
     */
    fun saveState(context: Context) {
        try {
            val prefs = context.getSharedPreferences("bubble_state", Context.MODE_PRIVATE)
            val editor = prefs.edit()

            // Save bubble count
            editor.putInt("bubble_count", activeBubbles.size)

            // Save each bubble
            activeBubbles.values.forEachIndexed { index, bubble ->
                editor.putString("bubble_${index}_userId", bubble.userId)
                editor.putString("bubble_${index}_userName", bubble.userName)
                editor.putString("bubble_${index}_avatarUrl", bubble.avatarUrl)
                editor.putInt("bubble_${index}_priority", bubble.priority)
            }

            editor.apply()
            android.util.Log.d("MultiBubbleManager", "💾 State saved: ${activeBubbles.size} bubbles")
        } catch (e: Exception) {
            android.util.Log.e("MultiBubbleManager", "❌ Save state failed: $e")
        }
    }

    /**
     * Restore bubble state from SharedPreferences
     */
    fun restoreState(context: Context) {
        try {
            val prefs = context.getSharedPreferences("bubble_state", Context.MODE_PRIVATE)
            val count = prefs.getInt("bubble_count", 0)

            if (count == 0) {
                android.util.Log.d("MultiBubbleManager", "ℹ️ No saved state")
                return
            }

            android.util.Log.d("MultiBubbleManager", "📦 Restoring $count bubbles")

            repeat(count) { index ->
                val userId = prefs.getString("bubble_${index}_userId", null) ?: return@repeat
                val userName = prefs.getString("bubble_${index}_userName", "") ?: ""
                val avatarUrl = prefs.getString("bubble_${index}_avatarUrl", "") ?: ""
                val priority = prefs.getInt("bubble_${index}_priority", 0)

                addBubble(context, userId, userName, avatarUrl, priority = priority)
            }

            android.util.Log.d("MultiBubbleManager", "✅ State restored")
        } catch (e: Exception) {
            android.util.Log.e("MultiBubbleManager", "❌ Restore state failed: $e")
        }
    }

    /**
     * Clear saved state
     */
    fun clearState(context: Context) {
        try {
            val prefs = context.getSharedPreferences("bubble_state", Context.MODE_PRIVATE)
            prefs.edit().clear().apply()
            android.util.Log.d("MultiBubbleManager", "🗑️ State cleared")
        } catch (e: Exception) {
            android.util.Log.e("MultiBubbleManager", "❌ Clear state failed: $e")
        }
    }

    // ========================================
    // CLEANUP
    // ========================================

    fun cleanup() {
        android.util.Log.d("MultiBubbleManager", "🧹 Cleanup")

        messageListeners.values.forEach {
            try {
                it.remove()
            } catch (e: Exception) {
                android.util.Log.e("MultiBubbleManager", "❌ Cleanup error: $e")
            }
        }

        messageListeners.clear()
        activeBubbles.clear()
        resetPositioning()
    }
}
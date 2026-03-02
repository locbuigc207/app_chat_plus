// android/app/src/main/kotlin/hust/appchat/bubble/BubbleManager.kt
package hust.appchat.bubble

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.os.Build
import android.util.Log
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentChange
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.util.*

object BubbleManager {
    private val activeBubbles = mutableMapOf<String, BubbleData>()
    private var firestore: FirebaseFirestore? = null
    private var auth: FirebaseAuth? = null
    private val messageListeners = mutableMapOf<String, ListenerRegistration>()

    private var isServiceRunning = false

    private val bubblePositions = mutableMapOf<String, BubblePosition>()

    private var lastScreenWidth = 1080
    private var lastScreenHeight = 2400
    private var lastOrientation = Configuration.ORIENTATION_UNDEFINED

    private var prefs: SharedPreferences? = null
    private val gson = Gson()
    private const val PREFS_NAME = "bubble_manager_prefs"
    private const val KEY_ACTIVE_BUBBLES = "active_bubbles"
    private const val KEY_LAST_SAVE_TIME = "last_save_time"
    private const val EXPIRY_HOURS = 24L

    private const val BUBBLE_SIZE = 100
    private const val STACK_SPACING = 10
    private const val TOP_MARGIN = 200

    data class BubbleData(
        val userId: String,
        val userName: String,
        val avatarUrl: String,
        var unreadCount: Int = 0,
        var lastMessage: String = "",
        var timestamp: Long = System.currentTimeMillis()
    )

    data class BubblePosition(
        var x: Int,
        var y: Int,
        val userId: String
    )

    data class BubblePersistData(
        val userId: String,
        val userName: String,
        val avatarUrl: String,
        val unreadCount: Int,
        val lastMessage: String,
        val timestamp: Long,
        val positionX: Int,
        val positionY: Int
    )

    // ========================================
    // INITIALIZATION
    // ========================================
    fun init(context: Context) {
        try {
            firestore = FirebaseFirestore.getInstance()
            auth = FirebaseAuth.getInstance()
            prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            updateScreenDimensions(context)
            restoreBubbles(context)

            Log.d("BubbleManager", "✅ Initialized. Screen: ${lastScreenWidth}x${lastScreenHeight}")
        } catch (e: Exception) {
            Log.e("BubbleManager", "❌ Failed to init: $e")
        }
    }

    fun onConfigurationChanged(context: Context, newConfig: Configuration) {
        if (newConfig.orientation != lastOrientation) {
            Log.d("BubbleManager", "📱 Orientation changed")

            val oldWidth = lastScreenWidth
            val oldHeight = lastScreenHeight

            updateScreenDimensions(context)
            repositionBubblesForRotation(context, oldWidth, oldHeight)

            lastOrientation = newConfig.orientation
            saveBubbles()
        }
    }

    fun onAppResumed(context: Context) {
        Log.d("BubbleManager", "▶️ App resumed. Restoring bubble UIs.")

        activeBubbles.keys.toList().forEach { userId ->
            val bubble = activeBubbles[userId]
            if (bubble != null) {
                showBubble(context, userId, bubble.userName, bubble.avatarUrl)
            }
        }
    }

    fun onAppPaused() {
        Log.d("BubbleManager", "⏸️ App paused")
    }

    fun cleanup() {
        Log.d("BubbleManager", "🧹 Cleanup: Removing listeners and data.")
        messageListeners.values.forEach {
            try {
                it.remove()
            } catch (e: Exception) {}
        }
        messageListeners.clear()
        activeBubbles.clear()
        bubblePositions.clear()
        lastOrientation = Configuration.ORIENTATION_UNDEFINED
        isServiceRunning = false
        clearSavedBubbles()
    }

    // ========================================
    // SCREEN UTILS
    // ========================================
    private fun updateScreenDimensions(context: Context) {
        try {
            val displayMetrics = context.resources.displayMetrics
            val newWidth = displayMetrics.widthPixels
            val newHeight = displayMetrics.heightPixels

            if (newWidth > 0 && newHeight > 0) {
                lastScreenWidth = newWidth
                lastScreenHeight = newHeight
                Log.d("BubbleManager", "📱 Screen Updated: ${lastScreenWidth}x${lastScreenHeight}")
            }
        } catch (e: Exception) {
            Log.e("BubbleManager", "❌ Error updating screen dimensions: $e")
        }
    }

    private fun repositionBubblesForRotation(
        context: Context,
        oldWidth: Int,
        oldHeight: Int
    ) {
        if (activeBubbles.isEmpty()) return

        bubblePositions.forEach { (userId, position) ->
            val xPercent = if (oldWidth > 0) position.x.toFloat() / oldWidth else 0f
            val yPercent = if (oldHeight > 0) position.y.toFloat() / oldHeight else 0f

            position.x = (xPercent * lastScreenWidth).toInt()
            position.y = (yPercent * lastScreenHeight).toInt()

            position.x = position.x.coerceIn(0, lastScreenWidth - BUBBLE_SIZE)
            position.y = position.y.coerceIn(0, lastScreenHeight - BUBBLE_SIZE)

            val intent = Intent(context, BubbleOverlayService::class.java).apply {
                action = BubbleOverlayService.ACTION_UPDATE_BUBBLE_POSITION
                putExtra("userId", userId)
                putExtra("positionX", position.x)
                putExtra("positionY", position.y)
            }

            try {
                context.startService(intent)
            } catch (e: Exception) {
                Log.e("BubbleManager", "❌ Failed to reposition bubble $userId on rotation: $e")
            }
        }
    }

    // ========================================
    // PERSISTENCE
    // ========================================
    private fun saveBubbles() {
        try {
            val persistDataList = activeBubbles.mapNotNull { (userId, bubble) ->
                val position = bubblePositions[userId] ?: return@mapNotNull null
                BubblePersistData(
                    userId = bubble.userId,
                    userName = bubble.userName,
                    avatarUrl = bubble.avatarUrl,
                    unreadCount = bubble.unreadCount,
                    lastMessage = bubble.lastMessage,
                    timestamp = bubble.timestamp,
                    positionX = position.x,
                    positionY = position.y
                )
            }

            if (persistDataList.isNotEmpty()) {
                val json = gson.toJson(persistDataList)
                prefs?.edit()?.apply {
                    putString(KEY_ACTIVE_BUBBLES, json)
                    putLong(KEY_LAST_SAVE_TIME, System.currentTimeMillis())
                    apply()
                }
                Log.d("BubbleManager", "💾 Saved ${persistDataList.size} bubbles")
            } else {
                clearSavedBubbles()
            }
        } catch (e: Exception) {
            Log.e("BubbleManager", "❌ Failed to save bubbles: $e")
        }
    }

    private fun restoreBubbles(context: Context) {
        try {
            val json = prefs?.getString(KEY_ACTIVE_BUBBLES, null)
            if (json.isNullOrEmpty()) {
                Log.d("BubbleManager", "ℹ️ No saved bubbles")
                return
            }

            val lastSaveTime = prefs?.getLong(KEY_LAST_SAVE_TIME, 0) ?: 0
            val hoursSinceLastSave = (System.currentTimeMillis() - lastSaveTime) / (1000 * 60 * 60)

            if (hoursSinceLastSave > EXPIRY_HOURS) {
                Log.d("BubbleManager", "⏰ Saved bubbles too old ($hoursSinceLastSave h), clearing")
                clearSavedBubbles()
                return
            }

            val type = object : TypeToken<List<BubblePersistData>>() {}.type
            val persistDataList: List<BubblePersistData> = gson.fromJson(json, type)

            Log.d("BubbleManager", "📦 Restoring ${persistDataList.size} bubbles")

            persistDataList.forEach { data ->
                activeBubbles[data.userId] = BubbleData(
                    userId = data.userId,
                    userName = data.userName,
                    avatarUrl = data.avatarUrl,
                    unreadCount = data.unreadCount,
                    lastMessage = data.lastMessage,
                    timestamp = data.timestamp
                )

                bubblePositions[data.userId] = BubblePosition(
                    x = data.positionX,
                    y = data.positionY,
                    userId = data.userId
                )

                showBubble(
                    context = context,
                    userId = data.userId,
                    userName = data.userName,
                    avatarUrl = data.avatarUrl,
                    message = null
                )
            }
            Log.d("BubbleManager", "✅ Bubbles restored and services triggered")
        } catch (e: Exception) {
            Log.e("BubbleManager", "❌ Failed to restore bubbles: $e")
            clearSavedBubbles()
        }
    }

    fun clearSavedBubbles() {
        prefs?.edit()?.apply {
            remove(KEY_ACTIVE_BUBBLES)
            remove(KEY_LAST_SAVE_TIME)
            apply()
        }
        Log.d("BubbleManager", "🗑️ Cleared saved bubbles")
    }

    // ========================================
    // BUBBLE OPERATIONS
    // ========================================
    fun showBubble(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String,
        message: String? = null
    ) {
        Log.d("BubbleManager", "🎈 showBubble: $userName, Message: ${message != null}")

        val bubbleData = activeBubbles.getOrPut(userId) {
            listenToMessages(context, userId)
            BubbleData(userId, userName, avatarUrl)
        }

        message?.let {
            bubbleData.lastMessage = it
            bubbleData.unreadCount++
            bubbleData.timestamp = System.currentTimeMillis()
        }

        val position = calculateBubblePosition(context, userId)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Use Notification Service for Android 11+
            // This will be handled by BubbleNotificationService
            // Just track the bubble data here
        } else {
            // Fallback to WindowManager for Android < 11
            val intent = Intent(context, BubbleOverlayService::class.java).apply {
                action = BubbleOverlayService.ACTION_SHOW_BUBBLE
                putExtra("userId", userId)
                putExtra("userName", userName)
                putExtra("avatarUrl", avatarUrl)
                putExtra("unreadCount", bubbleData.unreadCount)
                putExtra("lastMessage", bubbleData.lastMessage)
                putExtra("positionX", position.x)
                putExtra("positionY", position.y)
            }

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
                isServiceRunning = true
            } catch (e: Exception) {
                Log.e("BubbleManager", "❌ Failed to start service: $e")
            }
        }

        saveBubbles()
        listenToMessages(context, userId)
    }

    private fun calculateBubblePosition(context: Context, userId: String): BubblePosition {
        bubblePositions[userId]?.let {
            return it
        }

        updateScreenDimensions(context)

        val margin = 20
        val x = (lastScreenWidth - BUBBLE_SIZE - margin).coerceAtLeast(margin)

        val orderedActiveUserIds = activeBubbles.keys.toList()
        val index = orderedActiveUserIds.indexOf(userId)

        val y = (TOP_MARGIN + (index * (BUBBLE_SIZE + STACK_SPACING)))
            .coerceIn(TOP_MARGIN, lastScreenHeight - BUBBLE_SIZE - margin)

        val position = BubblePosition(x, y, userId)
        bubblePositions[userId] = position

        Log.d("BubbleManager", "📍 New Position for $userId: x=$x, y=$y")

        return position
    }

    fun removeBubble(context: Context, userId: String) {
        Log.d("BubbleManager", "🗑️ Removing bubble: $userId")

        activeBubbles.remove(userId)
        bubblePositions.remove(userId)
        messageListeners.remove(userId)?.remove()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Will be handled by BubbleNotificationService
        } else {
            val intent = Intent(context, BubbleOverlayService::class.java).apply {
                action = BubbleOverlayService.ACTION_HIDE_BUBBLE
                putExtra("userId", userId)
            }

            try {
                context.startService(intent)
                Log.d("BubbleManager", "✅ Bubble removed: $userId")
            } catch (e: Exception) {
                Log.e("BubbleManager", "❌ Failed to send hide bubble intent: $e")
            }
        }

        repositionBubbles(context)

        if (activeBubbles.isEmpty()) {
            isServiceRunning = false
            clearSavedBubbles()
        } else {
            saveBubbles()
        }
    }

    private fun repositionBubbles(context: Context) {
        if (activeBubbles.isEmpty()) return

        val orderedActiveUserIds = activeBubbles.keys.toList()

        orderedActiveUserIds.forEachIndexed { index, userId ->
            val newY = TOP_MARGIN + (index * (BUBBLE_SIZE + STACK_SPACING))

            val position = bubblePositions[userId]
            if (position != null) {
                position.y = newY.coerceIn(TOP_MARGIN, lastScreenHeight - BUBBLE_SIZE - 20)

                val intent = Intent(context, BubbleOverlayService::class.java).apply {
                    action = BubbleOverlayService.ACTION_UPDATE_BUBBLE_POSITION
                    putExtra("userId", userId)
                    putExtra("positionX", position.x)
                    putExtra("positionY", position.y)
                }
                try {
                    context.startService(intent)
                } catch (e: Exception) {
                    Log.e("BubbleManager", "❌ Failed to reposition bubble $userId: $e")
                }
            }
        }
    }

    fun updateBubblePosition(userId: String, x: Int, y: Int) {
        bubblePositions[userId]?.apply {
            this.x = x
            this.y = y
        }
        saveBubbles()
        Log.d("BubbleManager", "📍 Updated position for $userId: ($x, $y)")
    }

    fun markAsRead(context: Context, userId: String) {
        activeBubbles[userId]?.unreadCount = 0

        val intent = Intent(context, BubbleOverlayService::class.java).apply {
            action = BubbleOverlayService.ACTION_UPDATE_BUBBLE
            putExtra("userId", userId)
            putExtra("unreadCount", 0)
            putExtra("lastMessage", activeBubbles[userId]?.lastMessage ?: "")
        }
        try {
            context.startService(intent)
            saveBubbles()
        } catch (e: Exception) {
            Log.e("BubbleManager", "❌ Failed to send markAsRead intent: $e")
        }
    }

    // ========================================
    // FIREBASE LOGIC
    // ========================================
    private fun listenToMessages(context: Context, userId: String) {
        if (messageListeners.containsKey(userId)) {
            return
        }

        val currentUserId = getCurrentUserId() ?: return
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
                        return@addSnapshotListener
                    }

                    snapshot?.documentChanges?.forEach { change ->
                        if (change.type == DocumentChange.Type.ADDED) {
                            val message = change.document.getString("content") ?: ""
                            val type = change.document.getLong("type")?.toInt() ?: 0

                            activeBubbles[userId]?.let { bubble ->
                                bubble.lastMessage = if (type == 0) message else "📷 Image"
                                bubble.unreadCount++
                                bubble.timestamp = System.currentTimeMillis()

                                notifyBubbleUpdate(context, userId, bubble)
                                saveBubbles()
                            }
                        }
                    }
                }

            listener?.let { messageListeners[userId] = it }
            Log.d("BubbleManager", "✅ Listener setup: $userId")
        } catch (e: Exception) {
            Log.e("BubbleManager", "❌ Failed to setup listener: $e")
        }
    }

    private fun notifyBubbleUpdate(context: Context, userId: String, bubble: BubbleData) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Will be handled by BubbleNotificationService
        } else {
            val intent = Intent(context, BubbleOverlayService::class.java).apply {
                action = BubbleOverlayService.ACTION_UPDATE_BUBBLE
                putExtra("userId", userId)
                putExtra("unreadCount", bubble.unreadCount)
                putExtra("lastMessage", bubble.lastMessage)
            }

            try {
                context.startService(intent)
            } catch (e: Exception) {
                Log.e("BubbleManager", "❌ Failed to notify update: $e")
            }
        }
    }

    // ========================================
    // GETTERS
    // ========================================
    fun getCurrentUserId(): String? {
        return try {
            auth?.currentUser?.uid
        } catch (e: Exception) {
            null
        }
    }

    fun isBubbleActive(userId: String): Boolean {
        return activeBubbles.containsKey(userId)
    }

    fun getActiveBubbles(): Map<String, BubbleData> {
        return activeBubbles.toMap()
    }
}
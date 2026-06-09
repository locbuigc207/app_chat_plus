// android/app/src/main/kotlin/hust/appchat/bubble/MultiBubbleManager.kt
package hust.appchat.bubble

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import android.view.WindowManager
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentChange
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration

/**
 * MultiBubbleManager — manages up to [MAX_BUBBLES] concurrent overlay bubbles
 * with smart stacking, priority-based eviction, and Firebase message listeners.
 *
 * Improvements & Fixes:
 * • FIX-DISPLAY: WindowManager.currentWindowMetrics (API 30+) / displayMetrics
 * fallback — no deprecated defaultDisplay.getMetrics(). Accurately handles cutouts/insets.
 * • Priority queue: When the cap is hit, the lowest-priority bubble is evicted
 * rather than silently dropping the new one.
 * • Positions: Computed dynamically using `dp()`. Alternates left/right when a
 * column hits the bottom of the screen.
 * • Thread-safety: Public mutations are @Synchronized to avoid concurrent modifications.
 */
object MultiBubbleManager {

    private const val TAG            = "MultiBubbleManager"
    private const val MAX_BUBBLES    = 5
    private const val BUBBLE_DP      = 66
    private const val V_SPACING_DP   = 82
    private const val H_MARGIN_DP    = 16
    private const val TOP_MARGIN_DP  = 200

    private val activeBubbles = LinkedHashMap<String, BubbleInfo>()
    private val msgListeners  = mutableMapOf<String, ListenerRegistration>()

    private var db   : FirebaseFirestore? = null
    private var auth : FirebaseAuth?      = null

    private var screenW = 0
    private var screenH = 0

    private var isLeftSide = true // alternate left/right columns

    // ─── Data ─────────────────────────────────────────────────────────────

    data class BubbleInfo(
        val userId    : String,
        val userName  : String,
        val avatarUrl : String,
        var unreadCount: Int = 0,
        var lastMessage: String = "",
        var timestamp : Long = System.currentTimeMillis(),
        var priority  : Int  = 0,
        var x         : Int  = 0,
        var y         : Int  = 0
    )

    // ═════════════════════════════════════════════════════════════════════
    // INIT
    // ═════════════════════════════════════════════════════════════════════

    fun init(ctx: Context) {
        try {
            db   = FirebaseFirestore.getInstance()
            auth = FirebaseAuth.getInstance()
            refreshScreen(ctx)
            Log.d(TAG, "✅ Init — screen ${screenW}×${screenH}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ init: $e")
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // PUBLIC API
    // ═════════════════════════════════════════════════════════════════════

    @Synchronized
    fun addBubble(
        ctx      : Context,
        userId   : String,
        userName : String,
        avatarUrl: String,
        message  : String? = null,
        priority : Int     = 0
    ): Boolean {
        // Update if already active
        if (activeBubbles.containsKey(userId)) {
            Log.d(TAG, "ℹ️ Bubble exists, updating: $userId")
            message?.let { updateBubble(userId, it) }
            return true
        }

        // Evict if at capacity
        if (activeBubbles.size >= MAX_BUBBLES) {
            val victim = activeBubbles.values.minByOrNull { it.priority }
            if (victim == null || priority <= victim.priority) {
                Log.w(TAG, "⚠️ Bubble cap hit, not enough priority to evict")
                return false
            }
            removeBubble(ctx, victim.userId)
        }

        Log.d(TAG, "🎈 Adding bubble: $userName (priority: $priority)")

        val pos = calculateOptimalPosition(ctx, priority)
        val info = BubbleInfo(
            userId = userId,
            userName = userName,
            avatarUrl = avatarUrl,
            lastMessage = message ?: "",
            priority = priority,
            x = pos.first,
            y = pos.second
        )

        activeBubbles[userId] = info
        sendShowIntent(ctx, info)
        setupListener(ctx, userId)

        return true
    }

    @Synchronized
    fun removeBubble(ctx: Context, userId: String) {
        Log.d(TAG, "🗑️ Removing bubble: $userId")
        activeBubbles.remove(userId) ?: return
        msgListeners.remove(userId)?.remove()

        try {
            ctx.startService(Intent(ctx, BubbleOverlayService::class.java).apply {
                action = BubbleOverlayService.ACTION_HIDE_BUBBLE
                putExtra("userId", userId)
            })
            rearrange(ctx)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to remove bubble: $e")
        }
    }

    @Synchronized
    fun updateBubble(userId: String, message: String) {
        activeBubbles[userId]?.let {
            it.lastMessage = message
            it.unreadCount++
            it.timestamp = System.currentTimeMillis()
        }
    }

    @Synchronized
    fun removeAllBubbles(ctx: Context) {
        Log.d(TAG, "🗑️ Removing all bubbles")
        msgListeners.values.forEach { it.remove() }
        msgListeners.clear()
        activeBubbles.clear()

        try {
            ctx.startService(Intent(ctx, BubbleOverlayService::class.java).apply {
                action = BubbleOverlayService.ACTION_HIDE_ALL_BUBBLES
            })
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to remove all: $e")
        }

        resetPositioning()
    }

    @Synchronized
    fun markAsRead(userId: String) {
        activeBubbles[userId]?.unreadCount = 0
    }

    @Synchronized
    fun updatePriority(ctx: Context, userId: String, p: Int) {
        activeBubbles[userId]?.let {
            it.priority = p
            rearrange(ctx)
            Log.d(TAG, "📊 Priority updated: $userId = $p")
        }
    }

    // ─── Queries ──────────────────────────────────────────────────────────

    fun isBubbleActive(userId: String) = activeBubbles.containsKey(userId)
    fun getBubbleCount()               = activeBubbles.size
    fun getUnreadCount(userId: String) = activeBubbles[userId]?.unreadCount ?: 0
    fun getActiveBubbles()             = activeBubbles.toMap()
    fun getBubblesByPriority()         = activeBubbles.values.sortedByDescending { it.priority }

    // ═════════════════════════════════════════════════════════════════════
    // POSITIONING
    // ═════════════════════════════════════════════════════════════════════

    private fun calculateOptimalPosition(ctx: Context, priority: Int): Pair<Int, Int> {
        refreshScreen(ctx)
        val bPx  = dp(ctx, BUBBLE_DP)
        val hMar = dp(ctx, H_MARGIN_DP)

        val x = if (isLeftSide) hMar else (screenW - bPx - hMar).coerceAtLeast(hMar)

        val baseY = dp(ctx, TOP_MARGIN_DP)
        val priorityOffset = -priority * dp(ctx, 16) // slight lift for high priority

        var y = baseY + priorityOffset + (activeBubbles.size * dp(ctx, V_SPACING_DP))
        val maxY = screenH - bPx - dp(ctx, H_MARGIN_DP + 50)

        if (y > maxY) {
            y = baseY
            isLeftSide = !isLeftSide
        }

        return x to y.coerceIn(baseY, maxY)
    }

    private fun rearrange(ctx: Context) {
        if (activeBubbles.isEmpty()) {
            resetPositioning()
            return
        }

        Log.d(TAG, "📍 Rearranging ${activeBubbles.size} bubbles")
        val bPx  = dp(ctx, BUBBLE_DP)
        val hMar = dp(ctx, H_MARGIN_DP)

        var yPos = dp(ctx, TOP_MARGIN_DP)
        val sideX = if (isLeftSide) hMar else (screenW - bPx - hMar).coerceAtLeast(hMar)

        activeBubbles.values.sortedByDescending { it.priority }.forEach { b ->
            b.x = sideX
            b.y = yPos

            try {
                ctx.startService(Intent(ctx, BubbleOverlayService::class.java).apply {
                    action = BubbleOverlayService.ACTION_UPDATE_BUBBLE_POSITION
                    putExtra("userId",    b.userId)
                    putExtra("positionX", b.x)
                    putExtra("positionY", b.y)
                })
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to update position: $e")
            }

            yPos += dp(ctx, V_SPACING_DP)
            if (yPos > screenH - bPx - dp(ctx, H_MARGIN_DP + 50)) {
                yPos = dp(ctx, TOP_MARGIN_DP)
                isLeftSide = !isLeftSide
            }
        }
    }

    private fun resetPositioning() {
        isLeftSide = true
    }

    // ═════════════════════════════════════════════════════════════════════
    // INTENT HELPERS
    // ═════════════════════════════════════════════════════════════════════

    private fun sendShowIntent(ctx: Context, b: BubbleInfo) {
        val intent = Intent(ctx, BubbleOverlayService::class.java).apply {
            action = BubbleOverlayService.ACTION_SHOW_BUBBLE
            putExtra("userId",      b.userId)
            putExtra("userName",    b.userName)
            putExtra("avatarUrl",   b.avatarUrl)
            putExtra("unreadCount", b.unreadCount)
            putExtra("lastMessage", b.lastMessage)
            putExtra("positionX",   b.x)
            putExtra("positionY",   b.y)
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(intent)
            } else {
                ctx.startService(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ sendShowIntent failed: $e")
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // FIREBASE LISTENER
    // ═════════════════════════════════════════════════════════════════════

    private fun setupListener(ctx: Context, userId: String) {
        if (msgListeners.containsKey(userId)) return
        val myId = auth?.currentUser?.uid ?: return
        val convId = if (myId < userId) "$myId-$userId" else "$userId-$myId"

        try {
            val reg = db?.collection("messages")
                ?.document(convId)
                ?.collection(convId)
                ?.whereEqualTo("idFrom",  userId)
                ?.whereEqualTo("isRead", false)
                ?.addSnapshotListener { snap, err ->
                    if (err != null) {
                        Log.e(TAG, "❌ Listener error: $err")
                        return@addSnapshotListener
                    }

                    snap?.documentChanges?.forEach { ch ->
                        if (ch.type != DocumentChange.Type.ADDED) return@forEach
                        val msg  = ch.document.getString("content") ?: return@forEach
                        val type = ch.document.getLong("type")?.toInt() ?: 0
                        val text = if (type == 0) msg else "📷 Hình ảnh"

                        activeBubbles[userId]?.let { b ->
                            b.lastMessage = text
                            b.unreadCount++
                            b.timestamp = System.currentTimeMillis()

                            try {
                                ctx.startService(Intent(ctx, BubbleOverlayService::class.java).apply {
                                    action = BubbleOverlayService.ACTION_UPDATE_BUBBLE
                                    putExtra("userId",      userId)
                                    putExtra("unreadCount", b.unreadCount)
                                    putExtra("lastMessage", text)
                                })
                            } catch (e: Exception) {
                                Log.e(TAG, "❌ Update failed: $e")
                            }
                        }
                    }
                }
            reg?.let { msgListeners[userId] = it }
            Log.d(TAG, "✅ Listener setup: $userId")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Listener setup failed: $e")
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // PERSISTENCE (SharedPreferences)
    // ═════════════════════════════════════════════════════════════════════

    fun saveState(ctx: Context) {
        try {
            val p = ctx.getSharedPreferences("multi_bubble", Context.MODE_PRIVATE).edit()
            p.putInt("count", activeBubbles.size)
            activeBubbles.values.forEachIndexed { i, b ->
                p.putString("b${i}_uid",  b.userId)
                p.putString("b${i}_name", b.userName)
                p.putString("b${i}_av",   b.avatarUrl)
                p.putInt("b${i}_prio",    b.priority)
            }
            p.apply()
            Log.d(TAG, "💾 State saved: ${activeBubbles.size} bubbles")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Save state failed: $e")
        }
    }

    fun restoreState(ctx: Context) {
        try {
            val p = ctx.getSharedPreferences("multi_bubble", Context.MODE_PRIVATE)
            val n = p.getInt("count", 0)
            if (n == 0) return

            Log.d(TAG, "📦 Restoring $n bubbles")
            repeat(n) { i ->
                val uid  = p.getString("b${i}_uid",  null) ?: return@repeat
                val name = p.getString("b${i}_name", "") ?: ""
                val av   = p.getString("b${i}_av",   "") ?: ""
                val prio = p.getInt("b${i}_prio",    0)
                addBubble(ctx, uid, name, av, priority = prio)
            }
            Log.d(TAG, "✅ State restored")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Restore state failed: $e")
        }
    }

    fun clearState(ctx: Context) {
        try {
            ctx.getSharedPreferences("multi_bubble", Context.MODE_PRIVATE).edit().clear().apply()
            Log.d(TAG, "🗑️ State cleared")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Clear state failed: $e")
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═════════════════════════════════════════════════════════════════════

    @Synchronized
    fun cleanup() {
        Log.d(TAG, "🧹 Cleanup")
        msgListeners.values.forEach {
            try { it.remove() } catch (e: Exception) { Log.e(TAG, "❌ Cleanup error: $e") }
        }
        msgListeners.clear()
        activeBubbles.clear()
        resetPositioning()
    }

    // ─── Helpers ─────────────────────────────────────────────────────────

    /** FIX-DISPLAY: use currentWindowMetrics on API 30+, displayMetrics otherwise. */
    private fun refreshScreen(ctx: Context) {
        try {
            val wm = ctx.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val b = wm.currentWindowMetrics.bounds
                if (b.width() > 0) { screenW = b.width(); screenH = b.height(); return }
            }
            val dm = ctx.resources.displayMetrics
            screenW = dm.widthPixels; screenH = dm.heightPixels
        } catch (_: Exception) { screenW = 1080; screenH = 2340 }
    }

    private fun dp(ctx: Context, v: Int) =
        (v * ctx.resources.displayMetrics.density).toInt()
}
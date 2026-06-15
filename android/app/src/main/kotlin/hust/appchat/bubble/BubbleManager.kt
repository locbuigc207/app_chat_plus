// android/app/src/main/kotlin/hust/appchat/bubble/BubbleManager.kt
package hust.appchat.bubble

import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.os.Build
import android.util.Log
import android.view.WindowManager
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.DocumentChange
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.ListenerRegistration
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.util.concurrent.ConcurrentHashMap

object BubbleManager {

    private const val TAG          = "BubbleManager"
    private const val PREF_NAME    = "bm_state"
    private const val PREF_BUBBLES = "bubbles"
    private const val PREF_SAVED   = "saved_at"
    private const val EXPIRY_MS    = 24L * 60 * 60 * 1_000   // 24 h

    private const val BUBBLE_DP    = 66
    private const val SPACING_DP   = 82
    private const val H_MARGIN_DP  = 14
    private const val TOP_DP       = 200

    // ─── Registry ─────────────────────────────────────────────────────────
    private val registry    = ConcurrentHashMap<String, BubbleEntry>()
    private val positions   = ConcurrentHashMap<String, Pair<Int, Int>>()
    private val listeners   = mutableMapOf<String, ListenerRegistration>()

    var isServiceRunning = false
        private set

    // ─── Dependencies ─────────────────────────────────────────────────────
    private var db   : FirebaseFirestore? = null
    private var auth : FirebaseAuth?      = null
    private var prefs: SharedPreferences? = null
    private val gson = Gson()

    // ─── Screen ───────────────────────────────────────────────────────────
    private var screenW     = 0
    private var screenH     = 0
    private var orientation = Configuration.ORIENTATION_UNDEFINED

    // ─── Data ──────────────────────────────────────────────────────────────

    data class BubbleEntry(
        val userId   : String,
        val userName : String,
        val avatarUrl: String,
        var lastMsg  : String = "",
        var unread   : Int    = 0,
        var ts       : Long   = System.currentTimeMillis(),
    )

    // Persisted form
    private data class PersistedEntry(
        val userId   : String,
        val userName : String,
        val avatarUrl: String,
        val lastMsg  : String,
        val unread   : Int,
        val ts       : Long,
        val posX     : Int,
        val posY     : Int,
    )

    // ═════════════════════════════════════════════════════════════════════
    // INIT
    // ═════════════════════════════════════════════════════════════════════

    @Synchronized
    fun init(ctx: Context) {
        if (db != null) return          // idempotent
        try {
            db    = FirebaseFirestore.getInstance()
            auth  = FirebaseAuth.getInstance()
            prefs = ctx.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            refreshScreen(ctx)
            restoreState(ctx)
            Log.d(TAG, "✅ BubbleManager init — screen ${screenW}×${screenH}")
        } catch (e: Exception) { Log.e(TAG, "❌ init: $e") }
    }

    // ═════════════════════════════════════════════════════════════════════
    // SHOW / UPDATE BUBBLE
    // ═════════════════════════════════════════════════════════════════════

    @Synchronized
    fun showBubble(
        ctx      : Context,
        userId   : String,
        userName : String,
        avatarUrl: String,
        message  : String? = null,
    ) {
        val entry = registry.getOrPut(userId) {
            BubbleEntry(userId, userName, avatarUrl)
        }
        message?.let {
            entry.lastMsg = it
            entry.unread++
            entry.ts = System.currentTimeMillis()
        }

        val pos = positionFor(ctx, userId)
        sendService(ctx, Intent(ctx, BubbleOverlayService::class.java).apply {
            action = BubbleOverlayService.ACTION_SHOW_BUBBLE
            putExtra("userId",      userId)
            putExtra("userName",    userName)
            putExtra("avatarUrl",   avatarUrl)
            putExtra("unreadCount", entry.unread)
            putExtra("lastMessage", entry.lastMsg)
            putExtra("positionX",   pos.first)
            putExtra("positionY",   pos.second)
        })

        setupListener(ctx, userId)
        persist()
        Log.d(TAG, "🎈 showBubble: $userName unread=${entry.unread}")
    }

    @Synchronized
    fun removeBubble(ctx: Context, userId: String) {
        registry.remove(userId)
        positions.remove(userId)
        listeners.remove(userId)?.remove()

        sendService(ctx, Intent(ctx, BubbleOverlayService::class.java).apply {
            action = BubbleOverlayService.ACTION_HIDE_BUBBLE
            putExtra("userId", userId)
        })

        restack(ctx)

        if (registry.isEmpty()) {
            isServiceRunning = false
            clearPersisted()
        } else {
            persist()
        }
        Log.d(TAG, "🗑️ removeBubble: $userId")
    }

    @Synchronized
    fun updateBubble(ctx: Context, userId: String, message: String, newUnread: Int = -1) {
        val entry = registry[userId] ?: return
        entry.lastMsg = message
        entry.ts      = System.currentTimeMillis()
        if (newUnread >= 0) entry.unread = newUnread else entry.unread++

        sendService(ctx, Intent(ctx, BubbleOverlayService::class.java).apply {
            action = BubbleOverlayService.ACTION_UPDATE_BUBBLE
            putExtra("userId",      userId)
            putExtra("unreadCount", entry.unread)
            putExtra("lastMessage", entry.lastMsg)
        })
        persist()
    }

    @Synchronized
    fun markAsRead(ctx: Context, userId: String) {
        val entry = registry[userId] ?: return
        entry.unread = 0

        sendService(ctx, Intent(ctx, BubbleOverlayService::class.java).apply {
            action = BubbleOverlayService.ACTION_UPDATE_BUBBLE
            putExtra("userId",      userId)
            putExtra("unreadCount", 0)
            putExtra("lastMessage", entry.lastMsg)
        })
        persist()
    }

    // ═════════════════════════════════════════════════════════════════════
    // POSITION MANAGEMENT
    // ═════════════════════════════════════════════════════════════════════

    private fun positionFor(ctx: Context, userId: String): Pair<Int, Int> {
        positions[userId]?.let { return it }
        refreshScreen(ctx)

        val bPx   = dp(ctx, BUBBLE_DP)
        val hMar  = dp(ctx, H_MARGIN_DP)
        val index = registry.size - 1

        val x     = (screenW - bPx - hMar).coerceAtLeast(hMar)
        val y     = (dp(ctx, TOP_DP) + index * dp(ctx, SPACING_DP))
            .coerceAtMost(screenH - bPx - hMar)

        return (x to y).also { positions[userId] = it }
    }

    private fun restack(ctx: Context) {
        if (registry.isEmpty()) return

        val bPx  = dp(ctx, BUBBLE_DP)
        val hMar = dp(ctx, H_MARGIN_DP)

        registry.keys.toList().forEachIndexed { i, uid ->
            val newY = (dp(ctx, TOP_DP) + i * dp(ctx, SPACING_DP))
                .coerceAtMost(screenH - bPx - hMar)
            positions[uid] = (positions[uid]?.first ?: (screenW - bPx - hMar)) to newY

            sendService(ctx, Intent(ctx, BubbleOverlayService::class.java).apply {
                action = BubbleOverlayService.ACTION_UPDATE_BUBBLE_POSITION
                putExtra("userId",    uid)
                putExtra("positionX", positions[uid]!!.first)
                putExtra("positionY", positions[uid]!!.second)
            })
        }
    }

    fun updateBubblePosition(userId: String, x: Int, y: Int) {
        positions[userId] = x to y
        persist()
        Log.d(TAG, "📍 Updated position for $userId: ($x, $y)")
    }

    // ═════════════════════════════════════════════════════════════════════
    // CONFIGURATION CHANGE (rotation & DeX)
    // ═════════════════════════════════════════════════════════════════════

    fun onConfigurationChanged(ctx: Context, cfg: Configuration) {
        val oldW = screenW
        val oldH = screenH
        refreshScreen(ctx)

        // ĐÃ SỬA: Check sự thay đổi của cả kích thước màn hình để hỗ trợ Samsung DeX (DeX không đổi orientation)
        if (cfg.orientation == orientation && oldW == screenW && oldH == screenH) return

        orientation = cfg.orientation

        if (oldW == 0 || oldH == 0) return

        // Remap positions proportionally
        positions.replaceAll { _, pos ->
            val nx = ((pos.first.toFloat() / oldW) * screenW).toInt()
                .coerceIn(dp(ctx, H_MARGIN_DP), screenW - dp(ctx, BUBBLE_DP + H_MARGIN_DP))
            val ny = ((pos.second.toFloat() / oldH) * screenH).toInt()
                .coerceIn(dp(ctx, TOP_DP), screenH - dp(ctx, BUBBLE_DP + H_MARGIN_DP))
            nx to ny
        }

        restack(ctx)
        persist()
        Log.d(TAG, "📱 Resolution/Rotation changed → ${screenW}×${screenH}")
    }

    // ═════════════════════════════════════════════════════════════════════
    // LIFECYCLE
    // ═════════════════════════════════════════════════════════════════════

    fun onAppResumed(ctx: Context) {
        // ĐÃ SỬA: Bỏ qua hoàn toàn trên Android 11+ vì BubbleNotificationService đã quản lý việc khôi phục
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return
        }

        Log.d(TAG, "▶️ onAppResumed — restoring ${registry.size} bubble(s)")
        registry.values.forEach { e ->
            val pos = positions[e.userId] ?: positionFor(ctx, e.userId)
            sendService(ctx, Intent(ctx, BubbleOverlayService::class.java).apply {
                action = BubbleOverlayService.ACTION_SHOW_BUBBLE
                putExtra("userId",      e.userId)
                putExtra("userName",    e.userName)
                putExtra("avatarUrl",   e.avatarUrl)
                putExtra("unreadCount", e.unread)
                putExtra("lastMessage", e.lastMsg)
                putExtra("positionX",   pos.first)
                putExtra("positionY",   pos.second)
            })
        }
    }

    fun onAppPaused() { Log.d(TAG, "⏸️ onAppPaused") }

    @Synchronized
    fun cleanup() {
        listeners.values.forEach { try { it.remove() } catch (_: Exception) {} }
        listeners.clear()
        registry.clear()
        positions.clear()
        orientation = Configuration.ORIENTATION_UNDEFINED
        isServiceRunning = false
        clearPersisted()
        Log.d(TAG, "🧹 cleanup")
    }

    // ═════════════════════════════════════════════════════════════════════
    // FIREBASE LISTENERS
    // ═════════════════════════════════════════════════════════════════════

    private fun setupListener(ctx: Context, userId: String) {
        if (listeners.containsKey(userId)) return
        val myId = auth?.currentUser?.uid ?: return
        val conv = if (myId < userId) "$myId-$userId" else "$userId-$myId"

        val reg = db?.collection("messages")
            ?.document(conv)
            ?.collection(conv)
            ?.whereEqualTo("idFrom",  userId)
            ?.whereEqualTo("isRead", false)
            ?.addSnapshotListener { snap, err ->
                if (err != null) { Log.e(TAG, "Listener: $err"); return@addSnapshotListener }
                snap?.documentChanges?.forEach { ch ->
                    if (ch.type != DocumentChange.Type.ADDED) return@forEach
                    val msg  = ch.document.getString("content") ?: return@forEach
                    val type = ch.document.getLong("type")?.toInt() ?: 0
                    val text = if (type == 0) msg else "📷 Hình ảnh"
                    updateBubble(ctx, userId, text)
                }
            }
        reg?.let { listeners[userId] = it }
        Log.d(TAG, "✅ Listener setup: $userId")
    }

    // ═════════════════════════════════════════════════════════════════════
    // PERSISTENCE
    // ═════════════════════════════════════════════════════════════════════

    private fun persist() {
        try {
            val list = registry.values.mapNotNull { e ->
                val pos = positions[e.userId] ?: return@mapNotNull null
                PersistedEntry(e.userId, e.userName, e.avatarUrl,
                    e.lastMsg, e.unread, e.ts, pos.first, pos.second)
            }
            if (list.isNotEmpty()) {
                prefs?.edit()
                    ?.putString(PREF_BUBBLES, gson.toJson(list))
                    ?.putLong(PREF_SAVED, System.currentTimeMillis())
                    ?.apply()
                Log.d(TAG, "💾 Saved ${list.size} bubbles")
            } else {
                clearPersisted()
            }
        } catch (e: Exception) { Log.e(TAG, "❌ persist: $e") }
    }

    private fun restoreState(ctx: Context) {
        try {
            val savedAt = prefs?.getLong(PREF_SAVED, 0) ?: 0
            if (System.currentTimeMillis() - savedAt > EXPIRY_MS) {
                Log.d(TAG, "⏰ Persisted data expired"); clearPersisted(); return
            }
            val json = prefs?.getString(PREF_BUBBLES, null)
            if (json.isNullOrEmpty()) {
                Log.d(TAG, "ℹ️ No saved bubbles")
                return
            }

            val type = object : TypeToken<List<PersistedEntry>>() {}.type
            val list : List<PersistedEntry> = gson.fromJson(json, type)

            var restored = 0
            list.forEach { p ->
                if (p.userId.isEmpty() || p.userName.isEmpty()) return@forEach
                registry[p.userId] = BubbleEntry(p.userId, p.userName, p.avatarUrl,
                    p.lastMsg, p.unread, p.ts)
                positions[p.userId] = p.posX to p.posY
                restored++
            }
            Log.d(TAG, "📦 Restored $restored bubble(s)")
        } catch (e: Exception) { Log.e(TAG, "❌ restoreState: $e"); clearPersisted() }
    }

    fun clearPersisted() {
        prefs?.edit()?.remove(PREF_BUBBLES)?.remove(PREF_SAVED)?.apply()
        Log.d(TAG, "🗑️ Cleared saved bubbles")
    }

    // ═════════════════════════════════════════════════════════════════════
    // QUERIES
    // ═════════════════════════════════════════════════════════════════════

    fun isBubbleActive(userId: String) = registry.containsKey(userId)
    fun getActiveBubbles()             = registry.toMap()
    fun getCurrentUserId()             = try { auth?.currentUser?.uid } catch (_: Exception) { null }

    // ═════════════════════════════════════════════════════════════════════
    // HELPERS
    // ═════════════════════════════════════════════════════════════════════

    private fun sendService(ctx: Context, i: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Use Notification Service for Android 11+
            // Handled by BubbleNotificationService, skip starting Overlay Service
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                ctx.startForegroundService(i)
            } else {
                ctx.startService(i)
            }
            isServiceRunning = true
        } catch (e: Exception) { Log.e(TAG, "❌ sendService ${i.action}: $e") }
    }

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
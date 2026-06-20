// android/app/src/main/kotlin/hust/appchat/shortcuts/ShortcutHelper.kt
package hust.appchat.shortcuts

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import hust.appchat.BubbleActivity
import kotlinx.coroutines.*

@RequiresApi(Build.VERSION_CODES.R)
object ShortcutHelper {

    private const val TAG = "ShortcutHelper"
    private const val MAX_SHORTCUTS = 5

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // ========================================
    // PUBLIC API
    // ========================================

    fun isShortcutsSupported() = true // Luôn true trên minSdk 30

    fun getShortcutCount(context: Context): Int {
        return try {
            context.getSystemService(ShortcutManager::class.java)
                ?.dynamicShortcuts?.size ?: 0
        } catch (e: Exception) {
            Log.e(TAG, "❌ getShortcutCount: $e")
            0
        }
    }

    fun canCreateMoreShortcuts(context: Context) = getShortcutCount(context) < MAX_SHORTCUTS

    fun shortcutExists(context: Context, userId: String): Boolean {
        return try {
            context.getSystemService(ShortcutManager::class.java)
                ?.dynamicShortcuts?.any { it.id == userId } ?: false
        } catch (e: Exception) {
            false
        }
    }

    /** Fire-and-forget shortcut creation */
    fun createShortcut(
        context: Context, userId: String, userName: String, avatarUrl: String
    ) {
        scope.launch {
            try {
                createModernShortcut(context, userId, userName, avatarUrl)
            } catch (e: Exception) {
                Log.e(TAG, "❌ createShortcut: $e")
            }
        }
    }

    /** Suspending version for coroutine usage */
    suspend fun createShortcutSuspend(
        context: Context, userId: String, userName: String, avatarUrl: String
    ) = withContext(Dispatchers.Main) {
        createModernShortcut(context, userId, userName, avatarUrl)
    }

    fun removeShortcut(context: Context, userId: String) {
        try {
            context.getSystemService(ShortcutManager::class.java)
                ?.removeDynamicShortcuts(listOf(userId))
            Log.d(TAG, "✅ Shortcut removed: $userId")
        } catch (e: Exception) {
            Log.e(TAG, "❌ removeShortcut: $e")
        }
    }

    fun removeAllShortcuts(context: Context) {
        try {
            context.getSystemService(ShortcutManager::class.java)
                ?.removeAllDynamicShortcuts()
            AvatarLoader.clearAllCache()
            Log.d(TAG, "✅ All shortcuts removed")
        } catch (e: Exception) {
            Log.e(TAG, "❌ removeAllShortcuts: $e")
        }
    }

    fun updateShortcut(context: Context, userId: String, userName: String, avatarUrl: String) {
        removeShortcut(context, userId)
        createShortcut(context, userId, userName, avatarUrl)
    }

    suspend fun ensureShortcutForNotification(
        context: Context, userId: String, userName: String, avatarUrl: String
    ) {
        if (!shortcutExists(context, userId)) {
            Log.d(TAG, "🔗 Creating missing shortcut: $userName")
            createShortcutSuspend(context, userId, userName, avatarUrl)

            // Polling thay vì hard delay để theo dõi chính xác trạng thái
            repeat(20) {
                if (shortcutExists(context, userId)) return
                delay(100)
            }
        }
    }

    fun refreshShortcutAvatar(
        context: Context, userId: String, userName: String, avatarUrl: String
    ) {
        scope.launch {
            try {
                AvatarLoader.clearCache(avatarUrl, userName)
                updateShortcut(context, userId, userName, avatarUrl)
                Log.d(TAG, "✅ Avatar refreshed: $userName")
            } catch (e: Exception) {
                Log.e(TAG, "❌ refreshAvatar: $e")
            }
        }
    }

    /** Batch creation with parallel avatar preloading */
    suspend fun createShortcutsBatch(
        context: Context, users: List<Triple<String, String, String>>
    ) = withContext(Dispatchers.IO) {
        // 1. Preload all avatars in parallel
        AvatarLoader.preloadAvatarsBatch(
            context,
            users.map { (_, name, url) -> url to name }
        )

        // 2. Create shortcuts sequentially on Main thread
        withContext(Dispatchers.Main) {
            users.forEach { (uid, name, url) ->
                if (!shortcutExists(context, uid)) {
                    try {
                        createModernShortcut(context, uid, name, url)
                        delay(80) // Prevent overwhelming the system
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ batch creation failed for $name: $e")
                    }
                }
            }
        }
        Log.d(TAG, "✅ Batch shortcuts created (${users.size})")
    }

    fun getShortcutsInfo(context: Context): List<Map<String, String>> {
        return try {
            context.getSystemService(ShortcutManager::class.java)
                ?.dynamicShortcuts
                ?.map {
                    mapOf(
                        "id" to it.id,
                        "label" to (it.shortLabel?.toString() ?: ""),
                        "rank" to it.rank.toString()
                    )
                } ?: emptyList()
        } catch (e: Exception) {
            Log.e(TAG, "❌ getShortcutsInfo error: $e")
            emptyList()
        }
    }

    fun clearShortcutAvatarCache(avatarUrl: String, userName: String) {
        AvatarLoader.clearCache(avatarUrl, userName)
        Log.d(TAG, "🗑️ Cleared shortcut avatar cache for: $userName")
    }

    fun getAvatarCacheStats(): Map<String, Any> {
        return AvatarLoader.getCacheStats()
    }

    fun cleanup() {
        scope.coroutineContext.cancelChildren()
        Log.d(TAG, "✅ ShortcutHelper cleanup complete")
    }

    // ========================================
    // PRIVATE IMPLEMENTATION
    // ========================================

    private suspend fun createModernShortcut(
        context: Context, userId: String, userName: String, avatarUrl: String
    ) = withContext(Dispatchers.IO) {

        // Evict oldest if at capacity
        if (getShortcutCount(context) >= MAX_SHORTCUTS) {
            evictOldest(context)
        }

        val icon = AvatarLoader.loadAvatarIcon(context, avatarUrl, userName)

        val person = android.app.Person.Builder()
            .setName(userName)
            .setKey(userId)
            .setIcon(icon)
            .setImportant(true)
            .build()

        val intent = buildBubbleIntent(context, userId, userName, avatarUrl)

        // [SỬA LỖI P1]: Rank sẽ được hệ thống gán mặc định nếu để 0.
        // Thay vì setRank(0), không setRank để hệ thống tự động quản lý vòng đời LRU.
        val shortcut = ShortcutInfo.Builder(context, userId)
            .setShortLabel(userName)
            .setLongLabel("Chat with $userName")
            .setIcon(icon)
            .setIntent(intent)
            .setLongLived(true)
            .setPerson(person)
            .setCategories(setOf("android.app.shortcuts.CONVERSATION"))
            .build()

        withContext(Dispatchers.Main) {
            try {
                context.getSystemService(ShortcutManager::class.java)
                    ?.pushDynamicShortcut(shortcut)
                Log.d(TAG, "✅ Modern shortcut created: $userName")
            } catch (e: Exception) {
                Log.e(TAG, "❌ pushShortcut failed: $e")
            }
        }
    }

    private fun evictOldest(context: Context) {
        try {
            val sm = context.getSystemService(ShortcutManager::class.java) ?: return

            // Xóa theo rank lớn nhất (thường là cũ nhất/ít tương tác nhất theo thuật toán của hệ thống)
            val oldest = sm.dynamicShortcuts.maxByOrNull { it.rank } ?: return
            sm.removeDynamicShortcuts(listOf(oldest.id))

            Log.d(TAG, "🗑️ Evicted oldest shortcut (rank ${oldest.rank}): ${oldest.id}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ evictOldest failed: $e")
        }
    }

    private fun buildBubbleIntent(
        context: Context, userId: String, userName: String, avatarUrl: String
    ): Intent {
        return Intent(context, BubbleActivity::class.java).apply {
            component = ComponentName(context, BubbleActivity::class.java)
            action = Intent.ACTION_VIEW
            data = android.net.Uri.parse("bubble://chat/$userId")
            putExtra("userId", userId)
            putExtra("userName", userName)
            putExtra("avatarUrl", avatarUrl)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        }
    }
}
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
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import hust.appchat.BubbleActivity
import kotlinx.coroutines.*

@android.annotation.SuppressLint("NewApi")
object ShortcutHelper {

    private const val TAG = "ShortcutHelper"
    private const val MAX_SHORTCUTS = 5

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    // ========================================
    // PUBLIC API
    // ========================================

    fun isShortcutsSupported() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1

    fun getShortcutCount(context: Context): Int {
        if (!isShortcutsSupported()) return 0
        return try {
            context.getSystemService(ShortcutManager::class.java)
                ?.dynamicShortcuts?.size ?: 0
        } catch (e: Exception) {
            Log.e(TAG, "❌ getShortcutCount: $e")
            0
        }
    }

    fun canCreateMoreShortcuts(context: Context) =
        isShortcutsSupported() && getShortcutCount(context) < MAX_SHORTCUTS

    fun shortcutExists(context: Context, userId: String): Boolean {
        if (!isShortcutsSupported()) return false
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
                createShortcutInternal(context, userId, userName, avatarUrl)
            } catch (e: Exception) {
                Log.e(TAG, "❌ createShortcut: $e")
            }
        }
    }

    /** Suspending version for coroutine usage */
    suspend fun createShortcutSuspend(
        context: Context, userId: String, userName: String, avatarUrl: String
    ) = withContext(Dispatchers.Main) {
        createShortcutInternal(context, userId, userName, avatarUrl)
    }

    fun removeShortcut(context: Context, userId: String) {
        if (!isShortcutsSupported()) return
        try {
            context.getSystemService(ShortcutManager::class.java)
                ?.removeDynamicShortcuts(listOf(userId))
            Log.d(TAG, "✅ Shortcut removed: $userId")
        } catch (e: Exception) {
            Log.e(TAG, "❌ removeShortcut: $e")
        }
    }

    fun removeAllShortcuts(context: Context) {
        if (!isShortcutsSupported()) return
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

            // LỖI D FIX: Polling thay vì hard delay để theo dõi chính xác trạng thái
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AvatarLoader.preloadAvatarsBatch(
                context,
                users.map { (_, name, url) -> url to name }
            )
        }

        // 2. Create shortcuts sequentially on Main thread
        withContext(Dispatchers.Main) {
            users.forEach { (uid, name, url) ->
                if (!shortcutExists(context, uid)) {
                    try {
                        createShortcutInternal(context, uid, name, url)
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
        if (!isShortcutsSupported()) return emptyList()
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
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AvatarLoader.clearCache(avatarUrl, userName)
            Log.d(TAG, "🗑️ Cleared shortcut avatar cache for: $userName")
        }
    }

    fun getAvatarCacheStats(): Map<String, Any> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AvatarLoader.getCacheStats()
        } else {
            emptyMap()
        }
    }

    fun cleanup() {
        scope.coroutineContext.cancelChildren()
        Log.d(TAG, "✅ ShortcutHelper cleanup complete")
    }

    // ========================================
    // PRIVATE IMPLEMENTATION
    // ========================================

    @Suppress("DEPRECATION")
    private suspend fun createShortcutInternal(
        context: Context, userId: String, userName: String, avatarUrl: String
    ) {
        if (!isShortcutsSupported()) return

        // Evict oldest if at capacity
        if (getShortcutCount(context) >= MAX_SHORTCUTS) {
            evictOldest(context)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            createModernShortcut(context, userId, userName, avatarUrl)
        } else {
            createCompatShortcut(context, userId, userName, avatarUrl)
        }
    }

    @RequiresApi(Build.VERSION_CODES.R)
    private suspend fun createModernShortcut(
        context: Context, userId: String, userName: String, avatarUrl: String
    ) = withContext(Dispatchers.IO) {

        val icon = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            AvatarLoader.loadAvatarIcon(context, avatarUrl, userName)
        } else return@withContext

        val person = android.app.Person.Builder()
            .setName(userName)
            .setKey(userId)
            .setIcon(icon)
            .setImportant(true)
            .build()

        val intent = buildBubbleIntent(context, userId, userName, avatarUrl)

        val shortcut = ShortcutInfo.Builder(context, userId)
            .setShortLabel(userName)
            .setLongLabel("Chat with $userName")
            .setIcon(icon)
            .setIntent(intent)
            .setLongLived(true)
            .setPerson(person)
            .setCategories(setOf("android.app.shortcuts.CONVERSATION"))
            .setRank(0)
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

    private suspend fun createCompatShortcut(
        context: Context, userId: String, userName: String, avatarUrl: String
    ) = withContext(Dispatchers.IO) {

        val iconCompat = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val icon = AvatarLoader.loadAvatarIcon(context, avatarUrl, userName)
            val bmp  = AvatarLoader.iconToBitmap(context, icon) ?: return@withContext
            IconCompat.createWithBitmap(bmp)
        } else {
            IconCompat.createWithResource(context, android.R.drawable.ic_menu_gallery)
        }

        val shortcut = ShortcutInfoCompat.Builder(context, userId)
            .setShortLabel(userName)
            .setLongLabel("Chat with $userName")
            .setIcon(iconCompat)
            .setIntent(buildBubbleIntent(context, userId, userName, avatarUrl))
            .setLongLived(true)
            .build()

        withContext(Dispatchers.Main) {
            try {
                ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
                Log.d(TAG, "✅ Compat shortcut created: $userName")
            } catch (e: Exception) {
                Log.e(TAG, "❌ compat pushShortcut failed: $e")
            }
        }
    }

    private fun evictOldest(context: Context) {
        try {
            val sm = context.getSystemService(ShortcutManager::class.java) ?: return
            val oldest = sm.dynamicShortcuts.maxByOrNull { it.rank } ?: return
            sm.removeDynamicShortcuts(listOf(oldest.id))
            Log.d(TAG, "🗑️ Evicted oldest shortcut: ${oldest.id}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ evictOldest failed: $e")
        }
    }

    private fun buildBubbleIntent(
        context: Context, userId: String, userName: String, avatarUrl: String
    ): Intent {
        return Intent(context, BubbleActivity::class.java).apply {
            // FIX CHO ANDROID 16: Thiết lập component đích tường minh
            component = ComponentName(context, BubbleActivity::class.java)

            // ĐÃ SỬA: Thêm action hợp lệ cho Shortcut từ Android 11+
            action = Intent.ACTION_VIEW

            // KHUYẾN NGHỊ: Thêm data URI để định danh duy nhất conversation, tránh lẫn task
            data = android.net.Uri.parse("bubble://chat/$userId")

            putExtra("userId", userId)
            putExtra("userName", userName)
            putExtra("avatarUrl", avatarUrl)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        }
    }
}
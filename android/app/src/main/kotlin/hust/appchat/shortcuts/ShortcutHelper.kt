package hust.appchat.shortcuts

import android.content.Context
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import hust.appchat.BubbleActivity
import kotlinx.coroutines.*
import android.graphics.Bitmap // Giữ lại cho việc chuyển đổi Icon -> IconCompat trong Legacy
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable

/**
 * ✅ GIAI ĐOẠN 6: Shortcut Manager with AvatarLoader Integration
 *
 * Quản lý shortcuts cho Bubble API:
 * - Tạo dynamic shortcuts cho conversations
 * - SỬ DỤNG AvatarLoader để tải avatar và quản lý cache.
 * - Integration với launcher
 * - Persistent shortcuts
 */
object ShortcutHelper {
    private const val TAG = "ShortcutHelper"
    private const val MAX_SHORTCUTS = 5

    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    // ========================================
    // PUBLIC API
    // ========================================

    /**
     * Tạo shortcut cho conversation
     * Required for Bubble API on Android 11+
     */
    fun createShortcut(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) {
            Log.w(TAG, "⚠️ Shortcuts require Android 7.1+")
            return
        }

        scope.launch {
            try {
                Log.d(TAG, "🔗 Creating shortcut: $userName")

                // ✅ GIAI ĐOẠN 6: Preload avatar first
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    AvatarLoader.preloadAvatar(context, avatarUrl, userName)
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    // Android 11+ - Required for Bubble API
                    createModernShortcut(context, userId, userName, avatarUrl)
                } else {
                    // Android 7.1-10 - Fallback
                    createLegacyShortcut(context, userId, userName, avatarUrl)
                }

                Log.d(TAG, "✅ Shortcut created: $userName")

            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to create shortcut: $e")
            }
        }
    }

    /**
     * Xóa shortcut khi conversation bị đóng
     */
    fun removeShortcut(context: Context, userId: String) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                val manager = context.getSystemService(ShortcutManager::class.java)
                manager?.removeDynamicShortcuts(listOf(userId))

                Log.d(TAG, "✅ Shortcut removed: $userId")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to remove shortcut: $e")
        }
    }

    /**
     * Xóa tất cả shortcuts
     */
    fun removeAllShortcuts(context: Context) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                val manager = context.getSystemService(ShortcutManager::class.java)
                manager?.removeAllDynamicShortcuts()

                AvatarLoader.clearAllCache() // ✅ Dùng AvatarLoader

                Log.d(TAG, "✅ All shortcuts removed")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to remove all shortcuts: $e")
        }
    }

    /**
     * Update shortcut (e.g., when avatar changes)
     */
    fun updateShortcut(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String
    ) {
        // ✅ GIAI ĐOẠN 6: Clear cache first
        AvatarLoader.clearCache(avatarUrl, userName)

        // Remove old then create new
        removeShortcut(context, userId)
        createShortcut(context, userId, userName, avatarUrl)
    }

    /**
     * Kiểm tra shortcut tồn tại
     */
    fun shortcutExists(context: Context, userId: String): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                val manager = context.getSystemService(ShortcutManager::class.java)
                manager?.dynamicShortcuts?.any { it.id == userId } ?: false
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking shortcut: $e")
            false
        }
    }

    /**
     * Lấy số lượng shortcuts hiện tại
     */
    fun getShortcutCount(context: Context): Int {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                val manager = context.getSystemService(ShortcutManager::class.java)
                manager?.dynamicShortcuts?.size ?: 0
            } else {
                0
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting shortcut count: $e")
            0
        }
    }

    // ========================================
    // MODERN SHORTCUT (Android 11+)
    // ========================================

    @RequiresApi(Build.VERSION_CODES.R)
    private suspend fun createModernShortcut(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String
    ) = withContext(Dispatchers.Main) {
        try {
            val manager = context.getSystemService(ShortcutManager::class.java)

            // Check shortcut limit
            if (getShortcutCount(context) >= MAX_SHORTCUTS) {
                Log.w(TAG, "⚠️ Max shortcuts reached, removing oldest")
                removeOldestShortcut(context)
            }

            // ✅ NEW: Use AvatarLoader instead of manual loading
            val avatarIcon = AvatarLoader.loadAvatarIconAsync(
                context = context,
                avatarUrl = avatarUrl,
                userName = userName
            )

            val person = createPerson(userName, avatarIcon)

            val intent = Intent(context, BubbleActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                putExtra("userId", userId)
                putExtra("userName", userName)
                putExtra("avatarUrl", avatarUrl)

                // Flags for shortcut intent
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            }

            val shortcut = ShortcutInfo.Builder(context, userId)
                .setShortLabel(userName)
                .setLongLabel("Chat with $userName")
                .setIcon(avatarIcon)
                .setIntent(intent)
                .setLongLived(true) // ✅ Persistent across reboots
                .setPerson(person)
                .setCategories(setOf("android.app.shortcuts.CONVERSATION"))
                .setRank(0) // Higher priority
                .build()

            manager?.pushDynamicShortcut(shortcut)

            Log.d(TAG, "✅ Modern shortcut created: $userName")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Modern shortcut creation failed: $e")
            throw e
        }
    }

    // ========================================
    // LEGACY SHORTCUT (Android 7.1-10)
    // ========================================

    private suspend fun createLegacyShortcut(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String
    ) = withContext(Dispatchers.Main) {
        try {
            // ✅ NEW: Use AvatarLoader for legacy too
            val avatarIcon = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                // Convert Icon to IconCompat
                val icon = AvatarLoader.loadAvatarIconAsync(
                    context = context,
                    avatarUrl = avatarUrl,
                    userName = userName
                )

                // Convert to IconCompat (Tối ưu hóa việc chuyển đổi Icon sang IconCompat)
                val drawable = icon.loadDrawable(context)
                val bitmap = if (drawable is BitmapDrawable) {
                    drawable.bitmap
                } else {
                    // Fallback to manual bitmap creation for non-bitmap drawables
                    val w = drawable?.intrinsicWidth ?: 100
                    val h = drawable?.intrinsicHeight ?: 100
                    Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also { bmp ->
                        val canvas = Canvas(bmp)
                        drawable?.setBounds(0, 0, canvas.width, canvas.height)
                        drawable?.draw(canvas)
                    }
                }

                IconCompat.createWithBitmap(bitmap)
            } else {
                // Fallback for very old Android (< M)
                IconCompat.createWithResource(context, android.R.drawable.ic_menu_gallery)
            }

            val intent = Intent(context, BubbleActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                putExtra("userId", userId)
                putExtra("userName", userName)
                putExtra("avatarUrl", avatarUrl)
            }

            val shortcut = ShortcutInfoCompat.Builder(context, userId)
                .setShortLabel(userName)
                .setLongLabel("Chat with $userName")
                .setIcon(avatarIcon)
                .setIntent(intent)
                .setLongLived(true)
                .build()

            ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)

            Log.d(TAG, "✅ Legacy shortcut created: $userName")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Legacy shortcut creation failed: $e")
            throw e
        }
    }

    // ========================================
    // PERSON BUILDER
    // ========================================

    @RequiresApi(Build.VERSION_CODES.P)
    private fun createPerson(name: String, avatarIcon: Icon): android.app.Person {
        return android.app.Person.Builder()
            .setName(name)
            .setIcon(avatarIcon)
            .setImportant(true)
            .build()
    }

    // ========================================
    // SHORTCUT MANAGEMENT
    // ========================================

    private fun removeOldestShortcut(context: Context) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                val manager = context.getSystemService(ShortcutManager::class.java)
                val shortcuts = manager?.dynamicShortcuts ?: return

                if (shortcuts.isNotEmpty()) {
                    // Remove lowest rank (oldest)
                    val oldest = shortcuts.maxByOrNull { it.rank }
                    oldest?.let {
                        manager.removeDynamicShortcuts(listOf(it.id))
                        Log.d(TAG, "✅ Removed oldest shortcut: ${it.id}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to remove oldest shortcut: $e")
        }
    }

    /**
     * Lấy danh sách shortcuts hiện tại
     */
    fun getShortcuts(context: Context): List<ShortcutInfo> {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                val manager = context.getSystemService(ShortcutManager::class.java)
                manager?.dynamicShortcuts ?: emptyList()
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting shortcuts: $e")
            emptyList()
        }
    }

    /**
     * Kiểm tra xem device có hỗ trợ shortcuts không
     */
    fun isShortcutsSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1
    }

    /**
     * Kiểm tra xem có thể tạo thêm shortcut không
     */
    fun canCreateMoreShortcuts(context: Context): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                val manager = context.getSystemService(ShortcutManager::class.java)
                val currentCount = manager?.dynamicShortcuts?.size ?: 0
                currentCount < MAX_SHORTCUTS
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error checking shortcut capacity: $e")
            false
        }
    }

    // ========================================
    // SYNC & BATCH OPERATIONS
    // ========================================

    /**
     * Đảm bảo shortcut luôn sync với notification
     */
    suspend fun ensureShortcutForNotification(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String
    ) {
        if (!shortcutExists(context, userId)) {
            Log.d(TAG, "🔗 Creating missing shortcut for notification")

            // ✅ Use coroutine-safe creation
            withContext(Dispatchers.IO) {
                createShortcut(context, userId, userName, avatarUrl)

                // Wait a bit for shortcut to be created
                delay(300)
            }

            Log.d(TAG, "✅ Shortcut created for notification")
        } else {
            Log.d(TAG, "✅ Shortcut already exists for notification")
        }
    }

    /**
     * ✅ BATCH: Create shortcuts for multiple users with preloading
     */
    suspend fun createShortcutsBatch(
        context: Context,
        users: List<Triple<String, String, String>> // userId, userName, avatarUrl
    ) = withContext(Dispatchers.IO) {
        try {
            // ✅ STEP 1: Preload all avatars first (parallel)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Log.d(TAG, "🔄 Preloading ${users.size} avatars...")

                val avatarList = users.map { (_, userName, avatarUrl) ->
                    avatarUrl to userName
                }

                AvatarLoader.preloadAvatarsBatch(context, avatarList)
                Log.d(TAG, "✅ Avatars preloaded")
            }

            // ✅ STEP 2: Create shortcuts (now avatars are cached)
            Log.d(TAG, "🔄 Creating ${users.size} shortcuts...")

            users.forEach { (userId, userName, avatarUrl) ->
                try {
                    // Check if already exists
                    if (!shortcutExists(context, userId)) {
                        createShortcut(context, userId, userName, avatarUrl)
                        delay(100) // Avoid overwhelming system
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Batch shortcut creation failed for $userName: $e")
                }
            }

            Log.d(TAG, "✅ Batch shortcut creation complete")

        } catch (e: Exception) {
            Log.e(TAG, "❌ Batch operation failed: $e")
        }
    }

    // ========================================
    // AVATAR CACHE MANAGEMENT
    // ========================================

    /**
     * Clear avatar cache for specific shortcut
     */
    fun clearShortcutAvatarCache(avatarUrl: String, userName: String) {
        AvatarLoader.clearCache(avatarUrl, userName)
        Log.d(TAG, "🗑️ Cleared avatar cache for: $userName")
    }

    /**
     * Get avatar cache statistics
     */
    fun getAvatarCacheStats(): Map<String, Any> {
        return AvatarLoader.getCacheStats()
    }

    /**
     * Refresh shortcut with new avatar
     */
    fun refreshShortcutAvatar(
        context: Context,
        userId: String,
        userName: String,
        avatarUrl: String
    ) {
        scope.launch {
            try {
                // Clear cache
                AvatarLoader.clearCache(avatarUrl, userName)

                // Recreate shortcut
                updateShortcut(context, userId, userName, avatarUrl)

                Log.d(TAG, "✅ Shortcut avatar refreshed: $userName")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to refresh avatar: $e")
            }
        }
    }

    // ========================================
    // CLEANUP
    // ========================================

    fun cleanup() {
        scope.cancel()
        AvatarLoader.clearAllCache()
        Log.d(TAG, "✅ ShortcutHelper cleanup complete")
    }

    /**
     * ✅ FIX 7: Get shortcuts as simple data (for Flutter/debugging)
     */
    fun getShortcutsInfo(context: Context): List<Map<String, String>> {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                val manager = context.getSystemService(ShortcutManager::class.java)
                val shortcuts = manager?.dynamicShortcuts ?: emptyList()

                shortcuts.map { shortcut ->
                    mapOf(
                        "id" to shortcut.id,
                        "label" to (shortcut.shortLabel?.toString() ?: ""),
                        "rank" to shortcut.rank.toString()
                    )
                }
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error getting shortcuts info: $e")
            emptyList()
        }
    }
}


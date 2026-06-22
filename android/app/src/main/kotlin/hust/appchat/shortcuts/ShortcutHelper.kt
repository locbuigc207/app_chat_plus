// android/app/src/main/kotlin/hust/appchat/shortcuts/ShortcutHelper.kt
package hust.appchat.shortcuts

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.LocusId
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
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

        // [SỬA LỖI P0]: Tạo shortcut NGAY LẬP TỨC với icon mặc định để không chặn luồng bong bóng
        val defaultIcon = createDefaultIcon(userName)

        val person = android.app.Person.Builder()
            .setName(userName)
            .setKey(userId)
            .setIcon(defaultIcon)
            .setImportant(true)
            .build()

        val intent = buildBubbleIntent(context, userId, userName, avatarUrl)

        // Cấu hình ban đầu với defaultIcon
        val shortcut = ShortcutInfo.Builder(context, userId)
            .setShortLabel(userName)
            .setLongLabel("Chat with $userName")
            .setIcon(defaultIcon)
            .setIntent(intent)
            .setLongLived(true)
            .setLocusId(LocusId(userId)) // [SỬA LỖI P0]: Thêm LocusId
            .setRank(0) // [SỬA LỖI P1]: Thêm Rank
            .setPerson(person)
            .setCategories(setOf("android.shortcut.conversation")) // [SỬA LỖI P0]: Đổi thành category chuẩn
            .build()

        // 1. Push shortcut tức thì lên hệ thống
        withContext(Dispatchers.Main) {
            try {
                context.getSystemService(ShortcutManager::class.java)
                    ?.pushDynamicShortcut(shortcut)
                Log.d(TAG, "✅ Fast shortcut created with default icon: $userName")
            } catch (e: Exception) {
                Log.e(TAG, "❌ pushShortcut failed: $e")
                return@withContext
            }
        }

        // 2. Tải ảnh thật bất đồng bộ và cập nhật shortcut sau khi tải xong
        if (avatarUrl.isNotEmpty()) {
            scope.launch(Dispatchers.IO) {
                try {
                    val realIcon = AvatarLoader.loadAvatarIcon(context, avatarUrl, userName)

                    val updatedPerson = android.app.Person.Builder()
                        .setName(userName)
                        .setKey(userId)
                        .setIcon(realIcon)
                        .setImportant(true)
                        .build()

                    val updatedShortcut = ShortcutInfo.Builder(context, userId)
                        .setShortLabel(userName)
                        .setLongLabel("Chat with $userName")
                        .setIcon(realIcon)
                        .setIntent(intent)
                        .setLongLived(true)
                        .setLocusId(LocusId(userId)) // [SỬA LỖI P0]: Thêm LocusId
                        .setRank(0) // [SỬA LỖI P1]: Thêm Rank
                        .setPerson(updatedPerson)
                        .setCategories(setOf("android.shortcut.conversation")) // [SỬA LỖI P0]: Đổi thành category chuẩn
                        .build()

                    // [SỬA LỖI MỚI 6]: Bọc trong Main thread khi cập nhật lại hệ thống shortcut
                    withContext(Dispatchers.Main) {
                        context.getSystemService(ShortcutManager::class.java)
                            ?.updateShortcuts(listOf(updatedShortcut))
                        Log.d(TAG, "✅ Shortcut avatar updated from network: $userName")
                    }
                } catch (e: Exception) {
                    Log.w(TAG, "⚠️ Failed to load real avatar for shortcut update, keeping default: $e")
                }
            }
        }
    }

    /**
     * Tạo avatar mặc định bằng Canvas (chữ cái đầu của tên)
     * Rất nhanh, không cần mạng, giải quyết triệt để lỗi timeout 2s
     */
    private fun createDefaultIcon(name: String): android.graphics.drawable.Icon {
        val letter = if (name.isNotBlank()) name.first().uppercase() else "?"
        val size = 108 // Kích thước chuẩn cho icon
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        // Nền tròn
        val bgPaint = Paint().apply {
            color = Color.parseColor("#0078FF") // Màu xanh lam chủ đạo
            isAntiAlias = true
        }
        canvas.drawCircle(size / 2f, size / 2f, size / 2f, bgPaint)

        // Chữ cái
        val textPaint = Paint().apply {
            color = Color.WHITE
            textSize = size / 2f
            isAntiAlias = true
            textAlign = Paint.Align.CENTER
            typeface = Typeface.DEFAULT_BOLD
        }

        // Căn giữa chữ theo trục Y
        val yPos = (size / 2f) - ((textPaint.descent() + textPaint.ascent()) / 2f)
        canvas.drawText(letter, size / 2f, yPos, textPaint)

        return android.graphics.drawable.Icon.createWithBitmap(bitmap)
    }

    private fun evictOldest(context: Context) {
        try {
            val sm = context.getSystemService(ShortcutManager::class.java) ?: return

            // [SỬA LỖI P1]: Xóa shortcut cũ nhất theo thời gian (minByOrNull theo lastChangedTimestamp) thay vì rank
            val oldest = sm.dynamicShortcuts.minByOrNull { it.lastChangedTimestamp } ?: return
            sm.removeDynamicShortcuts(listOf(oldest.id))

            Log.d(TAG, "🗑️ Evicted oldest shortcut (ID: ${oldest.id})")
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
            addFlags(Intent.FLAG_ACTIVITY_NEW_DOCUMENT) // [SỬA LỖI MỚI 5]: Đổi thành FLAG_ACTIVITY_NEW_DOCUMENT
            addFlags(Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
        }
    }
}
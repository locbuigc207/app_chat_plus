package hust.appchat.shortcuts

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Log
import android.util.LruCache
import androidx.annotation.RequiresApi
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.request.RequestOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.absoluteValue

/**
 * ✅ GIAI ĐOẠN 6: AVATAR LOADER WITH CACHING
 *
 * Features:
 * - LruCache for in-memory caching (10 avatars)
 * - Glide for efficient image loading with disk cache
 * - Automatic default avatar generation with initials
 * - Color generation based on name hash
 * - Circular cropping
 * - Error handling with fallback
 */
object AvatarLoader {
    private const val TAG = "AvatarLoader"

    // ========================================
    // CACHE CONFIGURATION
    // ========================================

    // LRU Cache for storing loaded Icons
    // Cache size: 10 avatars (about 1-2MB depending on resolution)
    private val iconCache = LruCache<String, Icon>(10)

    // Default avatar size
    private const val AVATAR_SIZE = 100

    // Material Design colors for default avatars
    private val AVATAR_COLORS = listOf(
        0xFF2196F3.toInt(), // Blue
        0xFF4CAF50.toInt(), // Green
        0xFFFFC107.toInt(), // Amber
        0xFFE91E63.toInt(), // Pink
        0xFF9C27B0.toInt(), // Purple
        0xFFFF5722.toInt(), // Deep Orange
        0xFF00BCD4.toInt(), // Cyan
        0xFF8BC34A.toInt(), // Light Green
        0xFFFF9800.toInt(), // Orange
        0xFF795548.toInt(), // Brown
    )

    // ========================================
    // PUBLIC API
    // ========================================

    /**
     * Load avatar icon synchronously
     *
     * @param context Android context
     * @param avatarUrl URL of avatar image (empty for default)
     * @param userName User's name for default avatar generation
     * @return Icon ready for use in notifications/shortcuts
     */
    @RequiresApi(Build.VERSION_CODES.M)
    @JvmStatic
    fun loadAvatarIcon(
        context: Context,
        avatarUrl: String,
        userName: String
    ): Icon {
        // Check cache first
        val cacheKey = getCacheKey(avatarUrl, userName)
        iconCache.get(cacheKey)?.let {
            Log.d(TAG, "📦 Using cached avatar: $userName")
            return it
        }

        return try {
            Log.d(TAG, "🔄 Loading avatar: $userName")

            val icon = if (avatarUrl.isEmpty()) {
                // Generate default avatar
                createDefaultIcon(context, userName)
            } else {
                // Load from URL using Glide
                loadFromUrl(context, avatarUrl, userName)
            }

            // Cache the result
            iconCache.put(cacheKey, icon)

            Log.d(TAG, "✅ Avatar loaded: $userName")
            icon

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error loading avatar: $e")

            // Fallback to default
            createDefaultIcon(context, userName).also {
                iconCache.put(cacheKey, it)
            }
        }
    }

    /**
     * Load avatar icon asynchronously (for coroutines)
     */
    @RequiresApi(Build.VERSION_CODES.M)
    suspend fun loadAvatarIconAsync(
        context: Context,
        avatarUrl: String,
        userName: String
    ): Icon = withContext(Dispatchers.IO) {
        loadAvatarIcon(context, avatarUrl, userName)
    }

    /**
     * Preload avatar into cache
     */
    @RequiresApi(Build.VERSION_CODES.M)
    fun preloadAvatar(
        context: Context,
        avatarUrl: String,
        userName: String
    ) {
        try {
            loadAvatarIcon(context, avatarUrl, userName)
            Log.d(TAG, "✅ Preloaded avatar: $userName")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Preload failed: $e")
        }
    }

    /**
     * Clear cache for specific user
     */
    fun clearCache(avatarUrl: String, userName: String) {
        val cacheKey = getCacheKey(avatarUrl, userName)
        iconCache.remove(cacheKey)
        Log.d(TAG, "🗑️ Cleared cache for: $userName")
    }

    /**
     * Clear all cached avatars
     */
    fun clearAllCache() {
        iconCache.evictAll()
        Log.d(TAG, "🗑️ Cleared all avatar cache")
    }

    /**
     * Get current cache size
     */
    fun getCacheSize(): Int {
        return iconCache.size()
    }

    /**
     * ✅ FIX 1: Create default avatar icon (public helper)
     *
     * Used when avatar loading fails or for fallback scenarios
     */
    @RequiresApi(Build.VERSION_CODES.M)
    fun createDefaultAvatarIcon(context: Context, name: String): Icon {
        return createDefaultIcon(context, name)
    }

    // ========================================
    // PRIVATE IMPLEMENTATION
    // ========================================

    /**
     * Generate cache key from URL and name
     */
    private fun getCacheKey(avatarUrl: String, userName: String): String {
        return if (avatarUrl.isEmpty()) {
            "default_$userName"
        } else {
            avatarUrl
        }
    }

    /**
     * Load avatar from URL using Glide
     */
    @RequiresApi(Build.VERSION_CODES.M)
    private fun loadFromUrl(
        context: Context,
        avatarUrl: String,
        userName: String
    ): Icon {
        return try {
            val bitmap = Glide.with(context)
                .asBitmap()
                .load(avatarUrl)
                .apply(
                    RequestOptions()
                        .circleCrop()
                        .diskCacheStrategy(DiskCacheStrategy.ALL)
                        .override(AVATAR_SIZE, AVATAR_SIZE)
                )
                .submit()
                .get()

            Icon.createWithBitmap(bitmap)

        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Failed to load from URL, using default: $e")
            createDefaultIcon(context, userName)
        }
    }

    /**
     * Create default avatar with initials and colored background
     */
    @RequiresApi(Build.VERSION_CODES.M)
    private fun createDefaultIcon(context: Context, name: String): Icon {
        val bitmap = Bitmap.createBitmap(
            AVATAR_SIZE,
            AVATAR_SIZE,
            Bitmap.Config.ARGB_8888
        )
        val canvas = Canvas(bitmap)

        // Draw colored circle background
        val bgPaint = Paint().apply {
            color = generateColorFromName(name)
            isAntiAlias = true
            style = Paint.Style.FILL
        }
        canvas.drawCircle(
            AVATAR_SIZE / 2f,
            AVATAR_SIZE / 2f,
            AVATAR_SIZE / 2f,
            bgPaint
        )

        // Draw initials text
        val textPaint = Paint().apply {
            color = Color.WHITE
            textSize = AVATAR_SIZE * 0.4f // 40% of size
            textAlign = Paint.Align.CENTER
            isAntiAlias = true
            isFakeBoldText = true
        }

        val initials = getInitials(name)

        // Calculate text position (center vertically)
        val textY = (AVATAR_SIZE / 2f) - ((textPaint.descent() + textPaint.ascent()) / 2)

        canvas.drawText(
            initials,
            AVATAR_SIZE / 2f,
            textY,
            textPaint
        )

        return Icon.createWithBitmap(bitmap)
    }

    /**
     * Extract initials from name (max 2 characters)
     */
    private fun getInitials(name: String): String {
        if (name.isEmpty()) return "?"

        return name
            .trim()
            .split(" ")
            .take(2) // First two words
            .mapNotNull { word ->
                word.firstOrNull()?.uppercaseChar()
            }
            .joinToString("")
            .ifEmpty { name.first().uppercaseChar().toString() }
    }

    /**
     * Generate consistent color from name hash
     */
    private fun generateColorFromName(name: String): Int {
        if (name.isEmpty()) return AVATAR_COLORS[0]

        // Use hash of name to pick color
        val index = name.hashCode().absoluteValue % AVATAR_COLORS.size
        return AVATAR_COLORS[index]
    }

    // ========================================
    // BATCH OPERATIONS
    // ========================================

    /**
     * Preload multiple avatars (useful for conversation list)
     */
    @RequiresApi(Build.VERSION_CODES.M)
    suspend fun preloadAvatarsBatch(
        context: Context,
        users: List<Pair<String, String>> // (avatarUrl, userName)
    ) = withContext(Dispatchers.IO) {
        users.forEach { (avatarUrl, userName) ->
            try {
                loadAvatarIcon(context, avatarUrl, userName)
            } catch (e: Exception) {
                Log.e(TAG, "❌ Batch preload failed for $userName: $e")
            }
        }
        Log.d(TAG, "✅ Batch preload complete: ${users.size} avatars")
    }

    // ========================================
    // TESTING & DEBUG
    // ========================================

    /**
     * Get cache statistics
     */
    fun getCacheStats(): Map<String, Any> {
        return mapOf(
            "size" to iconCache.size(),
            "maxSize" to iconCache.maxSize(),
            "hitCount" to iconCache.hitCount(),
            "missCount" to iconCache.missCount(),
            "putCount" to iconCache.putCount(),
            "evictionCount" to iconCache.evictionCount()
        )
    }
}
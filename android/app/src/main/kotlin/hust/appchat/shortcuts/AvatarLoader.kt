// android/app/src/main/kotlin/hust/appchat/shortcuts/AvatarLoader.kt
package hust.appchat.shortcuts

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
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
import kotlin.math.abs

/**
 * AvatarLoader — Centralised avatar loading & caching for the Bubble system.
 *
 * Architecture & Features:
 * • L1 Cache: In-process [LruCache]<String, Icon> with dynamic sizing based on
 * device heap memory to prevent OutOfMemory errors.
 * • L2 Cache: Glide disk cache — survives process restarts.
 * • Fallback: Auto-generates a polished initial-letter avatar with a
 * deterministic colored background and specular highlight if URL is empty or fails.
 * • Thread Safety: [loadAvatarIcon] performs blocking IO and must be called on
 * a background thread. [loadAvatarIconAsync] and [preloadAvatarsBatch] wrap
 * operations in [Dispatchers.IO] for coroutine safety.
 */
@RequiresApi(Build.VERSION_CODES.M)
object AvatarLoader {

    private const val TAG         = "AvatarLoader"
    private const val AVATAR_SIZE = 120          // px for Glide override

    // ─── Colour palette for initials avatars ──────────────────────────────
    private val PALETTE = intArrayOf(
        0xFF1E88E5.toInt(), 0xFF43A047.toInt(), 0xFFE53935.toInt(),
        0xFF8E24AA.toInt(), 0xFFFF8F00.toInt(), 0xFF00897B.toInt(),
        0xFF6D4C41.toInt(), 0xFF0288D1.toInt(), 0xFFC62828.toInt(),
        0xFF2E7D32.toInt(), 0xFF6A1B9A.toInt(), 0xFFAD1457.toInt(),
    )

    // ─── LRU cache (Icon wrappers) ────────────────────────────────────────
    private val cache: LruCache<String, Icon> by lazy {
        val maxMb    = (Runtime.getRuntime().maxMemory() / 1024 / 1024).toInt()
        val capacity = minOf(20, maxOf(8, maxMb / 4))
        Log.d(TAG, "LRU capacity: $capacity (heap=${maxMb}MB)")
        LruCache(capacity)
    }

    // ═════════════════════════════════════════════════════════════════════
    // PUBLIC API
    // ═════════════════════════════════════════════════════════════════════

    /**
     * Load avatar icon synchronously (call on background thread / IO dispatcher).
     * Checks L1 cache first; loads via Glide on miss; falls back to initials.
     */
    @JvmStatic
    fun loadAvatarIcon(context: Context, avatarUrl: String, userName: String): Icon {
        val key = cacheKey(avatarUrl, userName)
        cache.get(key)?.let {
            Log.d(TAG, "📦 Using cached avatar: $userName")
            return it
        }

        val icon = try {
            Log.d(TAG, "🔄 Loading avatar: $userName")
            if (avatarUrl.isNotEmpty()) loadFromUrl(context, avatarUrl, userName)
            else                        createInitialsIcon(userName)
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ load failed ($userName): $e, using default")
            createInitialsIcon(userName)
        }

        cache.put(key, icon)
        Log.d(TAG, "✅ Avatar loaded: $userName")
        return icon
    }

    /** Coroutine-safe wrapper — dispatches to [Dispatchers.IO]. */
    suspend fun loadAvatarIconAsync(
        context: Context, avatarUrl: String, userName: String,
    ): Icon = withContext(Dispatchers.IO) {
        loadAvatarIcon(context, avatarUrl, userName)
    }

    /** Preload avatar into cache safely */
    fun preloadAvatar(context: Context, avatarUrl: String, userName: String) {
        try {
            loadAvatarIcon(context, avatarUrl, userName)
        } catch (e: Exception) {
            Log.e(TAG, "❌ preload failed for $userName: $e")
        }
    }

    /** Preload multiple avatars concurrently */
    suspend fun preloadAvatarsBatch(
        context: Context, users: List<Pair<String, String>>,
    ) = withContext(Dispatchers.IO) {
        users.forEach { (url, name) ->
            try {
                loadAvatarIcon(context, url, name)
            } catch (e: Exception) {
                Log.e(TAG, "❌ batch preload $name failed: $e")
            }
        }
        Log.d(TAG, "✅ Batch preload complete (${users.size} avatars)")
    }

    /** Convert cached Icon to a Bitmap for [android.app.Notification.Builder.setLargeIcon]. */
    fun iconToBitmap(context: Context, icon: Icon): Bitmap? {
        return try {
            val d = icon.loadDrawable(context) ?: return null
            val w = if (d.intrinsicWidth  > 0) d.intrinsicWidth  else AVATAR_SIZE
            val h = if (d.intrinsicHeight > 0) d.intrinsicHeight else AVATAR_SIZE
            val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            val c   = Canvas(bmp)
            d.setBounds(0, 0, w, h)
            d.draw(c)
            bmp
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ iconToBitmap failed: $e")
            null
        }
    }

    /** Public helper to explicitly create a default initials icon */
    fun createDefaultAvatarIcon(context: Context, name: String): Icon {
        return createInitialsIcon(name)
    }

    /** Cache Management */
    fun clearCache(avatarUrl: String, userName: String) {
        cache.remove(cacheKey(avatarUrl, userName))
        Log.d(TAG, "🗑️ Cleared cache for: $userName")
    }

    fun clearAllCache() {
        cache.evictAll()
        Log.d(TAG, "🗑️ Cleared all avatar cache")
    }

    fun getCacheSize(): Int = cache.size()

    fun getCacheStats(): Map<String, Any> = mapOf(
        "size"          to cache.size(),
        "maxSize"       to cache.maxSize(),
        "hitCount"      to cache.hitCount(),
        "missCount"     to cache.missCount(),
        "putCount"      to cache.putCount(),
        "evictionCount" to cache.evictionCount(),
    )

    // ═════════════════════════════════════════════════════════════════════
    // PRIVATE IMPLEMENTATION
    // ═════════════════════════════════════════════════════════════════════

    private fun loadFromUrl(context: Context, url: String, name: String): Icon {
        val bmp = Glide.with(context.applicationContext)
            .asBitmap()
            .load(url)
            .apply(
                RequestOptions()
                    .circleCrop()
                    .diskCacheStrategy(DiskCacheStrategy.ALL)
                    .override(AVATAR_SIZE, AVATAR_SIZE)
                    .error(0)          // 0 → Glide throws on error → we catch below
            )
            .submit()
            .get()                     // blocking; must be called off main thread
        return Icon.createWithBitmap(bmp)
    }

    private fun createInitialsIcon(name: String): Icon {
        val bmp    = Bitmap.createBitmap(AVATAR_SIZE, AVATAR_SIZE, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bmp)
        val r      = AVATAR_SIZE / 2f

        // Background circle
        val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = paletteColor(name)
            style = Paint.Style.FILL
        }
        canvas.drawCircle(r, r, r, bgPaint)

        // Specular highlight for a polished look
        val hiPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color  = Color.argb(40, 255, 255, 255)
            style  = Paint.Style.FILL
        }
        canvas.drawCircle(r * 0.7f, r * 0.6f, r * 0.55f, hiPaint)

        // Initials text
        val txt = initials(name)
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color     = Color.WHITE
            textSize  = AVATAR_SIZE * 0.4f
            textAlign = Paint.Align.CENTER
            typeface  = Typeface.DEFAULT_BOLD
            isFakeBoldText = true
        }
        val textY = r - (textPaint.descent() + textPaint.ascent()) / 2
        canvas.drawText(txt, r, textY, textPaint)

        return Icon.createWithBitmap(bmp)
    }

    // ─── Helpers ──────────────────────────────────────────────────────────

    private fun cacheKey(url: String, name: String) =
        if (url.isNotEmpty()) url else "initials:$name"

    private fun initials(name: String): String =
        name.trim().split(" ").take(2)
            .mapNotNull { it.firstOrNull()?.uppercaseChar() }
            .joinToString("").ifEmpty { "?" }

    private fun paletteColor(name: String): Int =
        PALETTE[abs(name.hashCode()) % PALETTE.size]
}
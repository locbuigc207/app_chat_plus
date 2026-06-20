// android/app/src/main/kotlin/hust/appchat/MyAppGlideModule.kt
package hust.appchat

import android.content.Context
import android.util.Log
import com.bumptech.glide.GlideBuilder
import com.bumptech.glide.annotation.GlideModule
import com.bumptech.glide.load.DecodeFormat
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.load.engine.cache.InternalCacheDiskCacheFactory
import com.bumptech.glide.load.engine.cache.LruResourceCache
import com.bumptech.glide.module.AppGlideModule
import com.bumptech.glide.request.RequestOptions

/**
 * ✅ MyAppGlideModule — Global Glide configuration.
 *
 * - Memory cache : 8 MB LRU (auto-scaled dựa trên Heap).
 * - Disk cache   : 32 MB internal storage.
 * - Decode format: PREFER_ARGB_8888 (đảm bảo chất lượng ảnh avatar cao).
 * - Disk strategy: AUTOMATIC (cache cả source và result).
 * - Manifest parsing: Disabled (tối ưu tốc độ khởi động cold-start ~40ms).
 * - Timeout      : 5000ms mặc định (tránh kẹt luồng mạng tải ảnh).
 */
@GlideModule
class MyAppGlideModule : AppGlideModule() {

    companion object {
        private const val TAG          = "GlideModule"
        private const val DISK_CACHE   = 32L * 1024 * 1024   // 32 MB
        private const val MEMORY_CACHE = 8L  * 1024 * 1024   // 8 MB
        private const val TIMEOUT_MS   = 5000                // 5 giây (Hỗ trợ fix timeout ở AvatarLoader)
    }

    override fun applyOptions(context: Context, builder: GlideBuilder) {
        // Tối ưu bộ nhớ đệm dựa trên Heap thực tế của thiết bị
        val maxHeapMb = (Runtime.getRuntime().maxMemory() / 1024 / 1024).toInt()
        val memCacheBytes = minOf(MEMORY_CACHE, (Runtime.getRuntime().maxMemory() / 8))

        builder
            .setDiskCache(InternalCacheDiskCacheFactory(context, DISK_CACHE))
            .setMemoryCache(LruResourceCache(memCacheBytes))
            .setDefaultRequestOptions(
                RequestOptions()
                    .format(DecodeFormat.PREFER_ARGB_8888)
                    .diskCacheStrategy(DiskCacheStrategy.AUTOMATIC)
                    .skipMemoryCache(false)
                    // [SỬA LỖI P2]: Thêm timeout mặc định tránh treo load ảnh diện rộng
                    .timeout(TIMEOUT_MS)
            )

        Log.d(TAG, "Glide configured — heap: ${maxHeapMb}MB, " +
                "memCache: ${memCacheBytes / 1024 / 1024}MB, diskCache: 32MB, timeout: ${TIMEOUT_MS}ms")
    }

    // Tắt manifest parsing để tăng tốc độ khởi động app
    override fun isManifestParsingEnabled(): Boolean {
        return false
    }
}
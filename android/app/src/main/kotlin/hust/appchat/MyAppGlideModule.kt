// android/app/src/main/kotlin/hust/appchat/MyAppGlideModule.kt
package hust.appchat

import android.content.Context
import com.bumptech.glide.GlideBuilder
import com.bumptech.glide.annotation.GlideModule
import com.bumptech.glide.load.engine.DiskCacheStrategy
import com.bumptech.glide.module.AppGlideModule
import com.bumptech.glide.request.RequestOptions

/**
 * ✅ Glide Module để tối ưu hóa loading ảnh
 * - Loại bỏ warning "Failed to find GeneratedAppGlideModule"
 * - Cấu hình cache và memory optimization
 */
@GlideModule
class MyAppGlideModule : AppGlideModule() {

    override fun applyOptions(context: Context, builder: GlideBuilder) {
        // Cấu hình default request options
        builder.setDefaultRequestOptions(
            RequestOptions()
                .diskCacheStrategy(DiskCacheStrategy.AUTOMATIC)
                .skipMemoryCache(false)
        )
    }

    // Cho phép manifest parsing (tương thích với thư viện cũ)
    override fun isManifestParsingEnabled(): Boolean {
        return false
    }
}
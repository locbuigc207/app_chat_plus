// android/app/src/main/kotlin/hust/appchat/MainApplication.kt
package hust.appchat

import android.app.Application
import android.os.StrictMode
import android.util.Log

/**
 * MainApplication
 * * * Đã chuyển sang kế thừa Application() chuẩn thay vì FlutterApplication (deprecated).
 * * Bổ sung StrictMode hỗ trợ bắt lỗi hiệu suất (I/O trên Main Thread, Memory Leaks) trong quá trình phát triển.
 */
class MainApplication : Application() {

    companion object {
        private const val TAG = "MainApplication"
    }

    override fun onCreate() {
        // Ghi nhận thời điểm bắt đầu khởi chạy Application
        val startTime = System.currentTimeMillis()

        // [SỬA LỖI P1]: Kích hoạt StrictMode cho môi trường Debug
        if (BuildConfig.DEBUG) {
            enableStrictMode()
        }

        super.onCreate()

        Log.d(TAG, "✅ Application onCreate completed in ${System.currentTimeMillis() - startTime}ms")
    }

    private fun enableStrictMode() {
        try {
            // Giám sát các luồng thực thi (Main Thread)
            StrictMode.setThreadPolicy(
                StrictMode.ThreadPolicy.Builder()
                    .detectDiskReads()
                    .detectDiskWrites()
                    .detectNetwork()   // Bắt lỗi gọi API/Mạng trên luồng UI
                    .detectCustomSlowCalls()
                    .penaltyLog()      // Chỉ ghi Log cảnh báo, không gây Crash app
                    .build()
            )

            // Giám sát rò rỉ bộ nhớ (Memory Leaks) ở mức máy ảo
            StrictMode.setVmPolicy(
                StrictMode.VmPolicy.Builder()
                    .detectLeakedSqlLiteObjects()
                    .detectLeakedClosableObjects()
                    .detectActivityLeaks()
                    .penaltyLog()
                    .build()
            )
            Log.d(TAG, "🛠️ StrictMode enabled for Debug build")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to enable StrictMode: $e")
        }
    }
}
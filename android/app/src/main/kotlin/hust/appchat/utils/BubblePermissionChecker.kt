// android/app/src/main/kotlin/hust/appchat/utils/BubblePermissionChecker.kt
package hust.appchat.utils

import android.app.NotificationManager
import android.content.Context
import android.os.PowerManager
import android.util.Log
import hust.appchat.notifications.NotificationHelper

/**
 * BubblePermissionChecker — Kiểm tra toàn bộ chuỗi điều kiện để
 * Bubble API hoạt động đúng, thay thế logic check phân tán trong
 * MainActivity và BubbleServiceV2.
 *
 * Kết quả được gửi về Dart dưới dạng string tên của [Status.dartName].
 * Dart parse chuỗi này thành enum BubblePermissionStatus tương ứng.
 *
 * Cần thêm vào MainActivity.setupV2MethodChannel():
 *   "getBubblePermissionStatus" → BubblePermissionChecker.check(context).dartName
 */
object BubblePermissionChecker {

    private const val TAG = "BubblePermChecker"

    /**
     * Enum trạng thái permission — dartName phải khớp chính xác với
     * tên của enum BubblePermissionStatus trong bubble_permission_service.dart.
     */
    enum class Status(val dartName: String) {
        /** Tất cả điều kiện đã đáp ứng — bubble sẽ hiển thị. */
        FULLY_SUPPORTED("fullySupported"),

        /** Người dùng tắt thông báo — cần bật lại từ Settings. */
        NOTIFICATION_DISABLED("notificationDisabled"),

        /** Channel không cho phép bubble (canBubble() = false). */
        BUBBLE_CHANNEL_DISABLED("bubbleChannelDisabled"),

        /**
         * App đang bị giới hạn pin — FCM có thể không đến được,
         * bubble không trigger. Phổ biến trên Xiaomi / Samsung / Vivo / Oppo.
         */
        BATTERY_NOT_WHITELISTED("batteryNotWhitelisted"),

        /**
         * OEM chặn hoàn toàn — thường là Huawei/Honor không có GMS.
         * Không thể khắc phục bằng user action thông thường.
         */
        OEM_SYSTEM_BLOCKED("oemSystemBlocked"),

        /** Không xác định được trạng thái — check bị exception. */
        UNKNOWN("unknown"),
    }

    // ─── Main Check ───────────────────────────────────────────────────────

    /**
     * Kiểm tra toàn bộ chuỗi điều kiện cần thiết để Bubble API hoạt động.
     * Trả về Status đầu tiên fail — nếu tất cả pass thì [Status.FULLY_SUPPORTED].
     *
     * Thứ tự kiểm tra quan trọng: OEM block → notification → channel → battery.
     */
    fun check(context: Context): Status {
        // 0. OEM chặn hoàn toàn (Huawei không có GMS → FCM không hoạt động)
        if (OemCompatHelper.isBubbleApiBlocked()) {
            Log.w(TAG, "⛔ OEM_SYSTEM_BLOCKED: ${OemCompatHelper.getOemName()}")
            return Status.OEM_SYSTEM_BLOCKED
        }

        return try {
            val nm = context.getSystemService(NotificationManager::class.java)
                ?: run {
                    Log.e(TAG, "❌ NotificationManager unavailable")
                    return Status.UNKNOWN
                }

            // 1. Notification permission tổng thể (cần POST_NOTIFICATIONS trên API 33+)
            if (!nm.areNotificationsEnabled()) {
                Log.w(TAG, "⛔ NOTIFICATION_DISABLED: areNotificationsEnabled = false")
                return Status.NOTIFICATION_DISABLED
            }

            // 2. Per-channel bubble permission (API 29+, minSdk 30 → luôn available)
            val channel = nm.getNotificationChannel(NotificationHelper.CHANNEL_MESSAGES)
            if (channel == null) {
                Log.w(TAG, "⛔ BUBBLE_CHANNEL_DISABLED: channel '${NotificationHelper.CHANNEL_MESSAGES}' không tồn tại")
                return Status.BUBBLE_CHANNEL_DISABLED
            }

            if (!channel.canBubble()) {
                Log.w(TAG, "⛔ BUBBLE_CHANNEL_DISABLED: canBubble() = false")
                return Status.BUBBLE_CHANNEL_DISABLED
            }

            if (channel.importance < NotificationManager.IMPORTANCE_DEFAULT) {
                Log.w(TAG, "⛔ BUBBLE_CHANNEL_DISABLED: importance quá thấp (${channel.importance})")
                return Status.BUBBLE_CHANNEL_DISABLED
            }

            // 3. Battery optimization — chỉ check trên OEM aggressive
            // Pixel và AOSP thuần thường không cần whitelist này
            if (OemCompatHelper.requiresUserAction()) {
                val pm = context.getSystemService(PowerManager::class.java)
                if (pm != null && !pm.isIgnoringBatteryOptimizations(context.packageName)) {
                    Log.w(TAG, "⛔ BATTERY_NOT_WHITELISTED trên ${OemCompatHelper.getOemName()}")
                    return Status.BATTERY_NOT_WHITELISTED
                }
            }

            Log.d(TAG, "✅ FULLY_SUPPORTED trên ${OemCompatHelper.getOemName()}")
            Status.FULLY_SUPPORTED

        } catch (e: Exception) {
            Log.e(TAG, "❌ check() exception: $e")
            Status.UNKNOWN
        }
    }

    // ─── Quick Checks ─────────────────────────────────────────────────────

    /**
     * Kiểm tra nhanh chỉ channel canBubble và notification enabled.
     * KHÔNG check battery — dùng để re-check nhanh sau khi user
     * quay về từ Settings (ví dụ trong MainActivity.onResume()).
     */
    fun isChannelBubbleEnabled(context: Context): Boolean {
        return try {
            val nm = context.getSystemService(NotificationManager::class.java)
                ?: return false
            if (!nm.areNotificationsEnabled()) return false
            val channel = nm.getNotificationChannel(NotificationHelper.CHANNEL_MESSAGES)
                ?: return false
            channel.canBubble() &&
                    channel.importance >= NotificationManager.IMPORTANCE_DEFAULT
        } catch (e: Exception) {
            Log.e(TAG, "❌ isChannelBubbleEnabled: $e")
            false
        }
    }

    /**
     * Kiểm tra nhanh xem app có trong battery optimization whitelist không.
     * Chỉ có ý nghĩa trên OEM aggressive (Xiaomi, Samsung, Oppo, Vivo).
     */
    fun isBatteryWhitelisted(context: Context): Boolean {
        return try {
            val pm = context.getSystemService(PowerManager::class.java) ?: return true
            pm.isIgnoringBatteryOptimizations(context.packageName)
        } catch (e: Exception) {
            Log.e(TAG, "❌ isBatteryWhitelisted: $e")
            true // Không xác định được → coi như ok để tránh false alarm
        }
    }

    // ─── Status Helpers ───────────────────────────────────────────────────

    /**
     * Trả về true nếu status này cần user thao tác để fix.
     */
    fun needsUserAction(status: Status): Boolean = when (status) {
        Status.FULLY_SUPPORTED,
        Status.UNKNOWN,
        Status.OEM_SYSTEM_BLOCKED -> false
        else -> true
    }

    /**
     * Trả về true nếu đây là lỗi cứng không thể khắc phục qua user action.
     */
    fun isHardBlocked(status: Status): Boolean =
        status == Status.OEM_SYSTEM_BLOCKED

    /**
     * Trả về chuỗi Dart-friendly để gửi qua MethodChannel.
     * Dart side parse bằng: BubblePermissionStatus.values.firstWhere((e) => e.name == raw)
     */
    fun toDartName(status: Status): String = status.dartName

    /**
     * Parse ngược từ dartName về Status (dùng nội bộ Kotlin nếu cần).
     */
    fun fromDartName(dartName: String): Status =
        Status.values().firstOrNull { it.dartName == dartName } ?: Status.UNKNOWN

    /**
     * Mô tả ngắn gọn bằng tiếng Việt — dùng cho log và debug.
     */
    fun describe(status: Status): String = when (status) {
        Status.FULLY_SUPPORTED          -> "Bong bóng chat hoạt động bình thường"
        Status.NOTIFICATION_DISABLED    -> "Thông báo bị tắt"
        Status.BUBBLE_CHANNEL_DISABLED  -> "Channel chưa cho phép bong bóng"
        Status.BATTERY_NOT_WHITELISTED  -> "App bị giới hạn nền (pin)"
        Status.OEM_SYSTEM_BLOCKED       -> "OEM chặn hoàn toàn Bubble API"
        Status.UNKNOWN                  -> "Không xác định được trạng thái"
    }
}
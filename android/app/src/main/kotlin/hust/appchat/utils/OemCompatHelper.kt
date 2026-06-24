// android/app/src/main/kotlin/hust/appchat/utils/OemCompatHelper.kt
package hust.appchat.utils

import android.content.ActivityNotFoundException
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log

/**
 * OemCompatHelper — Phát hiện OEM và điều hướng đến đúng màn hình cài đặt
 * cho từng hệ máy: Xiaomi/HyperOS, Samsung/One UI, OPPO/ColorOS,
 * Realme UI, Vivo/OriginOS, Huawei/HarmonyOS.
 *
 * Tất cả Intent đều dùng fallback chain — thử intent chính xác nhất trước,
 * nếu thất bại tự động chuyển sang intent tổng quát hơn.
 *
 * Cần thêm các handler sau vào MainActivity.setupV2MethodChannel():
 *   "openBubbleSettings"   → OemCompatHelper.openBubbleSettings(this)
 *   "openBatteryWhitelist" → OemCompatHelper.openBatteryWhitelist(this)
 *   "openAutoStartSettings"→ OemCompatHelper.openAutoStartSettings(this)
 *   "getBubbleSetupSteps"  → OemCompatHelper.getBubbleSetupSteps(this) → List<String>
 *   "getOemName"           → OemCompatHelper.getOemName()
 */
object OemCompatHelper {

    private const val TAG = "OemCompatHelper"

    // ─── OEM Detection ────────────────────────────────────────────────────

    fun isXiaomi(): Boolean {
        val mfr = Build.MANUFACTURER.lowercase()
        val brand = Build.BRAND.lowercase()
        return mfr.contains("xiaomi") ||
                mfr.contains("redmi") ||
                brand.contains("xiaomi") ||
                brand.contains("redmi") ||
                brand.contains("poco")
    }

    /** Kiểm tra có phải HyperOS hay MIUI bằng system property */
    fun isHyperOSOrMiui(): Boolean {
        if (!isXiaomi()) return false
        return System.getProperty("ro.miui.ui.version.name", "").isNotEmpty()
    }

    /**
     * HyperOS 2 có lỗi Flutter white screen trong freeform window.
     * Kiểm tra qua ro.build.version.hyperos hoặc incremental build string.
     */
    fun isHyperOS2(): Boolean {
        if (!isHyperOSOrMiui()) return false
        val hyperOsVer   = System.getProperty("ro.build.version.hyperos", "")
        val incremental  = System.getProperty("ro.product.build.version.incremental", "")
        val buildId      = Build.ID
        return hyperOsVer.startsWith("2") ||
                incremental.contains("OS2", ignoreCase = true) ||
                buildId.contains("OS2", ignoreCase = true)
    }

    fun isSamsung(): Boolean =
        Build.MANUFACTURER.lowercase() == "samsung"

    /**
     * Đọc One UI version. Ví dụ: "70100" = One UI 7.1.0
     * 0 nếu không đọc được (không phải Samsung hoặc One UI rất cũ).
     */
    fun getSamsungOneUIVersion(): Int =
        System.getProperty("ro.build.version.oneui", "0")
            .trim().toIntOrNull() ?: 0

    fun isOneUI7Plus(): Boolean = isSamsung() && getSamsungOneUIVersion() >= 70000

    fun isOppo(): Boolean {
        val mfr = Build.MANUFACTURER.lowercase()
        return mfr.contains("oppo") ||
                System.getProperty("ro.build.version.opporom", "").isNotEmpty() ||
                System.getProperty("ro.coloros.version.name", "").isNotEmpty()
    }

    fun isRealme(): Boolean =
        Build.MANUFACTURER.lowercase().contains("realme")

    fun isVivo(): Boolean =
        Build.MANUFACTURER.lowercase().contains("vivo") ||
                System.getProperty("ro.vivo.os.version", "").isNotEmpty()

    fun isOnePlus(): Boolean =
        Build.MANUFACTURER.lowercase().contains("oneplus") ||
                Build.BRAND.lowercase().contains("oneplus")

    fun isHuawei(): Boolean =
        Build.MANUFACTURER.lowercase().contains("huawei") ||
                Build.BRAND.lowercase().contains("honor")

    /**
     * Huawei/Honor sau 2020 không có GMS → FCM không hoạt động → bubble không trigger.
     * Phát hiện bằng cách thử load class GoogleApiAvailability.
     */
    fun isHuaweiWithoutGms(): Boolean {
        if (!isHuawei()) return false
        return try {
            Class.forName("com.google.android.gms.common.GoogleApiAvailability")
            false // GMS tồn tại
        } catch (_: ClassNotFoundException) {
            true  // Không có GMS
        }
    }

    fun getOemName(): String = when {
        isHyperOS2()          -> "Xiaomi HyperOS 2"
        isHyperOSOrMiui()     -> "Xiaomi HyperOS / MIUI"
        isXiaomi()            -> "Xiaomi"
        isOneUI7Plus()        -> "Samsung One UI ${getSamsungOneUIVersion() / 10000}"
        isSamsung()           -> "Samsung One UI"
        isRealme()            -> "Realme UI"
        isOppo()              -> "OPPO ColorOS"
        isVivo()              -> "Vivo OriginOS"
        isOnePlus()           -> "OnePlus OxygenOS"
        isHuaweiWithoutGms()  -> "Huawei HarmonyOS (không có GMS)"
        else                  -> "Android ${Build.VERSION.RELEASE}"
    }

    // ─── Settings Navigation ──────────────────────────────────────────────

    /**
     * Mở màn hình cho phép Bubble / Thông báo nổi theo đúng OEM.
     * Thứ tự: intent chính xác nhất → intent tổng quát → App Info.
     */
    fun openBubbleSettings(context: Context) {
        val pkg = context.packageName
        val intents: List<Intent> = when {
            isXiaomi() -> listOf(
                // MIUI Bubble settings app riêng
                Intent().apply {
                    component = ComponentName(
                        "com.miui.bubbles",
                        "com.miui.bubbles.settings.BubbleMainActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                // Android chuẩn (API 29+)
                Intent(Settings.ACTION_APP_NOTIFICATION_BUBBLE_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                buildNotificationSettingsIntent(pkg)
            )
            isSamsung() -> listOf(
                // One UI 7: bubble settings per-app
                Intent(Settings.ACTION_APP_NOTIFICATION_BUBBLE_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                // One UI < 7 fallback
                buildNotificationSettingsIntent(pkg)
            )
            else -> listOf(
                Intent(Settings.ACTION_APP_NOTIFICATION_BUBBLE_SETTINGS).apply {
                    putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                buildNotificationSettingsIntent(pkg)
            )
        }
        launchFirstSuccessful(context, intents, "openBubbleSettings")
    }

    /**
     * Mở Battery Optimization / Tiết kiệm pin whitelist theo OEM.
     */
    fun openBatteryWhitelist(context: Context) {
        val pkg = context.packageName
        val intents: List<Intent> = when {
            isXiaomi() -> listOf(
                // HyperOS 2.x / MIUI 14+
                Intent().apply {
                    component = ComponentName(
                        "com.miui.powerkeeper",
                        "com.miui.powerkeeper.ui.HiddenAppsContainerManagementActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                // MIUI / HyperOS 1.x — broadcast action
                Intent("miui.intent.action.POWER_HIDE_MODE_APP_LIST").apply {
                    addCategory(Intent.CATEGORY_DEFAULT)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                // Android chuẩn
                buildIgnoreBatteryOptIntent(pkg),
                buildAppDetailsIntent(pkg)
            )
            isSamsung() -> listOf(
                // Samsung Device Care
                Intent().apply {
                    component = ComponentName(
                        "com.samsung.android.lool",
                        "com.samsung.android.sm.ui.battery.BatteryActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                buildIgnoreBatteryOptIntent(pkg),
                buildAppDetailsIntent(pkg)
            )
            isOppo() || isRealme() -> listOf(
                // ColorOS 15+ / Realme UI 5+
                Intent().apply {
                    component = ComponentName(
                        "com.coloros.safecenter",
                        "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                // ColorOS cũ hơn
                Intent().apply {
                    component = ComponentName(
                        "com.oppo.safe",
                        "com.oppo.safe.permission.startup.StartupAppListActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                buildIgnoreBatteryOptIntent(pkg),
                buildAppDetailsIntent(pkg)
            )
            isVivo() -> listOf(
                // OriginOS 5+
                Intent().apply {
                    component = ComponentName(
                        "com.iqoo.secure",
                        "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                // Vivo Permission Manager
                Intent().apply {
                    component = ComponentName(
                        "com.vivo.permissionmanager",
                        "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                buildIgnoreBatteryOptIntent(pkg),
                buildAppDetailsIntent(pkg)
            )
            isHuawei() -> listOf(
                Intent().apply {
                    component = ComponentName(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                buildIgnoreBatteryOptIntent(pkg),
                buildAppDetailsIntent(pkg)
            )
            else -> listOf(
                buildIgnoreBatteryOptIntent(pkg),
                buildAppDetailsIntent(pkg)
            )
        }
        launchFirstSuccessful(context, intents, "openBatteryWhitelist")
    }

    /**
     * Mở Auto-start / Khởi động tự động theo OEM.
     */
    fun openAutoStartSettings(context: Context) {
        val pkg = context.packageName
        val intents: List<Intent> = when {
            isXiaomi() -> listOf(
                // MIUI / HyperOS: Security Center → Auto-start
                Intent().apply {
                    component = ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.autostart.AutoStartManagementActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                // MIUI cũ hơn
                Intent().apply {
                    component = ComponentName(
                        "com.miui.securitycenter",
                        "com.miui.permcenter.MainAcitivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                buildAppDetailsIntent(pkg)
            )
            isSamsung() -> listOf(
                // Samsung không có auto-start riêng, dùng battery settings
                Intent().apply {
                    component = ComponentName(
                        "com.samsung.android.lool",
                        "com.samsung.android.sm.ui.battery.BatteryActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                buildAppDetailsIntent(pkg)
            )
            isOppo() || isRealme() -> listOf(
                Intent().apply {
                    component = ComponentName(
                        "com.coloros.safecenter",
                        "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                Intent().apply {
                    component = ComponentName(
                        "com.oppo.safe",
                        "com.oppo.safe.permission.startup.StartupAppListActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                buildAppDetailsIntent(pkg)
            )
            isVivo() -> listOf(
                Intent().apply {
                    component = ComponentName(
                        "com.vivo.permissionmanager",
                        "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                Intent().apply {
                    component = ComponentName(
                        "com.iqoo.secure",
                        "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                buildAppDetailsIntent(pkg)
            )
            isHuawei() -> listOf(
                Intent().apply {
                    component = ComponentName(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                Intent().apply {
                    component = ComponentName(
                        "com.huawei.systemmanager",
                        "com.huawei.systemmanager.optimize.process.ProtectActivity"
                    )
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
                buildAppDetailsIntent(pkg)
            )
            else -> listOf(buildAppDetailsIntent(pkg))
        }
        launchFirstSuccessful(context, intents, "openAutoStartSettings")
    }

    // ─── Setup Steps (Vietnamese) ─────────────────────────────────────────

    /**
     * Trả về danh sách các bước hướng dẫn user bằng tiếng Việt theo OEM.
     * Gọi từ MethodChannel handler "getBubbleSetupSteps".
     */
    fun getBubbleSetupSteps(context: Context): List<String> {
        val appName = getAppName(context)
        return when {
            isHyperOS2() -> listOf(
                "Cài đặt → Ứng dụng → $appName → Tiết kiệm pin → Không hạn chế",
                "Cài đặt → Thông báo → $appName → bật Hiển thị nổi",
                "Tải ứng dụng Activity Launcher → tìm \"com.miui.bubbles.settings\" → bật Bubble cho $appName",
                "Tùy chọn nhà phát triển → bật Force activities to be resizable"
            )
            isHyperOSOrMiui() -> listOf(
                "Cài đặt → Ứng dụng → $appName → Tiết kiệm pin → Không hạn chế",
                "Cài đặt → Thông báo → $appName → bật Hiển thị nổi (Bong bóng)",
                "Tùy chọn nhà phát triển → tắt Tối ưu hóa MIUI để bỏ giới hạn"
            )
            isOneUI7Plus() -> listOf(
                "Cài đặt → Thông báo → Cài đặt nâng cao → Thông báo nổi → chọn Bong bóng",
                "Cài đặt → Thông báo → $appName → Tin nhắn → bật Hiển thị dưới dạng cửa sổ nổi"
            )
            isSamsung() -> listOf(
                "Cài đặt → Thông báo → Cài đặt nâng cao → Thông báo nổi → Bong bóng",
                "Cài đặt → Thông báo → $appName → bật Cho phép bong bóng"
            )
            isOppo() -> listOf(
                "Cài đặt → Pin → App Quick Freeze → bỏ $appName khỏi danh sách",
                "Cài đặt → Ứng dụng → $appName → Khởi động tự động → Bật",
                "Cài đặt → Thông báo → $appName → bật Cho phép bong bóng"
            )
            isRealme() -> listOf(
                "Cài đặt → Pin → App Quick Freeze → bỏ $appName khỏi danh sách đóng băng",
                "Cài đặt → Ứng dụng → $appName → Tự khởi động → Bật",
                "Cài đặt → Thông báo → $appName → bật Bong bóng chat"
            )
            isVivo() -> listOf(
                "iManager → Quyền riêng tư → Quản lý khởi động → bật $appName",
                "Cài đặt → Pin → Mức tiêu thụ điện nền cao → bỏ giới hạn $appName",
                "Cài đặt → Thông báo → $appName → bật Bong bóng chat"
            )
            isHuaweiWithoutGms() -> listOf(
                "Thiết bị Huawei/Honor không hỗ trợ bong bóng chat do không có Google Services.",
                "Tin nhắn sẽ hiển thị qua thông báo thông thường."
            )
            else -> listOf(
                "Cài đặt → Thông báo → $appName → bật Cho phép bong bóng hoặc Thông báo nổi"
            )
        }
    }

    // ─── Capability Flags ─────────────────────────────────────────────────

    /**
     * OEM này yêu cầu user thao tác thủ công — cần hiển thị onboarding guide.
     */
    fun requiresUserAction(): Boolean =
        isXiaomi() || isSamsung() || isOppo() || isRealme() || isVivo()

    /**
     * OEM chặn hoàn toàn Bubble API — không thể khắc phục bằng code.
     */
    fun isBubbleApiBlocked(): Boolean = isHuaweiWithoutGms()

    /**
     * HyperOS 2 có bug Flutter white screen trong freeform floating window.
     * BubbleActivity cần gửi signal này xuống Dart để tránh fixed constraints.
     */
    fun hasHyperOS2RenderBug(): Boolean = isHyperOS2()

    /**
     * Samsung One UI 7+ có thể reset bubble permission sau system update.
     * MainActivity.onResume() nên re-check canBubble() trên thiết bị Samsung.
     */
    fun needsResumePermissionCheck(): Boolean = isSamsung()

    // ─── Private Builders ─────────────────────────────────────────────────

    private fun buildNotificationSettingsIntent(pkg: String): Intent =
        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, pkg)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    private fun buildIgnoreBatteryOptIntent(pkg: String): Intent =
        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:$pkg")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    private fun buildAppDetailsIntent(pkg: String): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$pkg")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

    private fun getAppName(context: Context): String =
        try {
            val info = context.packageManager.getApplicationInfo(context.packageName, 0)
            context.packageManager.getApplicationLabel(info).toString()
        } catch (_: Exception) { "App Chat Plus" }

    /**
     * Thử lần lượt từng Intent trong danh sách.
     * Dừng tại Intent đầu tiên thành công, log lỗi nếu tất cả thất bại.
     */
    private fun launchFirstSuccessful(
        context: Context,
        intents: List<Intent>,
        source: String,
    ) {
        for (intent in intents) {
            try {
                context.startActivity(intent)
                Log.d(TAG, "✅ $source → ${intent.action ?: intent.component?.className}")
                return
            } catch (_: ActivityNotFoundException) {
                Log.w(TAG, "⚠️ $source: not found — ${intent.component?.className}")
            } catch (_: SecurityException) {
                Log.w(TAG, "⚠️ $source: security exception — ${intent.component?.className}")
            } catch (e: Exception) {
                Log.w(TAG, "⚠️ $source: failed — ${e.message}")
            }
        }
        Log.e(TAG, "❌ $source: all intents failed on ${getOemName()}")
    }
}
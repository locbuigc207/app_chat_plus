# =======================================================================
# 1. FLUTTER CORE
# =======================================================================
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class plugins.flutter.io.** { *; }

# =======================================================================
# 2. DEEPAR SDK (Cực kỳ quan trọng để không crash Camera Story)
# =======================================================================
-keep class ai.deepar.** { *; }
-keepclassmembers class ai.deepar.** { *; }

# =======================================================================
# 3. AGORA RTC & WEBRTC (Giữ kết nối Video Call / Voice Call)
# =======================================================================
-keep class io.agora.** { *; }
-keep class org.webrtc.** { *; }
-keep class com.agora.** { *; }

# =======================================================================
# 4. FFMPEG KIT (Xử lý âm thanh, video không bị lỗi)
# =======================================================================
-keep class com.arthenica.ffmpegkit.** { *; }

# =======================================================================
# 5. NATIVE APP CODE CỦA BẠN (Bubble Chat, Notifications, Activity)
# =======================================================================
# Giữ lại toàn bộ code Kotlin/Java trong package của bạn để tránh lỗi Bubble Service
-keep class hust.appchat.** { *; }
-keepclassmembers class hust.appchat.** { *; }

# =======================================================================
# 6. GLIDE (Xử lý load Avatar bong bóng chat)
# =======================================================================
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep public class * extends com.bumptech.glide.module.AppGlideModule
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** {
  **[] $VALUES;
  public *;
}
-keep class com.bumptech.glide.** { *; }

# =======================================================================
# 7. GSON (Nếu dùng Gson để parse JSON trong code Native)
# =======================================================================
-keep class com.google.gson.** { *; }
-keep class sun.misc.Unsafe { *; }

# =======================================================================
# 8. FIREBASE & GOOGLE PLAY SERVICES
# =======================================================================
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# =======================================================================
# 9. EXOPLAYER / JUST AUDIO (Nếu có dùng trình phát nhạc/video Native)
# =======================================================================
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media3.** { *; }

# =======================================================================
# TẮT CẢNH BÁO THƯ VIỆN BÊN THỨ 3 (Tránh lỗi vặt khi Build)
# =======================================================================
-dontwarn sun.misc.**
-dontwarn java.nio.file.**
-dontwarn org.webrtc.**
-dontwarn io.agora.**
-dontwarn com.arthenica.**
-dontwarn ai.deepar.**
# ===========================================================================
# proguard-rules.pro — Hoàn chỉnh cho Flutter + Native Bubble Chat System
# ===========================================================================

# ── 1. DEBUGGING & STACK TRACES ──────────────────────────────────────────────
# Giữ lại tên file và số dòng để dễ debug khi có lỗi (Crashlytics)
-keepattributes SourceFile, LineNumberTable
-renamesourcefileattribute SourceFile

# ── 2. FLUTTER CORE ──────────────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class plugins.flutter.io.** { *; }
-dontwarn io.flutter.**

# ── 3. NATIVE APP CODE CỦA BẠN (Bubble Chat, Notifications, Activity) ────────
# Giữ lại toàn bộ code Kotlin/Java trong package của bạn để tránh lỗi service
-keep class hust.appchat.** { *; }
-keepclassmembers class hust.appchat.** { *; }

# BubbleManager persistence models (Gson serialization/deserialization)
-keepclassmembers class hust.appchat.bubble.BubbleManager {
    static ** INSTANCE;
}
-keep class hust.appchat.bubble.BubbleManager$BubbleEntry { *; }
-keep class hust.appchat.bubble.BubbleManager$PersistedEntry { *; }
-keep class hust.appchat.bubble.BubbleManager$Companion { *; }
-keep class hust.appchat.bubble.MultiBubbleManager$BubbleInfo { *; }
-keep class hust.appchat.bubble.MultiBubbleManager$Position { *; }

# ── 4. THIRD-PARTY SDKS (DeepAR, Agora, FFmpeg, Media3) ─────────────────────
# DeepAR (Cực kỳ quan trọng để không crash Camera Story)
-keep class ai.deepar.** { *; }
-keepclassmembers class ai.deepar.** { *; }

# Agora RTC & WebRTC (Giữ kết nối Video Call / Voice Call)
-keep class io.agora.** { *; }
-keep class org.webrtc.** { *; }
-keep class com.agora.** { *; }

# FFmpeg Kit (Xử lý âm thanh, video không bị lỗi)
-keep class com.arthenica.ffmpegkit.** { *; }

# ExoPlayer / Just Audio
-keep class com.google.android.exoplayer2.** { *; }
-keep class androidx.media3.** { *; }

# ── 5. KOTLIN & COROUTINES ───────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-keepclassmembers class **$WhenMappings { <fields>; }
-keepclassmembers class kotlin.Lazy { <fields>; }

# Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembernames class kotlinx.** { volatile <fields>; }
-dontwarn kotlinx.coroutines.**
-dontwarn kotlin.**

# ── 6. GSON ──────────────────────────────────────────────────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keep class sun.misc.Unsafe { *; }
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# ── 7. GLIDE (Load Avatar bong bóng chat) ────────────────────────────────────
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule { <init>(...); }
-keep public enum com.bumptech.glide.load.ImageHeaderParser$** {
    **[] $VALUES;
    public *;
}
-keep class com.bumptech.glide.load.data.ParcelFileDescriptorRewinder$InternalRewinder {
    *** rewind();
}
-keep class com.bumptech.glide.** { *; }
-dontwarn com.bumptech.glide.**

# ── 8. FIREBASE & GOOGLE PLAY SERVICES ───────────────────────────────────────
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Firebase Firestore model classes (nếu dùng @PropertyName)
-keepclassmembers class hust.appchat.** {
    @com.google.firebase.firestore.PropertyName <fields>;
    @com.google.firebase.firestore.PropertyName <methods>;
}

# ── 9. ANDROIDX / JETPACK / NATIVE APIs ──────────────────────────────────────
-keep class androidx.** { *; }
-keep class android.support.** { *; }

# Notification & Shortcut API cho Bubble Chat
-keep class android.app.Person { *; }
-keep class android.app.Person$Builder { *; }
-keep class android.app.Notification$BubbleMetadata { *; }
-keep class android.app.Notification$BubbleMetadata$Builder { *; }
-keep class android.app.Notification$MessagingStyle { *; }
-keep class android.content.pm.ShortcutInfo { *; }
-keep class android.content.pm.ShortcutInfo$Builder { *; }
-keep class android.content.pm.ShortcutManager { *; }
-keep class androidx.core.content.pm.ShortcutInfoCompat { *; }
-keep class androidx.core.content.pm.ShortcutManagerCompat { *; }

# ── 10. GENERAL ANDROID RULES (BroadcastReceivers, Services, Enums) ──────────
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.app.Service
-keep public class * extends com.google.firebase.messaging.FirebaseMessagingService

-keepclassmembers class * implements android.os.Parcelable {
    static ** CREATOR;
}

-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ── 11. OKHTTP / RETROFIT ────────────────────────────────────────────────────
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# ── 12. GENERAL DONTWARN (Tắt cảnh báo tránh lỗi vặt khi Build) ──────────────
-dontwarn sun.misc.**
-dontwarn java.nio.file.**
-dontwarn org.webrtc.**
-dontwarn io.agora.**
-dontwarn com.arthenica.**
-dontwarn ai.deepar.**
-dontwarn androidx.**
-dontwarn android.support.**
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**
-dontwarn javax.annotation.**
-dontwarn com.squareup.okhttp.**

# ── 13. FLUTTER LOCAL NOTIFICATIONS ──────────────────────────────────────────
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**
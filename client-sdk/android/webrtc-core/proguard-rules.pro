# WebRTC-Lite ProGuard Rules

# WebRTC native library
-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# Firebase
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# Hilt
-keep class dagger.hilt.** { *; }
-keep class javax.inject.** { *; }
-keep class * extends dagger.hilt.android.internal.managers.ViewComponentManager$FragmentContextWrapper { *; }

# Coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# Keep data classes
-keep @androidx.annotation.Keep class * {*}
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

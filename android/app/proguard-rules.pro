# ==========================================================
# Proguard / R8 Optimization Rules for Onyx Dialer
# ==========================================================

# 1. RootRecorder for su / app_process CLI execution
-keep class dark.onyx.com.RootRecorder { *; }
-keepclassmembers class dark.onyx.com.RootRecorder {
    public static void main(java.lang.String[]);
    public *;
}

# 2. InCallService, AIDL, MainActivity, and native Telecom components
-keep class dark.onyx.com.** { *; }
-keepclassmembers class dark.onyx.com.** { *; }
-dontwarn dark.onyx.com.**

# 3. Shizuku API & Provider
-keep class rikka.shizuku.** { *; }
-keepclassmembers class rikka.shizuku.** { *; }
-keep interface rikka.shizuku.** { *; }
-keep class * extends rikka.shizuku.ShizukuProvider { *; }
-dontwarn rikka.shizuku.**

# 4. Flutter engine and plugins
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }
-dontwarn io.flutter.**

# 5. Reflection, Line Numbers & Stack traces for diagnostics
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
-keepattributes SourceFile,LineNumberTable
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**

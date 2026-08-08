-keep class dark.onyx.com.RootRecorder { *; }
-keepclassmembers class dark.onyx.com.RootRecorder {
    public static void main(java.lang.String[]);
    public *;
}
-keep class dark.onyx.com.CallRecorderService { *; }
-keepclassmembers class dark.onyx.com.CallRecorderService { *; }
-keep class dark.onyx.com.** { *; }

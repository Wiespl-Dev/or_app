# FFmpegKit JNI Protection
-keep class com.arthenica.ffmpegkit.** { *; }
-keep class com.arthenica.smart-exception.** { *; }
-keep class com.antonkarpenko.ffmpegkit.** { *; }

# Prevent stripping of native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep JNI metadata
-keepattributes Exceptions,InnerClasses,Signature,Deprecated,SourceFile,LineNumberTable,*Annotation*,EnclosingMethod
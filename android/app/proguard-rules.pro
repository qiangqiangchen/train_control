# Flutter Blue Plus - 保留蓝牙相关类不被混淆
-keep class com.boskokg.flutter_blue_plus.** { *; }
-keep class com.google.protobuf.** { *; }

# Flutter 相关
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# 保留所有注解
-keepattributes *Annotation*

# 保留枚举
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
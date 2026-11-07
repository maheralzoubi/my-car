# Only used when release minification (R8) is enabled in app/build.gradle.kts
# (currently isMinifyEnabled = false). Kept so turning R8 on later doesn't
# silently break BLE / notifications on release builds.

# flutter_blue_plus — documented requirement (README "Proguard" section).
-keep class com.lib.flutter_blue_plus.* { *; }

# flutter_local_notifications serialises scheduled notifications with Gson.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keepattributes *Annotation*
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
  @com.google.gson.annotations.SerializedName <fields>;
}
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

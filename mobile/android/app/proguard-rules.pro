-keepattributes Signature,*Annotation*

# flutter_local_notifications persists scheduled-notification models with Gson.
# R8 must keep generic signatures or Gson TypeToken throws "Missing type parameter"
# when the plugin cancels/removes notifications from its cache in release builds.
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken { *; }
-keep class com.dexterous.flutterlocalnotifications.** { *; }

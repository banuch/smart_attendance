# Release builds are shrunk by R8 (full mode). ML Kit face detection looks up
# some of its own internal classes by reflection; without these rules R8 strips
# them and InputImage processing fails with a NullPointerException
# ("getClass() on a null object reference") in release builds only.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }

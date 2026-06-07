# ML Kit text recognition references script-specific recognizer options
# (Chinese, Devanagari, Japanese, Korean) that are not included when the
# package is consumed via google_mlkit_text_recognition. R8 fails the
# release build if these symbols cannot be resolved.
#
# We only use the latin script recognizer, so we instruct R8 to keep the
# wrapper class and ignore the missing script-specific options.
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# google_mlkit_commons reflects InputImage subtypes via JNI; preserve them
# so the camera frame conversion does not break in release mode.
-keep class com.google.mlkit.vision.common.** { *; }
-keep class com.google_mlkit_commons.** { *; }

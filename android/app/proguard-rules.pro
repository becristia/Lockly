# Keep Flutter embedding and plugin registrant entry points reachable after R8.
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter's embedding references Play Feature Delivery classes for optional
# deferred components. Lockly does not ship deferred components, so release R8
# should not require Play Core runtime dependencies.
-dontwarn com.google.android.play.core.**

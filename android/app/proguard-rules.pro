# Project-specific R8 rules. AndroidX/Hilt/Media3/Coil/Play Billing all ship their own
# consumer-proguard-rules bundled in their AARs — R8 applies those automatically, so this
# file only needs rules for things those libraries can't know about on their own.

# WorkManager resolves a scheduled Worker by fully-qualified class name at run time
# (androidx.work.impl.WorkerFactory), so an obfuscated/renamed name breaks it silently —
# only detectable as "notification worker never runs," not a build failure.
-keep class com.swipy.core.notifications.SwipyNotificationWorker { <init>(...); }

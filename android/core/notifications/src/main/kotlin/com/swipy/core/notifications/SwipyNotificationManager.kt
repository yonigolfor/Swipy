package com.swipy.core.notifications

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/** Android port of iOS `NotificationManager` — builds the notification channel and posts/
 * cancels styled notifications. See [NotificationScheduler]/[AlarmReceiver]/
 * [SwipyNotificationWorker] for what actually decides *when* each [NotificationTrigger] fires;
 * this class only knows how to build and deliver one, given already-resolved title/body text
 * (see [NotificationContentBuilder]). */
@Singleton
class SwipyNotificationManager @Inject constructor(
    @ApplicationContext private val context: Context,
) {
    /** Idempotent — creating an already-existing channel is a no-op per the platform contract,
     * safe to call on every app start (`SwipyApplication.onCreate()`), mirroring iOS's own
     * "must happen before the first notification post" ordering constraint. */
    fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID_REMINDERS,
            context.getString(R.string.notif_channel_reminders_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = context.getString(R.string.notif_channel_reminders_description)
        }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    fun post(trigger: NotificationTrigger, title: String, body: String) {
        // Unifies the API 33+ POST_NOTIFICATIONS runtime-permission check with per-channel/
        // global notification disablement on every API level, in one platform-recommended call
        // — a user can revoke either at any time post-grant, independent of app code.
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return
        val pendingIntent = PendingIntent.getActivity(
            context,
            trigger.notificationId,
            deepLinkIntent(trigger.deepLinkRoute),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID_REMINDERS)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()
        NotificationManagerCompat.from(context).notify(trigger.notificationId, notification)
    }

    fun cancel(trigger: NotificationTrigger) {
        NotificationManagerCompat.from(context).cancel(trigger.notificationId)
    }

    /** Targets the app's own launcher Activity generically via [Context.packageManager] rather
     * than referencing `com.swipy.app.MainActivity` directly — `:app` depends on this module,
     * not the other way around, so a hard class reference isn't available here. */
    private fun deepLinkIntent(route: String): Intent {
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: Intent()
        return launchIntent.apply {
            action = Intent.ACTION_VIEW
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_DEEP_LINK_ROUTE, route)
        }
    }

    companion object {
        const val CHANNEL_ID_REMINDERS = "swipy_reminders"

        /** Read by `MainActivity` to set the initial nav destination on a notification tap —
         * must match the extra key `MainActivity` reads exactly (duplicated by necessity, same
         * cross-module constraint as [NotificationTrigger.deepLinkRoute]). */
        const val EXTRA_DEEP_LINK_ROUTE = "com.swipy.notifications.DEEP_LINK_ROUTE"
    }
}

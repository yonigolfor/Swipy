package com.swipy.core.notifications

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

/** Exact alarms are cleared by the OS on every reboot — without this, a user who reboots their
 * device and doesn't reopen the app for a while would silently lose the weekly-cleanup/
 * inactivity reminders, which are meant to be "OS-guaranteed forever" per iOS parity. */
@AndroidEntryPoint
class BootReceiver : BroadcastReceiver() {

    @Inject lateinit var scheduler: NotificationScheduler

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        scheduler.armPersistentReminders()
    }
}

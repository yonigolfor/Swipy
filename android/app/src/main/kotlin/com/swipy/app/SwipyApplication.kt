package com.swipy.app

import android.app.Application
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import androidx.work.WorkManager
import com.swipy.core.notifications.NotificationScheduler
import com.swipy.core.notifications.SwipyNotificationManager
import com.swipy.core.notifications.SwipyNotificationWorker
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

@HiltAndroidApp
class SwipyApplication : Application(), Configuration.Provider {

    @Inject lateinit var workerFactory: HiltWorkerFactory

    @Inject lateinit var notificationManager: SwipyNotificationManager

    @Inject lateinit var notificationScheduler: NotificationScheduler

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder().setWorkerFactory(workerFactory).build()

    override fun onCreate() {
        super.onCreate()
        notificationManager.createChannel()
        notificationScheduler.armPersistentReminders()
        SwipyNotificationWorker.enqueue(WorkManager.getInstance(this))
    }
}

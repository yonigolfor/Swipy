package com.swipy.app

import android.app.Application
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import androidx.work.WorkManager
import com.swipy.core.notifications.NotificationForegroundCoordinator
import com.swipy.core.notifications.PhotoBurstMonitor
import com.swipy.core.notifications.SwipyNotificationManager
import com.swipy.core.notifications.SwipyNotificationWorker
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject

@HiltAndroidApp
class SwipyApplication : Application(), Configuration.Provider {

    @Inject lateinit var workerFactory: HiltWorkerFactory

    @Inject lateinit var notificationManager: SwipyNotificationManager

    @Inject lateinit var photoBurstMonitor: PhotoBurstMonitor

    @Inject lateinit var notificationForegroundCoordinator: NotificationForegroundCoordinator

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder().setWorkerFactory(workerFactory).build()

    override fun onCreate() {
        super.onCreate()
        notificationManager.createChannel()
        SwipyNotificationWorker.enqueue(WorkManager.getInstance(this))
        photoBurstMonitor.start()
        // Arming the weekly-cleanup/inactivity alarms and the initial burst baseline is
        // deliberately NOT done here — it happens on the coordinator's first ON_START (fired
        // right after the first Activity starts), matching iOS's own choice to defer
        // evaluateAndScheduleNotifications()/reschedule calls to `scenePhase == .active` rather
        // than `didFinishLaunching`. BootReceiver covers the "reboot with no UI opened" case.
        notificationForegroundCoordinator.start()
    }
}

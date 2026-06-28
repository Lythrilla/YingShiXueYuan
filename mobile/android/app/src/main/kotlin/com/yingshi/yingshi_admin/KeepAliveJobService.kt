package com.yingshi.yingshi_admin

import android.app.job.JobParameters
import android.app.job.JobService

/// AlarmManager 被系统延后或吞掉时的兜底巡检。
class KeepAliveJobService : JobService() {
    override fun onStartJob(params: JobParameters?): Boolean {
        KeepAliveReceiver.ensureBackgroundService(applicationContext)
        KeepAliveReceiver.ensureAlertService(applicationContext)
        KeepAliveReceiver.schedule(applicationContext)
        KeepAliveReceiver.scheduleJob(applicationContext)
        return false
    }

    override fun onStopJob(params: JobParameters?): Boolean = true
}

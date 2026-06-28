package com.yingshi.yingshi_admin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class NativeAlertService : Service() {
    companion object {
        const val EXTRA_TOKEN = "token"
        private const val CHANNEL_ID = "yingshi_alert_process_guard"
        private const val NOTIFICATION_ID = 8892
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        if (intent?.hasExtra(EXTRA_TOKEN) == true) {
            NativeAlertPoller.updateToken(
                applicationContext,
                intent.getStringExtra(EXTRA_TOKEN),
            )
        }
        NativeAlertPoller.start(applicationContext)
        NativeAlertPoller.pollNow(applicationContext)
        KeepAliveReceiver.schedule(applicationContext)
        KeepAliveReceiver.scheduleJob(applicationContext)
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        KeepAliveReceiver.scheduleFastRecovery(applicationContext)
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        KeepAliveReceiver.scheduleFastRecovery(applicationContext)
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        ensureChannel()
        val launchIntent =
            packageManager.getLaunchIntentForPackage(packageName) ?: Intent()
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val pi = PendingIntent.getActivity(this, 8893, launchIntent, flags)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("录音预约 · 独立监听中")
            .setContentText("独立进程接收新预约并触发强提醒")
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(pi)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "独立预约监听进程",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "独立进程监听新预约，降低主界面进程被清理后的影响"
            setSound(null, null)
            enableVibration(false)
        }
        nm.createNotificationChannel(channel)
    }
}

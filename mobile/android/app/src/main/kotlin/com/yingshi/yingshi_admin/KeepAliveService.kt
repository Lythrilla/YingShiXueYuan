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

/// 守护前台服务：与后台监控服务同进程，用独立常驻通知提高上划后的存活概率。
/// 主要职责是在「从最近任务划掉应用」时（onTaskRemoved）立即拉回监控服务，
/// 并用 START_STICKY 让系统在进程被回收后尽量重建本服务。
class KeepAliveService : Service() {
    companion object {
        private const val CHANNEL_ID = "yingshi_keepalive_guard"
        private const val NOTIFICATION_ID = 8890
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, buildNotification())
        KeepAliveReceiver.ensureBackgroundService(applicationContext)
        KeepAliveReceiver.schedule(applicationContext)
        KeepAliveReceiver.scheduleJob(applicationContext)
        NativeAlertPoller.start(applicationContext)
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        KeepAliveReceiver.ensureBackgroundService(applicationContext)
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
        val pi = PendingIntent.getActivity(this, 8891, launchIntent, flags)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(applicationInfo.icon)
            .setContentTitle("录音预约 · 守护中")
            .setContentText("防止后台监控被清理，确保新预约提醒")
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
            "后台守护服务",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "守护后台监控服务，降低被系统清理的概率"
            setSound(null, null)
            enableVibration(false)
        }
        nm.createNotificationChannel(channel)
    }
}

package com.yingshi.yingshi_admin

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class NativeAlertService : Service() {
    companion object {
        const val EXTRA_TOKEN = "token"
        const val EXTRA_SOUND = "sound"
        const val EXTRA_VIBRATION = "vibration"
        const val EXTRA_FULLSCREEN = "fullscreen"
        const val EXTRA_RELENTLESS = "relentless"
        const val EXTRA_POLL_SECONDS = "poll_seconds"
        // 与 Flutter 前台服务、守护服务合用同一条通知（同一通知 id 在整个应用内
        // 只会显示一条），避免通知栏出现多条常驻通知。
        private const val CHANNEL_ID = "yingshi_service_v2"
        private const val NOTIFICATION_ID = 8888
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (!enterForeground()) {
            // 后台启动受限（Android 12+/14+ 会抛 ForegroundServiceStartNotAllowedException），
            // 不要让异常逃逸导致进程崩溃；交给闹钟 / Job 心跳稍后在允许的时机重试。
            KeepAliveReceiver.schedule(applicationContext)
            KeepAliveReceiver.scheduleJob(applicationContext)
            stopSelf()
            return START_NOT_STICKY
        }
        NativeAlertPoller.updateConfig(
            applicationContext,
            token = if (intent?.hasExtra(EXTRA_TOKEN) == true) {
                intent.getStringExtra(EXTRA_TOKEN).orEmpty()
            } else {
                null
            },
            sound = intent?.optionalBoolean(EXTRA_SOUND),
            vibration = intent?.optionalBoolean(EXTRA_VIBRATION),
            fullscreen = intent?.optionalBoolean(EXTRA_FULLSCREEN),
            relentless = intent?.optionalBoolean(EXTRA_RELENTLESS),
            pollSeconds = if (intent?.hasExtra(EXTRA_POLL_SECONDS) == true) {
                intent.getIntExtra(EXTRA_POLL_SECONDS, 10)
            } else {
                null
            },
        )
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

    // Android 14（API 34）起 dataSync 前台服务有累计时长上限，到点系统回调 onTimeout，
    // 必须主动停掉前台，否则会被系统强杀 / ANR。停掉后由心跳闹钟稍后重新拉起。
    override fun onTimeout(startId: Int) {
        handleTimeout()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        handleTimeout()
    }

    private fun handleTimeout() {
        KeepAliveReceiver.schedule(applicationContext)
        KeepAliveReceiver.scheduleJob(applicationContext)
        stopSelf()
    }

    private fun enterForeground(): Boolean {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    buildNotification(),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                startForeground(NOTIFICATION_ID, buildNotification())
            }
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
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
            .setContentTitle("录音预约")
            .setContentText("运行中")
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setContentIntent(pi)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "后台运行",
            NotificationManager.IMPORTANCE_MIN,
        ).apply {
            description = "保持后台运行以接收新预约提醒"
            setSound(null, null)
            enableVibration(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun Intent.optionalBoolean(name: String): Boolean? =
        if (hasExtra(name)) getBooleanExtra(name, true) else null
}

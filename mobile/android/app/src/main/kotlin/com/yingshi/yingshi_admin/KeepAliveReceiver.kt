package com.yingshi.yingshi_admin

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.AlarmManagerCompat
import androidx.core.content.ContextCompat

/// 保活心跳：定时检查后台监控服务是否存活，被杀后立即拉起，并且每次都重新排程，
/// 形成持续自愈的心跳（区别于插件自带的一次性 watchdog）。
class KeepAliveReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_KEEP_ALIVE = "com.yingshi.yingshi_admin.KEEP_ALIVE"

        private const val REQUEST_HEARTBEAT = 7411
        private const val REQUEST_FAST_1 = 7412
        private const val REQUEST_FAST_2 = 7413
        private const val REQUEST_FAST_3 = 7414
        private const val JOB_PERIODIC = 74110
        private const val JOB_FAST = 74111
        private const val INTERVAL_MS = 60_000L
        private const val MIN_JOB_PERIOD_MS = 15 * 60 * 1000L

        /// flutter_background_service 的前台服务类名。
        private const val BG_SERVICE =
            "id.flutter.flutter_background_service.BackgroundService"

        /// 排一次（仅一次）唤醒；onReceive 里会再次排下一次，从而持续心跳。
        /// 用 setAndAllowWhileIdle：Doze 下也能触发，并临时获得后台启动前台服务的豁免。
        fun schedule(
            context: Context,
            delayMs: Long = INTERVAL_MS,
            requestId: Int = REQUEST_HEARTBEAT,
        ) {
            val ctx = context.applicationContext
            val intent = Intent(ctx, KeepAliveReceiver::class.java)
                .setAction(ACTION_KEEP_ALIVE)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags = flags or PendingIntent.FLAG_IMMUTABLE
            }
            val pi = PendingIntent.getBroadcast(ctx, requestId, intent, flags)
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val triggerAt = System.currentTimeMillis() + delayMs
            try {
                AlarmManagerCompat.setAndAllowWhileIdle(
                    am, AlarmManager.RTC_WAKEUP, triggerAt, pi
                )
            } catch (e: Exception) {
                e.printStackTrace()
                am.set(AlarmManager.RTC_WAKEUP, triggerAt, pi)
            }
        }

        /// 划掉后台、开机、更新后连续安排几次快速自愈，避免单次 alarm 被系统吞掉。
        fun scheduleFastRecovery(context: Context) {
            schedule(context, 1_000L, REQUEST_FAST_1)
            schedule(context, 5_000L, REQUEST_FAST_2)
            schedule(context, 15_000L, REQUEST_FAST_3)
            scheduleJob(context, 5_000L)
        }

        /// JobScheduler 作为 AlarmManager 之外的兜底：系统重启、alarm 被延后时仍会巡检。
        fun scheduleJob(context: Context, delayMs: Long? = null) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
            val ctx = context.applicationContext
            val scheduler = ctx.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
            val component = ComponentName(ctx, KeepAliveJobService::class.java)
            val jobId = if (delayMs == null) JOB_PERIODIC else JOB_FAST
            val builder = JobInfo.Builder(jobId, component)
                .setPersisted(true)

            if (delayMs == null) {
                builder.setPeriodic(MIN_JOB_PERIOD_MS)
            } else {
                builder
                    .setMinimumLatency(delayMs)
                    .setOverrideDeadline(delayMs + 10_000L)
            }

            try {
                scheduler.schedule(builder.build())
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        /// 若后台监控服务未运行则拉起（前台服务）。
        fun ensureBackgroundService(context: Context) {
            val ctx = context.applicationContext
            if (isServiceRunning(ctx, BG_SERVICE)) return
            try {
                val intent = Intent().setClassName(ctx, BG_SERVICE)
                ContextCompat.startForegroundService(ctx, intent)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }

        @Suppress("DEPRECATION")
        private fun isServiceRunning(context: Context, className: String): Boolean {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            for (service in am.getRunningServices(Integer.MAX_VALUE)) {
                if (className == service.service.className) return true
            }
            return false
        }
    }

    override fun onReceive(context: Context, intent: Intent?) {
        ensureBackgroundService(context)
        if (intent?.action != ACTION_KEEP_ALIVE) {
            scheduleFastRecovery(context)
        }
        schedule(context)
        scheduleJob(context)
    }
}

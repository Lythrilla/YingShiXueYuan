package com.yingshi.yingshi_admin

import android.app.ActivityManager
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
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

        private const val REQUEST_ID = 7411
        private const val INTERVAL_MS = 60_000L

        /// flutter_background_service 的前台服务类名。
        private const val BG_SERVICE =
            "id.flutter.flutter_background_service.BackgroundService"

        /// 排一次（仅一次）唤醒；onReceive 里会再次排下一次，从而持续心跳。
        /// 用 setAndAllowWhileIdle：Doze 下也能触发，并临时获得后台启动前台服务的豁免。
        fun schedule(context: Context, delayMs: Long = INTERVAL_MS) {
            val ctx = context.applicationContext
            val intent = Intent(ctx, KeepAliveReceiver::class.java)
                .setAction(ACTION_KEEP_ALIVE)
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags = flags or PendingIntent.FLAG_MUTABLE
            }
            val pi = PendingIntent.getBroadcast(ctx, REQUEST_ID, intent, flags)
            val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            AlarmManagerCompat.setAndAllowWhileIdle(
                am, AlarmManager.RTC_WAKEUP, System.currentTimeMillis() + delayMs, pi
            )
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
        // 无论上次进程因何而死，都重新排下一次心跳，实现持续自愈。
        schedule(context)
    }
}

package com.yingshi.yingshi_admin

import android.app.Service
import android.content.Intent
import android.os.IBinder

/// 轻量守护服务：与后台监控服务同进程，不额外占用通知。
/// 主要职责是在「从最近任务划掉应用」时（onTaskRemoved）立即拉回监控服务，
/// 并用 START_STICKY 让系统在进程被回收后尽量重建本服务。
class KeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        KeepAliveReceiver.ensureBackgroundService(applicationContext)
        KeepAliveReceiver.schedule(applicationContext)
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // 用户上划清理后立即安排一次快速兜底拉活（带 while-idle 豁免，可后台启前台服务）。
        KeepAliveReceiver.schedule(applicationContext, 1000L)
        super.onTaskRemoved(rootIntent)
    }
}

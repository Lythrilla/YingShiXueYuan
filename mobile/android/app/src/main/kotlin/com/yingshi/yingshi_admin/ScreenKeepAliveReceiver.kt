package com.yingshi.yingshi_admin

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class ScreenKeepAliveReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_SCREEN_OFF -> {
                KeepAliveReceiver.ensureGuardService(context)
                NativeAlertPoller.start(context.applicationContext)
                try {
                    context.startActivity(
                        Intent(context, OnePixelKeepAliveActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            .addFlags(Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS)
                            .addFlags(Intent.FLAG_ACTIVITY_NO_ANIMATION),
                    )
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
            Intent.ACTION_SCREEN_ON, Intent.ACTION_USER_PRESENT -> {
                OnePixelKeepAliveActivity.finishCurrent()
                NativeAlertPoller.pollNow(context.applicationContext)
            }
        }
    }
}

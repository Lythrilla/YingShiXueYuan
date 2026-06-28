package com.yingshi.yingshi_admin

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NativeAlertActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val pending = goAsync()
        val bookingId = intent?.getIntExtra(NativeAlertPoller.EXTRA_BOOKING_ID, 0) ?: 0
        val action = intent?.getStringExtra(NativeAlertPoller.EXTRA_ACTION).orEmpty()
        if (bookingId <= 0 || action.isEmpty()) {
            pending.finish()
            return
        }
        NativeAlertPoller.handleAction(context.applicationContext, bookingId, action) {
            pending.finish()
        }
    }
}

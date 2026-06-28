package com.yingshi.yingshi_admin

import android.app.Activity
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import java.lang.ref.WeakReference

class OnePixelKeepAliveActivity : Activity() {
    companion object {
        private var current: WeakReference<OnePixelKeepAliveActivity>? = null

        fun finishCurrent() {
            current?.get()?.finish()
            current = null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        current = WeakReference(this)
        window.setGravity(Gravity.START or Gravity.TOP)
        window.attributes = window.attributes.apply {
            width = 1
            height = 1
            x = 0
            y = 0
        }
        window.addFlags(
            WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
        )
        KeepAliveReceiver.ensureGuardService(applicationContext)
        NativeAlertPoller.start(applicationContext)
    }

    override fun onDestroy() {
        if (current?.get() === this) current = null
        super.onDestroy()
    }
}

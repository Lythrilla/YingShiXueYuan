package com.yingshi.yingshi_admin

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator

/// 提醒信号：有新预约时震动一下（单次短震），不响铃、不循环。
object NativeAlertSignal {

    /// 震动一下。
    @Suppress("DEPRECATION")
    fun buzz(context: Context) {
        try {
            val vibrator =
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(500L, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                vibrator.vibrate(500L)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /// 取消正在进行的震动。
    fun stop(context: Context? = null) {
        try {
            val vibrator =
                context?.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            vibrator?.cancel()
        } catch (_: Exception) {
        }
    }
}

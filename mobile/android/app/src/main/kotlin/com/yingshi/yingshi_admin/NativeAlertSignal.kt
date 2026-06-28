package com.yingshi.yingshi_admin

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator

object NativeAlertSignal {
    private var player: MediaPlayer? = null
    private var vibrating = false

    @Synchronized
    fun sync(
        context: Context,
        shouldRun: Boolean,
        playSound: Boolean,
        vibrate: Boolean,
    ) {
        if (!shouldRun || (!playSound && !vibrate)) {
            stop()
            return
        }
        if (playSound && player == null) startSound(context.applicationContext)
        if (!playSound && player != null) stopSound()
        if (vibrate && !vibrating) startVibration(context.applicationContext)
        if (!vibrate && vibrating) stopVibration(context.applicationContext)
    }

    @Synchronized
    fun stop(context: Context? = null) {
        stopSound()
        context?.applicationContext?.let { stopVibration(it) }
        vibrating = false
    }

    private fun startSound(context: Context) {
        try {
            val attrs = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            val afd = context.resources.openRawResourceFd(R.raw.alarm)
            player = MediaPlayer().apply {
                setAudioAttributes(attrs)
                setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                isLooping = true
                prepare()
                start()
            }
            afd.close()
        } catch (e: Exception) {
            e.printStackTrace()
            stopSound()
        }
    }

    private fun stopSound() {
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        try {
            player?.release()
        } catch (_: Exception) {
        }
        player = null
    }

    @Suppress("DEPRECATION")
    private fun startVibration(context: Context) {
        try {
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            val pattern = longArrayOf(0L, 700L, 500L, 700L, 1_200L)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(
                    VibrationEffect.createWaveform(pattern, 0),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
            } else {
                vibrator.vibrate(pattern, 0)
            }
            vibrating = true
        } catch (e: Exception) {
            e.printStackTrace()
            vibrating = false
        }
    }

    private fun stopVibration(context: Context) {
        try {
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            vibrator.cancel()
        } catch (_: Exception) {
        }
        vibrating = false
    }
}

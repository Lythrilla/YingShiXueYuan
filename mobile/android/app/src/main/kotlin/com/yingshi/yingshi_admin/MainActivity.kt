package com.yingshi.yingshi_admin

import android.app.Activity
import android.content.Intent
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "yingshi/native"
    private val pickRingtoneRequest = 4201
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        startKeepAlive()
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickRingtone" -> pickRingtone(call.argument<String>("current"), result)
                    "openChannelSettings" -> {
                        openChannelSettings(call.argument<String>("channelId"))
                        result.success(null)
                    }
                    "openNotificationSettings" -> {
                        openNotificationSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// 启动守护服务并排程保活心跳，确保上划清理后台后监控服务仍被持续拉活。
    private fun startKeepAlive() {
        try {
            startService(Intent(this, KeepAliveService::class.java))
        } catch (e: Exception) {
            e.printStackTrace()
        }
        KeepAliveReceiver.schedule(applicationContext)
    }

    private fun pickRingtone(current: String?, result: MethodChannel.Result) {
        // 同一时刻只允许一个选择器；若已有挂起请求，直接返回取消。
        pendingResult?.success(mapOf("cancelled" to true))
        pendingResult = result
        val existing = if (!current.isNullOrEmpty()) {
            Uri.parse(current)
        } else {
            RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_NOTIFICATION)
        }
        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
            putExtra(
                RingtoneManager.EXTRA_RINGTONE_TYPE,
                RingtoneManager.TYPE_NOTIFICATION or RingtoneManager.TYPE_ALARM
            )
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true)
            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
            putExtra(RingtoneManager.EXTRA_RINGTONE_TITLE, "选择提醒铃声")
            putExtra(RingtoneManager.EXTRA_RINGTONE_EXISTING_URI, existing)
        }
        startActivityForResult(intent, pickRingtoneRequest)
    }

    @Deprecated("deprecated in Activity, but still the picker callback path")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != pickRingtoneRequest) return
        val res = pendingResult
        pendingResult = null
        if (resultCode == Activity.RESULT_OK && data != null) {
            val uri: Uri? = data.getParcelableExtra(RingtoneManager.EXTRA_RINGTONE_PICKED_URI)
            if (uri == null) {
                res?.success(mapOf("cancelled" to true))
                return
            }
            val title = try {
                RingtoneManager.getRingtone(this, uri)?.getTitle(this) ?: "系统铃声"
            } catch (e: Exception) {
                "系统铃声"
            }
            res?.success(mapOf("uri" to uri.toString(), "title" to title))
        } else {
            res?.success(mapOf("cancelled" to true))
        }
    }

    private fun openChannelSettings(channelId: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !channelId.isNullOrEmpty()) {
            val intent = Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                putExtra(Settings.EXTRA_CHANNEL_ID, channelId)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } else {
            openNotificationSettings()
        }
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName"))
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }
}

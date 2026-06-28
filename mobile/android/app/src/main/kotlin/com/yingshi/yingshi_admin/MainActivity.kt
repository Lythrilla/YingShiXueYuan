package com.yingshi.yingshi_admin

import android.annotation.SuppressLint
import android.app.Activity
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.ContextCompat
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
                    "manufacturer" -> result.success(Build.MANUFACTURER ?: "")
                    "isIgnoringBatteryOptimizations" ->
                        result.success(isIgnoringBatteryOptimizations())
                    "requestIgnoreBatteryOptimizations" -> {
                        requestIgnoreBatteryOptimizations()
                        result.success(null)
                    }
                    "openAutoStartSettings" -> result.success(openAutoStartSettings())
                    "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                    "requestFullScreenIntent" -> {
                        requestFullScreenIntent()
                        result.success(null)
                    }
                    "startNativeAlertPoller" -> {
                        NativeAlertPoller.start(applicationContext)
                        NativeAlertPoller.pollNow(applicationContext)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// 启动守护服务并排程保活心跳，确保上划清理后台后监控服务仍被持续拉活。
    private fun startKeepAlive() {
        try {
            ContextCompat.startForegroundService(this, Intent(this, KeepAliveService::class.java))
        } catch (e: Exception) {
            e.printStackTrace()
        }
        KeepAliveReceiver.schedule(applicationContext)
        KeepAliveReceiver.scheduleJob(applicationContext)
        NativeAlertPoller.start(applicationContext)
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

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    @SuppressLint("BatteryLife")
    private fun requestIgnoreBatteryOptimizations() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (isIgnoringBatteryOptimizations()) return
        try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
                .setData(Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
            openNotificationSettings()
        }
    }

    /// 跳转到各厂商的「自启动 / 后台运行」白名单页；找不到时退回应用详情页。
    /// 国产深度定制系统（小米/华为/OPPO/vivo 等）上划清理后会杀进程并阻止拉活，
    /// 必须由用户在此授予自启动权限，代码无法绕过。
    private fun openAutoStartSettings(): Boolean {
        val candidates = listOf(
            "com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity",
            "com.letv.android.letvsafe" to "com.letv.android.letvsafe.AutobootManageActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.appcontrol.activity.StartupAppControlActivity",
            "com.huawei.systemmanager" to "com.huawei.systemmanager.optimize.process.ProtectActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity",
            "com.coloros.safecenter" to "com.coloros.safecenter.startupapp.StartupAppListActivity",
            "com.oppo.safe" to "com.oppo.safe.permission.startup.StartupAppListActivity",
            "com.coloros.oppoguardelf" to "com.coloros.powermanager.fuelgaue.PowerUsageModelActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity",
            "com.iqoo.secure" to "com.iqoo.secure.ui.phoneoptimize.BgStartUpManager",
            "com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
            "com.samsung.android.lool" to "com.samsung.android.sm.ui.battery.BatteryActivity",
            "com.samsung.android.lool" to "com.samsung.android.sm.battery.ui.BatteryActivity",
            "com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
            "com.htc.pitroad" to "com.htc.pitroad.landingpage.activity.LandingPageActivity",
            "com.asus.mobilemanager" to "com.asus.mobilemanager.entry.FunctionActivity",
        )
        for ((pkg, cls) in candidates) {
            val intent = Intent()
                .setComponent(ComponentName(pkg, cls))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY) != null) {
                try {
                    startActivity(intent)
                    return true
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }
        }
        // 没有匹配到厂商页面：退回应用详情页，用户可手动找到「自启动 / 后台运行」。
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return false
    }

    /// Android 14（API 34）起「全屏通知」属受限特殊权限，非闹钟/通话类应用默认未授予，
    /// 未授予时锁屏来电式弹窗不会出现，需要用户在系统设置里手动开启。
    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < 34) return true
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return nm.canUseFullScreenIntent()
    }

    private fun requestFullScreenIntent() {
        if (Build.VERSION.SDK_INT < 34) return
        try {
            val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT)
                .setData(Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            e.printStackTrace()
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

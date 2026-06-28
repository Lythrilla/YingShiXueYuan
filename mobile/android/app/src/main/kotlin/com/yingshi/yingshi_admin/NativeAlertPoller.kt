package com.yingshi.yingshi_admin

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationCompat
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray

object NativeAlertPoller {
    private const val SERVER_URL = "http://117.72.222.31:8888"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val NATIVE_PREFS = "NativeAlertPoller"
    private const val KEY_TOKEN = "flutter.token"
    private const val KEY_SOUND = "flutter.alert_sound"
    private const val KEY_VIBRATION = "flutter.alert_vibration"
    private const val KEY_FULLSCREEN = "flutter.alert_fullscreen"
    private const val KEY_RELENTLESS = "flutter.alert_relentless"
    private const val KEY_POLL_SECONDS = "flutter.poll_seconds"
    private const val KEY_SEEN_IDS = "native_seen_pending_ids"
    private const val KEY_NATIVE_TOKEN = "native_token"
    private const val KEY_NATIVE_SOUND = "native_alert_sound"
    private const val KEY_NATIVE_VIBRATION = "native_alert_vibration"
    private const val KEY_NATIVE_FULLSCREEN = "native_alert_fullscreen"
    private const val KEY_NATIVE_RELENTLESS = "native_alert_relentless"
    private const val KEY_NATIVE_POLL_SECONDS = "native_poll_seconds"

    private const val SUMMARY_CHANNEL_ID = "yingshi_summary"
    private const val ALERT_CHANNEL_ID = "yingshi_native_alert_v2"
    private const val ALERT_SOUND_CHANNEL_ID = "yingshi_native_alert_sound_v2"
    private const val ALERT_VIBRATION_CHANNEL_ID = "yingshi_native_alert_vibration_v2"
    private const val ALERT_SILENT_CHANNEL_ID = "yingshi_native_alert_silent_v2"
    private const val BOOKING_ID_BASE = 100000
    private const val DOOR_ID_BASE = 300000
    private const val SUMMARY_NOTIFICATION_ID = 9990

    private const val ACTION_APPROVE = "com.yingshi.yingshi_admin.NATIVE_APPROVE"
    private const val ACTION_CANCEL = "com.yingshi.yingshi_admin.NATIVE_CANCEL"
    const val EXTRA_BOOKING_ID = "booking_id"
    const val EXTRA_ACTION = "native_action"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val started = AtomicBoolean(false)
    private val polling = AtomicBoolean(false)
    @Volatile private var appContext: Context? = null

    private val periodicRunnable = Runnable { pollNow() }

    fun start(context: Context) {
        appContext = context.applicationContext
        ensureChannels(context.applicationContext)
        if (started.compareAndSet(false, true)) {
            pollSoon(0L)
            startSseLoop(context.applicationContext)
        }
    }

    fun updateConfig(
        context: Context,
        token: String?,
        sound: Boolean?,
        vibration: Boolean?,
        fullscreen: Boolean?,
        relentless: Boolean?,
        pollSeconds: Int?,
    ) {
        val editor = nativePrefs(context).edit()
        if (token == null) {
            // Keep the previous token when callers only want to refresh settings.
        } else if (token.isEmpty()) {
            editor.remove(KEY_NATIVE_TOKEN)
        } else {
            editor.putString(KEY_NATIVE_TOKEN, token)
        }
        if (sound != null) editor.putBoolean(KEY_NATIVE_SOUND, sound)
        if (vibration != null) editor.putBoolean(KEY_NATIVE_VIBRATION, vibration)
        if (fullscreen != null) editor.putBoolean(KEY_NATIVE_FULLSCREEN, fullscreen)
        if (relentless != null) editor.putBoolean(KEY_NATIVE_RELENTLESS, relentless)
        if (pollSeconds != null) {
            editor.putInt(KEY_NATIVE_POLL_SECONDS, pollSeconds.coerceIn(10, 600))
        }
        editor.apply()
    }

    fun pollNow(context: Context? = appContext) {
        val ctx = context?.applicationContext ?: return
        appContext = ctx
        ensureChannels(ctx)
        if (!polling.compareAndSet(false, true)) return
        Thread {
            val wakeLock = acquireWakeLock(ctx)
            try {
                pollOnce(ctx)
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                wakeLock?.release()
                polling.set(false)
                if (started.get()) pollSoon(readPollMillis(ctx))
            }
        }.start()
    }

    fun clearBooking(context: Context, bookingId: Int) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(BOOKING_ID_BASE + bookingId)
        nm.cancel(DOOR_ID_BASE + bookingId)
        val remaining = readSeenIds(context) - bookingId
        saveSeenIds(context, remaining)
        if (remaining.isEmpty()) NativeAlertSignal.stop(context)
    }

    fun handleAction(
        context: Context,
        bookingId: Int,
        action: String,
        onFinished: () -> Unit = {},
    ) {
        Thread {
            try {
                val token = readToken(context) ?: return@Thread
                val suffix = if (action == ACTION_APPROVE) "verify" else "cancel"
                val conn = openConnection(
                    "$SERVER_URL/api/admin/bookings/$bookingId/$suffix",
                    token,
                    "POST",
                )
                conn.inputStream.close()
                clearBooking(context, bookingId)
                pollNow(context)
            } catch (e: Exception) {
                e.printStackTrace()
            } finally {
                onFinished()
            }
        }.start()
    }

    private fun pollSoon(delayMs: Long) {
        mainHandler.removeCallbacks(periodicRunnable)
        mainHandler.postDelayed(periodicRunnable, delayMs)
    }

    private fun pollOnce(context: Context) {
        val token = readToken(context)
        if (token.isNullOrBlank()) {
            clearAllKnown(context)
            NativeAlertSignal.stop(context)
            return
        }

        val conn = openConnection(
            "$SERVER_URL/api/admin/bookings?status=booked",
            token,
            "GET",
        )
        val body = conn.inputStream.bufferedReader().use { it.readText() }
        val bookings = parseBookings(JSONArray(body))
        val pendingIds = bookings.map { it.id }.toSet()
        val seen = readSeenIds(context)
        val stale = seen - pendingIds
        for (id in stale) clearBooking(context, id)

        val sound = readBool(context, KEY_NATIVE_SOUND, KEY_SOUND, true)
        val vibration = readBool(context, KEY_NATIVE_VIBRATION, KEY_VIBRATION, true)
        val fullscreen = readBool(context, KEY_NATIVE_FULLSCREEN, KEY_FULLSCREEN, true)
        val relentless = readBool(context, KEY_NATIVE_RELENTLESS, KEY_RELENTLESS, true)
        val firstId = bookings.firstOrNull()?.id
        val hasNewBooking = bookings.any { !seen.contains(it.id) }

        for (booking in bookings) {
            val shouldAlert = !seen.contains(booking.id) ||
                (relentless && booking.id == firstId)
            showBookingNotification(
                context,
                booking,
                fullScreen = fullscreen && !seen.contains(booking.id),
                playSound = sound && shouldAlert,
                vibrate = vibration && shouldAlert,
            )
        }
        showSummary(context, pendingIds.size)
        NativeAlertSignal.sync(
            context,
            shouldRun = pendingIds.isNotEmpty() && (relentless || hasNewBooking),
            playSound = sound,
            vibrate = vibration,
        )
        saveSeenIds(context, pendingIds)
    }

    private fun startSseLoop(context: Context) {
        Thread {
            var backoffMs = 1_000L
            while (started.get()) {
                val token = readToken(context)
                if (token.isNullOrBlank()) {
                    Thread.sleep(10_000L)
                    continue
                }
                try {
                    val encoded = URLEncoder.encode(token, Charsets.UTF_8.name())
                    val conn = openConnection(
                        "$SERVER_URL/api/admin/events?token=$encoded",
                        token,
                        "GET",
                    )
                    BufferedReader(InputStreamReader(conn.inputStream)).use { reader ->
                        backoffMs = 1_000L
                        val data = StringBuilder()
                        while (started.get()) {
                            val line = reader.readLine() ?: break
                            if (line.startsWith("data:")) {
                                data.append(line.substringAfter("data:").trim())
                            } else if (line.isEmpty()) {
                                val payload = data.toString()
                                data.clear()
                                if (payload.isNotBlank() && payload != "ping") {
                                    pollNow(context)
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    e.printStackTrace()
                }
                Thread.sleep(backoffMs)
                backoffMs = (backoffMs * 2).coerceAtMost(30_000L)
            }
        }.start()
    }

    private fun openConnection(url: String, token: String, method: String): HttpURLConnection {
        val conn = URL(url).openConnection() as HttpURLConnection
        conn.requestMethod = method
        conn.connectTimeout = 15_000
        conn.readTimeout = if (url.contains("/events")) 0 else 15_000
        conn.setRequestProperty("Authorization", "Bearer $token")
        conn.setRequestProperty("Content-Type", "application/json")
        if (url.contains("/events")) {
            conn.setRequestProperty("Accept", "text/event-stream")
            conn.setRequestProperty("Cache-Control", "no-cache")
        }
        val code = conn.responseCode
        if (code !in 200..299) {
            conn.errorStream?.close()
            throw IllegalStateException("HTTP $code")
        }
        return conn
    }

    private fun parseBookings(array: JSONArray): List<NativeBooking> {
        val bookings = mutableListOf<NativeBooking>()
        for (i in 0 until array.length()) {
            val obj = array.getJSONObject(i)
            val resource = obj.optJSONObject("resource")
            val slot = obj.optJSONObject("slot")
            bookings += NativeBooking(
                id = obj.optInt("id"),
                applicant = obj.optString("applicant_name", "预约申请"),
                resource = resource?.optString("name").orEmpty(),
                date = obj.optString("date"),
                slotName = slot?.optString("name").orEmpty(),
                slotRange = slot?.optString("range").orEmpty(),
                phone = obj.optString("phone"),
                instructor = obj.optString("instructor"),
                numPeople = obj.optInt("num_people", 1),
                quantity = obj.optInt("quantity", 1),
            )
        }
        return bookings
    }

    private fun showBookingNotification(
        context: Context,
        booking: NativeBooking,
        fullScreen: Boolean,
        playSound: Boolean,
        vibrate: Boolean,
    ) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channelId = alertChannelId(playSound, vibrate)
        val launchIntent =
            context.packageManager.getLaunchIntentForPackage(context.packageName) ?: Intent()
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag()
        val contentIntent = PendingIntent.getActivity(
            context,
            BOOKING_ID_BASE + booking.id,
            launchIntent,
            flags,
        )
        val fullScreenIntent =
            if (fullScreen) contentIntent else null
        val approveIntent = Intent(context, NativeAlertActionReceiver::class.java)
            .setAction(ACTION_APPROVE)
            .putExtra(EXTRA_BOOKING_ID, booking.id)
            .putExtra(EXTRA_ACTION, ACTION_APPROVE)
        val cancelIntent = Intent(context, NativeAlertActionReceiver::class.java)
            .setAction(ACTION_CANCEL)
            .putExtra(EXTRA_BOOKING_ID, booking.id)
            .putExtra(EXTRA_ACTION, ACTION_CANCEL)
        val approvePi = PendingIntent.getBroadcast(
            context,
            BOOKING_ID_BASE + booking.id + 10_000,
            approveIntent,
            flags,
        )
        val cancelPi = PendingIntent.getBroadcast(
            context,
            BOOKING_ID_BASE + booking.id + 20_000,
            cancelIntent,
            flags,
        )
        val detail = "${booking.resource} · ${booking.date} ${booking.slotName} ${booking.slotRange}\n" +
            "电话 ${booking.phone}${if (booking.instructor.isNotEmpty()) " · 指导 ${booking.instructor}" else ""} · " +
            "${booking.numPeople}人/${booking.quantity}套"
        val builder = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle("待处理预约：${booking.applicant}")
            .setContentText("${booking.resource} · ${booking.date} ${booking.slotName}")
            .setStyle(NotificationCompat.BigTextStyle().bigText(detail))
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setOnlyAlertOnce(false)
            .addAction(context.applicationInfo.icon, "通过", approvePi)
            .addAction(context.applicationInfo.icon, "取消", cancelPi)
        if (fullScreenIntent != null) builder.setFullScreenIntent(fullScreenIntent, true)
        if (playSound || vibrate) nm.cancel(BOOKING_ID_BASE + booking.id)
        nm.notify(BOOKING_ID_BASE + booking.id, builder.build())
    }

    private fun showSummary(context: Context, count: Int) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (count <= 0) {
            nm.cancel(SUMMARY_NOTIFICATION_ID)
            return
        }
        val launchIntent =
            context.packageManager.getLaunchIntentForPackage(context.packageName) ?: Intent()
        val pi = PendingIntent.getActivity(
            context,
            SUMMARY_NOTIFICATION_ID,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
        val notification = NotificationCompat.Builder(context, SUMMARY_CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle("${count} 条预约待处理")
            .setContentText("原生守护服务实时监控中，处理后提醒会自动消失")
            .setContentIntent(pi)
            .setOngoing(true)
            .setAutoCancel(false)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setOnlyAlertOnce(true)
            .build()
        nm.notify(SUMMARY_NOTIFICATION_ID, notification)
    }

    private fun clearAllKnown(context: Context) {
        val ids = readSeenIds(context)
        for (id in ids) clearBooking(context, id)
        showSummary(context, 0)
        NativeAlertSignal.stop(context)
        saveSeenIds(context, emptySet())
    }

    private fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val alarmUri = Settings.System.DEFAULT_ALARM_ALERT_URI
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        nm.createNotificationChannel(
            NotificationChannel(
                ALERT_CHANNEL_ID,
                "新预约强提醒（响铃+震动）",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                setSound(alarmUri, attrs)
                enableVibration(true)
                enableLights(true)
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(
                ALERT_SOUND_CHANNEL_ID,
                "新预约强提醒（响铃）",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                setSound(alarmUri, attrs)
                enableVibration(false)
                enableLights(true)
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(
                ALERT_VIBRATION_CHANNEL_ID,
                "新预约强提醒（震动）",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                setSound(null, null)
                enableVibration(true)
                enableLights(true)
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(
                ALERT_SILENT_CHANNEL_ID,
                "新预约提醒（静音刷新）",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                setSound(null, null)
                enableVibration(false)
                enableLights(true)
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(
                SUMMARY_CHANNEL_ID,
                "待处理汇总",
                NotificationManager.IMPORTANCE_HIGH,
            ),
        )
    }

    private fun alertChannelId(playSound: Boolean, vibrate: Boolean): String {
        if (playSound && vibrate) return ALERT_CHANNEL_ID
        if (playSound) return ALERT_SOUND_CHANNEL_ID
        if (vibrate) return ALERT_VIBRATION_CHANNEL_ID
        return ALERT_SILENT_CHANNEL_ID
    }

    private fun readToken(context: Context): String? =
        nativePrefs(context).getString(KEY_NATIVE_TOKEN, null)
            ?: flutterPrefs(context).getString(KEY_TOKEN, null)

    private fun readBool(
        context: Context,
        nativeKey: String,
        flutterKey: String,
        default: Boolean,
    ): Boolean {
        val native = nativePrefs(context)
        if (native.contains(nativeKey)) return native.getBoolean(nativeKey, default)
        val prefs = flutterPrefs(context)
        return if (prefs.contains(flutterKey)) prefs.getBoolean(flutterKey, default) else default
    }

    private fun readPollMillis(context: Context): Long {
        val native = nativePrefs(context)
        if (native.contains(KEY_NATIVE_POLL_SECONDS)) {
            return native.getInt(KEY_NATIVE_POLL_SECONDS, 10).toLong()
                .coerceIn(10L, 600L) * 1_000L
        }
        val prefs = flutterPrefs(context)
        val seconds = try {
            prefs.getLong(KEY_POLL_SECONDS, 10L)
        } catch (_: ClassCastException) {
            prefs.getInt(KEY_POLL_SECONDS, 10).toLong()
        }
        return seconds.coerceIn(10L, 600L) * 1_000L
    }

    private fun readSeenIds(context: Context): Set<Int> =
        nativePrefs(context)
            .getStringSet(KEY_SEEN_IDS, emptySet())
            ?.mapNotNull { it.toIntOrNull() }
            ?.toSet()
            ?: emptySet()

    private fun saveSeenIds(context: Context, ids: Set<Int>) {
        nativePrefs(context)
            .edit()
            .putStringSet(KEY_SEEN_IDS, ids.map { it.toString() }.toSet())
            .apply()
    }

    private fun flutterPrefs(context: Context) =
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)

    private fun nativePrefs(context: Context) =
        context.getSharedPreferences(NATIVE_PREFS, Context.MODE_PRIVATE)

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }

    private fun acquireWakeLock(context: Context): PowerManager.WakeLock? {
        return try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "YingShi:NativePoll")
                .apply { acquire(20_000L) }
        } catch (_: Exception) {
            null
        }
    }

    private data class NativeBooking(
        val id: Int,
        val applicant: String,
        val resource: String,
        val date: String,
        val slotName: String,
        val slotRange: String,
        val phone: String,
        val instructor: String,
        val numPeople: Int,
        val quantity: Int,
    )
}

package com.yingshi.yingshi_admin

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
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
    private const val KEY_POLL_SECONDS = "flutter.poll_seconds"
    private const val KEY_SEEN_IDS = "native_seen_pending_ids"
    private const val KEY_NATIVE_TOKEN = "native_token"
    private const val KEY_NATIVE_SOUND = "native_alert_sound"
    private const val KEY_NATIVE_VIBRATION = "native_alert_vibration"
    private const val KEY_NATIVE_FULLSCREEN = "native_alert_fullscreen"
    private const val KEY_NATIVE_RELENTLESS = "native_alert_relentless"
    private const val KEY_NATIVE_POLL_SECONDS = "native_poll_seconds"

    private const val BOOKING_ID_BASE = 100000
    private const val DOOR_ID_BASE = 300000
    private const val ALERT_CHANNEL_ID = "yingshi_alert_v4"

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

        // 有新的待处理预约：弹一条可见通知 + 震动一下（不响铃）。
        val newBookings = bookings.filter { !seen.contains(it.id) }
        if (newBookings.isNotEmpty()) {
            for (b in newBookings) showBookingNotification(context, b)
            NativeAlertSignal.buzz(context)
        }
        saveSeenIds(context, pendingIds)
    }

    private fun ensureAlertChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            ALERT_CHANNEL_ID,
            "新预约提醒",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "有新的待处理预约时提醒"
            setSound(null, null)
            enableVibration(false)
        }
        nm.createNotificationChannel(channel)
    }

    /// 弹一条可见的新预约通知（震动由 NativeAlertSignal.buzz 单独触发）。
    private fun showBookingNotification(context: Context, b: NativeBooking) {
        ensureAlertChannel(context)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent()
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        val pi = PendingIntent.getActivity(context, BOOKING_ID_BASE + b.id, launch, flags)
        val slot = b.slotName.ifBlank { b.slotRange }
        val detail = listOf(b.resource, b.date, slot)
            .filter { it.isNotBlank() }
            .joinToString(" · ")
        val notif = NotificationCompat.Builder(context, ALERT_CHANNEL_ID)
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle("新预约待处理 · ${b.applicant}")
            .setContentText(detail)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setSound(null)
            .setVibrate(null)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        nm.notify(BOOKING_ID_BASE + b.id, notif)
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

    private fun clearAllKnown(context: Context) {
        val ids = readSeenIds(context)
        for (id in ids) clearBooking(context, id)
        NativeAlertSignal.stop(context)
        saveSeenIds(context, emptySet())
    }

    private fun readToken(context: Context): String? =
        nativePrefs(context).getString(KEY_NATIVE_TOKEN, null)
            ?: flutterPrefs(context).getString(KEY_TOKEN, null)

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

package com.khaled.widgetstudio.widget

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.bluetooth.BluetoothAdapter
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.media.AudioManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import androidx.glance.appwidget.GlanceAppWidgetManager
import com.khaled.widgetstudio.data.DataRequirements
import com.khaled.widgetstudio.design.DesignStore
import com.khaled.widgetstudio.spec.BindingNames
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

/**
 * Event-driven widget updates (ADR-030). While a long-lived component runs (the notification
 * listener once access is granted, else the optional "Live widgets" foreground service), system
 * events (battery and charging, volume, time tick, screen on, Wi-Fi, Bluetooth, airplane mode, Do Not
 * Disturb) redraw only the widgets whose spec reads that data, at most once a second per widget.
 * Without either, WorkManager refreshes every 15 minutes and the minute ticker keeps clocks moving.
 */
object LiveUpdates {
    /** A data source and the binding prefixes it changes. */
    enum class Source(val prefixes: List<String>) {
        BATTERY(listOf("battery.")), VOLUME(listOf("volume.", "system.silent")), TIME(listOf("time.", "date.", "day.", "week.", "month.", "year.", "timer.", "stopwatch.", "hourly.", "prayer.next", "calendar.next", "tasks.")),
        SCREEN(emptyList()), WIFI(listOf("system.wifi")), BLUETOOTH(listOf("system.bluetooth", "earbuds.")), AIRPLANE(listOf("system.airplane")),
        DND(listOf("system.dnd", "system.silent")), MEDIA(listOf("media.")), APP(emptyList()), ACTION(emptyList()), WORKER(emptyList());

        /** Empty prefixes: every widget redraws (the screen came on, the app opened, a refresh ran). */
        fun affects(names: Set<String>): Boolean = prefixes.isEmpty() || names.any { name -> prefixes.any { name.startsWith(it) } }
    }

    private val main = Handler(Looper.getMainLooper())
    private val lastDraw = mutableMapOf<Int, Long>()
    private val pending = mutableSetOf<Int>()
    private var receiver: BroadcastReceiver? = null
    private var owners = 0
    const val MIN_INTERVAL_MS = 1_000L

    /** Starts listening (idempotent; each caller balances it with [stop]). */
    @Synchronized
    fun start(context: Context) {
        owners += 1
        if (receiver != null) return
        val app = context.applicationContext
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_BATTERY_CHANGED); addAction(Intent.ACTION_POWER_CONNECTED); addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction("android.media.VOLUME_CHANGED_ACTION"); addAction(AudioManager.RINGER_MODE_CHANGED_ACTION)
            addAction(Intent.ACTION_TIME_TICK); addAction(Intent.ACTION_TIME_CHANGED); addAction(Intent.ACTION_TIMEZONE_CHANGED)
            addAction(Intent.ACTION_SCREEN_ON); addAction(Intent.ACTION_USER_PRESENT)
            addAction(WifiManager.WIFI_STATE_CHANGED_ACTION); addAction(BluetoothAdapter.ACTION_STATE_CHANGED)
            addAction(Intent.ACTION_AIRPLANE_MODE_CHANGED); addAction(NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED)
        }
        val created = object : BroadcastReceiver() {
            private var lastBattery = -1
            private var lastCharging: Boolean? = null
            override fun onReceive(context: Context, intent: Intent) {
                val source = when (intent.action) {
                    Intent.ACTION_BATTERY_CHANGED -> {
                        // Sent for temperature and voltage too: only a level or charging change counts.
                        val level = intent.getIntExtra(android.os.BatteryManager.EXTRA_LEVEL, -1)
                        val charging = intent.getIntExtra(android.os.BatteryManager.EXTRA_PLUGGED, 0) != 0
                        if (level == lastBattery && charging == lastCharging) return
                        lastBattery = level; lastCharging = charging
                        Source.BATTERY
                    }
                    Intent.ACTION_POWER_CONNECTED, Intent.ACTION_POWER_DISCONNECTED -> Source.BATTERY
                    "android.media.VOLUME_CHANGED_ACTION", AudioManager.RINGER_MODE_CHANGED_ACTION -> Source.VOLUME
                    Intent.ACTION_TIME_TICK, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED -> Source.TIME
                    Intent.ACTION_SCREEN_ON, Intent.ACTION_USER_PRESENT -> Source.SCREEN
                    WifiManager.WIFI_STATE_CHANGED_ACTION -> Source.WIFI
                    BluetoothAdapter.ACTION_STATE_CHANGED -> Source.BLUETOOTH
                    Intent.ACTION_AIRPLANE_MODE_CHANGED -> Source.AIRPLANE
                    NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED -> Source.DND
                    else -> return
                }
                changed(context, source)
            }
        }
        if (Build.VERSION.SDK_INT >= 33) app.registerReceiver(created, filter, Context.RECEIVER_EXPORTED) else app.registerReceiver(created, filter)
        receiver = created
    }

    @Synchronized
    fun stop(context: Context) {
        owners = (owners - 1).coerceAtLeast(0)
        if (owners > 0) return
        receiver?.let { runCatching { context.applicationContext.unregisterReceiver(it) } }
        receiver = null
    }

    val isListening: Boolean get() = receiver != null

    /** A source changed: redraw the widgets that read it, throttled per widget. */
    fun changed(context: Context, source: Source) {
        val app = context.applicationContext
        UpdateLatency.changed(app, source)
        CoroutineScope(Dispatchers.Default).launch {
            val ids = Widgets.placedIds(app).filter { id -> Widgets.names(app, id)?.let(source::affects) ?: true }
            for (id in ids) schedule(app, id)
        }
    }

    private fun schedule(context: Context, appWidgetId: Int) {
        synchronized(this) {
            if (!pending.add(appWidgetId)) return
        }
        val now = SystemClock.elapsedRealtime()
        val wait = ((lastDraw[appWidgetId] ?: 0L) + MIN_INTERVAL_MS - now).coerceAtLeast(0L)
        main.postDelayed({
            synchronized(this) { pending.remove(appWidgetId) }
            lastDraw[appWidgetId] = SystemClock.elapsedRealtime()
            CoroutineScope(Dispatchers.Default).launch { Widgets.update(context, appWidgetId) }
        }, wait)
    }
}

/**
 * How long a change takes to reach the screen, per source (ADR-030): the event's time, then the next
 * render of a widget that reads it. The last 20 delays per source are kept for Diagnostics.
 */
object UpdateLatency {
    private val changedAt = mutableMapOf<LiveUpdates.Source, Long>()

    @Synchronized
    fun changed(context: Context, source: LiveUpdates.Source) {
        changedAt.putIfAbsent(source, SystemClock.elapsedRealtime())
    }

    /** Called after a widget was rendered: closes every open event the widget reads. */
    @Synchronized
    fun drawn(context: Context, names: Set<String>?) {
        val now = SystemClock.elapsedRealtime()
        val prefs = context.getSharedPreferences("latency", Context.MODE_PRIVATE)
        val done = changedAt.filterKeys { names == null || it.affects(names) }
        for ((source, at) in done) {
            val list = prefs.getString(source.name, null)?.let { runCatching { JSONArray(it) }.getOrNull() } ?: JSONArray()
            list.put(now - at)
            while (list.length() > 20) list.remove(0)
            prefs.edit().putString(source.name, list.toString()).putLong("${source.name}.at", System.currentTimeMillis()).apply()
            changedAt.remove(source)
        }
    }

    /** Per source: delays in ms, newest last. */
    fun all(context: Context): Map<String, List<Long>> {
        val prefs = context.getSharedPreferences("latency", Context.MODE_PRIVATE)
        return LiveUpdates.Source.entries.mapNotNull { source ->
            val list = prefs.getString(source.name, null)?.let { runCatching { JSONArray(it) }.getOrNull() } ?: return@mapNotNull null
            source.name.lowercase() to (0 until list.length()).map { list.getLong(it) }
        }.toMap()
    }

    fun summary(context: Context): String = all(context).entries.joinToString("\n") { (source, delays) ->
        val sorted = delays.sorted()
        "$source: median ${sorted[sorted.size / 2]} ms, last ${delays.last()} ms (${delays.size})"
    }.ifEmpty { "no changes measured yet" }

    @Suppress("unused")
    private fun json(map: Map<String, Long>) = JSONObject(map)
}

/**
 * "Live widgets" (ADR-030, off by default): a foreground service with a quiet notification that keeps
 * [LiveUpdates] listening when notification access isn't granted. Android needs one running component
 * to receive these events; without it, widgets refresh every 15 minutes and on app open.
 */
class LiveWidgetsService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(NotificationChannel(CHANNEL, getString(com.khaled.widgetstudio.R.string.app_name), NotificationManager.IMPORTANCE_MIN).apply { setShowBadge(false) })
        val text = if (WidgetEnvironment.language(this) == "en") "Keeping widgets up to date" else "تحديث الويدجتات أولًا بأول"
        val notification = Notification.Builder(this, CHANNEL).setSmallIcon(android.R.drawable.stat_notify_sync).setContentText(text).setOngoing(true).build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE) else startForeground(ID, notification)
        LiveUpdates.start(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY

    override fun onDestroy() {
        LiveUpdates.stop(this)
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "live"
        private const val ID = 7

        fun isEnabled(context: Context) = context.getSharedPreferences("settings", Context.MODE_PRIVATE).getBoolean("liveWidgets", false)

        fun setEnabled(context: Context, enabled: Boolean) {
            context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putBoolean("liveWidgets", enabled).apply()
            sync(context)
        }

        /** Runs the service when it is on and widgets are placed. */
        fun sync(context: Context) {
            val intent = Intent(context, LiveWidgetsService::class.java)
            if (isEnabled(context) && Widgets.placedIds(context).isNotEmpty()) runCatching { androidx.core.content.ContextCompat.startForegroundService(context, intent) }
            else context.stopService(intent)
        }
    }
}

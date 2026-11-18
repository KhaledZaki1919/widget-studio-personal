package com.khaled.widgetstudio.data

import android.Manifest
import android.app.NotificationManager
import android.content.ComponentName
import android.content.ContentUris
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.session.MediaController
import android.media.session.MediaSessionManager
import android.media.session.PlaybackState
import android.net.wifi.WifiManager
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.CalendarContract
import android.provider.Settings
import android.service.notification.NotificationListenerService
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.khaled.widgetstudio.spec.BindingResolver.Value
import com.khaled.widgetstudio.spec.MediaPlayback
import com.khaled.widgetstudio.widget.Widgets
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.ZoneId
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Catalog bindings read from the phone for each render (ADR-027). `provided` lists what this file
 * fills; `CapabilityCatalogTest` fails when a catalog binding marked native on Android has no provider.
 */
object DeviceState {
    /** Filled here; the rest come from `LiveRepository` or the resolver. */
    val provided = setOf(
        "battery.charging", "battery.symbol", "volume.level", "volume.ring", "volume.muted", "volume.symbol", "brightness.level",
        "system.wifi", "system.bluetooth", "system.airplane", "system.mobileData", "system.darkMode", "system.lowPower", "system.silent",
        "system.rotationLock", "system.dnd", "system.torch", "compass.heading", "compass.north",
        "calendar.next.title", "calendar.next.time", "calendar.next.location", "calendar.count", "calendar.1.title", "calendar.1.time",
        "calendar.2.title", "calendar.2.time", "calendar.3.title", "calendar.3.time", "calendar.4.title", "calendar.4.time",
        "media.title", "media.artist", "media.album", "media.app",
        // ADR-029
        "calendar.1.end", "calendar.2.end", "calendar.3.end", "calendar.4.end", "calendar.next.end",
        "calendar.1.calendar", "calendar.2.calendar", "calendar.3.calendar", "calendar.4.calendar",
        "calendar.1.color", "calendar.2.color", "calendar.3.color", "calendar.4.color",
        "heart.rate", "heart.resting", "heart.today", "stress.level", "energy.level", "activity.minutes", "activity.kcal",
        "screenTime.today", "earbuds.level", "media.appIcon", "app.<appField>.icon",
        "stock.<tickerField>.price", "stock.<tickerField>.change", "stock.<tickerField>.changePct", "stock.<tickerField>.series",
    )

    private fun bool(value: Boolean) = Value.Text(if (value) "1" else "0")
    private fun share(value: Double) = Value.Number(value, Math.round(value.coerceIn(0.0, 1.0) * 100).toString())

    fun batterySymbol(level: Double) = when {
        level < 0.2 -> "battery.25"
        level < 0.45 -> "battery.50"
        level < 0.8 -> "battery.75"
        else -> "battery.100"
    }

    fun volumeSymbol(level: Double) = when {
        level < 0.01 -> "speaker.slash.fill"
        level < 0.5 -> "speaker.wave.2.fill"
        else -> "speaker.wave.3.fill"
    }

    /** Only values Android gives without asking; calendar and media need their own permission. */
    fun read(context: Context, now: Instant, language: String): Map<String, Value> {
        val live = mutableMapOf<String, Value>()
        val resolver = context.contentResolver
        context.getSystemService(BatteryManager::class.java)?.let { battery ->
            live["battery.charging"] = bool(battery.isCharging)
            val percent = battery.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            if (percent in 0..100) live["battery.symbol"] = Value.Text(batterySymbol(percent / 100.0))
        }
        context.getSystemService(AudioManager::class.java)?.let { audio ->
            val media = audio.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
            live["volume.level"] = share(media)
            live["volume.muted"] = bool(media < 0.01 || audio.isStreamMute(AudioManager.STREAM_MUSIC))
            live["volume.symbol"] = Value.Text(volumeSymbol(media))
            live["volume.ring"] = share(audio.getStreamVolume(AudioManager.STREAM_RING).toDouble() / audio.getStreamMaxVolume(AudioManager.STREAM_RING).coerceAtLeast(1))
            live["system.silent"] = bool(audio.ringerMode != AudioManager.RINGER_MODE_NORMAL)
        }
        runCatching { live["brightness.level"] = share(Settings.System.getInt(resolver, Settings.System.SCREEN_BRIGHTNESS) / 255.0) }
        context.applicationContext.getSystemService(WifiManager::class.java)?.let { live["system.wifi"] = bool(it.isWifiEnabled) }
        live["system.bluetooth"] = bool(Settings.Global.getInt(resolver, Settings.Global.BLUETOOTH_ON, 0) != 0)
        live["system.airplane"] = bool(Settings.Global.getInt(resolver, Settings.Global.AIRPLANE_MODE_ON, 0) != 0)
        live["system.mobileData"] = bool(Settings.Global.getInt(resolver, "mobile_data", 1) != 0)
        live["system.darkMode"] = bool(context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK == Configuration.UI_MODE_NIGHT_YES)
        context.getSystemService(PowerManager::class.java)?.let { live["system.lowPower"] = bool(it.isPowerSaveMode) }
        live["system.rotationLock"] = bool(Settings.System.getInt(resolver, Settings.System.ACCELEROMETER_ROTATION, 1) == 0)
        context.getSystemService(NotificationManager::class.java)?.let { live["system.dnd"] = bool(it.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL) }
        val prefs = context.getSharedPreferences("live", Context.MODE_PRIVATE)
        live["system.torch"] = bool(prefs.getBoolean("torch", false))
        if (prefs.contains("heading")) {
            val heading = prefs.getFloat("heading", 0f).toDouble()
            live["compass.heading"] = Value.Number(heading, Math.round(heading).toString())
            live["compass.north"] = Value.Number(360 - heading, Math.round(360 - heading).toString())
        }
        live += calendar(context, now)
        live += TaskStore.get(context).values(now, ZoneId.systemDefault(), language)
        live += MediaHub.values(context, language)
        live += Extras.read(context, now)
        return live
    }

    private fun calendar(context: Context, now: Instant): Map<String, Value> {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.READ_CALENDAR) != PackageManager.PERMISSION_GRANTED) return emptyMap()
        val zone = ZoneId.systemDefault()
        val start = now.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant().toEpochMilli()
        val builder = CalendarContract.Instances.CONTENT_URI.buildUpon()
        ContentUris.appendId(builder, start)
        ContentUris.appendId(builder, start + 7 * 86_400_000L)
        data class Event(val first: String, val second: Long, val third: String, val end: Long, val calendar: String, val color: Int)
        val events = mutableListOf<Event>()
        runCatching {
            context.contentResolver.query(
                builder.build(), arrayOf(
                    CalendarContract.Instances.TITLE, CalendarContract.Instances.BEGIN, CalendarContract.Instances.EVENT_LOCATION, CalendarContract.Instances.ALL_DAY,
                    CalendarContract.Instances.END, CalendarContract.Instances.CALENDAR_DISPLAY_NAME, CalendarContract.Instances.DISPLAY_COLOR,
                ),
                null, null, CalendarContract.Instances.BEGIN + " ASC",
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    if (cursor.getInt(3) == 0 && cursor.getLong(1) >= now.toEpochMilli()) {
                        events += Event(cursor.getString(0) ?: "", cursor.getLong(1), cursor.getString(2) ?: "", cursor.getLong(4), cursor.getString(5) ?: "", cursor.getInt(6))
                    }
                }
            }
        }
        val live = mutableMapOf<String, Value>()
        val today = now.atZone(zone).toLocalDate()
        val todays = events.count { Instant.ofEpochMilli(it.second).atZone(zone).toLocalDate() == today }
        live["calendar.count"] = Value.Number(todays.toDouble(), todays.toString())
        events.firstOrNull()?.let {
            live["calendar.next.title"] = Value.Text(it.first)
            live["calendar.next.time"] = Value.Date(Instant.ofEpochMilli(it.second))
            live["calendar.next.location"] = Value.Text(it.third)
            if (it.end > 0) live["calendar.next.end"] = Value.Date(Instant.ofEpochMilli(it.end))
        }
        events.take(4).forEachIndexed { index, event ->
            live["calendar.${index + 1}.title"] = Value.Text(event.first)
            live["calendar.${index + 1}.time"] = Value.Date(Instant.ofEpochMilli(event.second))
            // ADR-029: end time, calendar name and color.
            if (event.end > 0) live["calendar.${index + 1}.end"] = Value.Date(Instant.ofEpochMilli(event.end))
            live["calendar.${index + 1}.calendar"] = Value.Text(event.calendar)
            live["calendar.${index + 1}.color"] = Value.Text("#%06X".format(event.color and 0xFFFFFF))
        }
        return live
    }

    /** One compass reading for the next redraw: a widget can't watch the sensor (ADR-027). */
    suspend fun sampleCompass(context: Context) {
        val manager = context.getSystemService(SensorManager::class.java) ?: return
        val sensor = manager.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) ?: return
        val heading = withTimeoutOrNull(1_500) {
            suspendCancellableCoroutine<Float> { continuation ->
                val listener = object : SensorEventListener {
                    override fun onSensorChanged(event: SensorEvent) {
                        val matrix = FloatArray(9)
                        val angles = FloatArray(3)
                        SensorManager.getRotationMatrixFromVector(matrix, event.values)
                        SensorManager.getOrientation(matrix, angles)
                        manager.unregisterListener(this)
                        if (continuation.isActive) continuation.resume(((Math.toDegrees(angles[0].toDouble()) + 360) % 360).toFloat())
                    }

                    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
                }
                manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_UI)
                continuation.invokeOnCancellation { manager.unregisterListener(listener) }
            }
        } ?: return
        context.getSharedPreferences("live", Context.MODE_PRIVATE).edit().putFloat("heading", heading).apply()
    }
}

/** Keeps the app able to see media sessions; Android requires a notification listener for that (ADR-027). */
class MediaListener : NotificationListenerService() {
    // ADR-030: the listener is the long-lived component that keeps event-driven widget updates running.
    override fun onListenerConnected() {
        MediaHub.attach(applicationContext)
        com.khaled.widgetstudio.widget.LiveUpdates.start(applicationContext)
    }

    override fun onListenerDisconnected() {
        MediaHub.detach(applicationContext)
        com.khaled.widgetstudio.widget.LiveUpdates.stop(applicationContext)
    }
}

/** Now playing from any player: the active MediaSession (NotificationListener + MediaSessionManager). */
object MediaHub {
    private val main = Handler(Looper.getMainLooper())
    private var attachedTo: MediaController? = null
    private var sessionsListener: MediaSessionManager.OnActiveSessionsChangedListener? = null

    private val callback = object : MediaController.Callback() {
        override fun onPlaybackStateChanged(state: PlaybackState?) = changed()
        override fun onMetadataChanged(metadata: MediaMetadata?) = changed()
    }

    /** Redraws at most once a second, and every 15 s while playing, so progress moves. */
    private var appContext: Context? = null
    private val redraw = Runnable {
        appContext?.let { com.khaled.widgetstudio.widget.LiveUpdates.changed(it, com.khaled.widgetstudio.widget.LiveUpdates.Source.MEDIA) }
        scheduleTick()
    }

    private fun changed() {
        main.removeCallbacks(redraw)
        main.postDelayed(redraw, 1_000)
    }

    private fun scheduleTick() {
        val playing = attachedTo?.playbackState?.state == PlaybackState.STATE_PLAYING
        if (playing) main.postDelayed(redraw, 15_000)
    }

    fun isEnabled(context: Context) = NotificationManagerCompat.getEnabledListenerPackages(context).contains(context.packageName)

    /** A card that is mostly about music can't work without access: it says so instead of drawing dashes. */
    fun needsAccess(context: Context, spec: com.khaled.widgetstudio.spec.WidgetSpec): Boolean {
        if (isEnabled(context)) return false
        val ids = com.khaled.widgetstudio.spec.BindingNames.names(spec).toList() +
            spec.layers.mapNotNull { (it.content as? com.khaled.widgetstudio.spec.LayerContent.Button)?.action }
        val media = ids.count { it.startsWith("media.") && it != "media.open" }
        return media > 0 && media * 2 >= ids.size
    }

    /** One line per media session, for Diagnostics. */
    fun sessions(context: Context): List<String> {
        if (!isEnabled(context)) return emptyList()
        val manager = context.getSystemService(MediaSessionManager::class.java) ?: return emptyList()
        val sessions = runCatching { manager.getActiveSessions(component(context)) }.getOrNull() ?: return emptyList()
        return sessions.map { session ->
            val label = runCatching {
                context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(session.packageName, 0)).toString()
            }.getOrDefault(session.packageName)
            val state = when (session.playbackState?.state) {
                PlaybackState.STATE_PLAYING -> "playing"
                PlaybackState.STATE_PAUSED -> "paused"
                PlaybackState.STATE_STOPPED -> "stopped"
                PlaybackState.STATE_BUFFERING -> "buffering"
                else -> "idle"
            }
            "$label · $state · " + (session.metadata?.getString(MediaMetadata.METADATA_KEY_TITLE) ?: "—")
        }
    }

    private fun component(context: Context) = ComponentName(context, MediaListener::class.java)

    fun attach(context: Context) {
        appContext = context
        val manager = context.getSystemService(MediaSessionManager::class.java) ?: return
        val listener = MediaSessionManager.OnActiveSessionsChangedListener { follow(context); changed() }
        sessionsListener?.let(manager::removeOnActiveSessionsChangedListener)
        sessionsListener = listener
        runCatching { manager.addOnActiveSessionsChangedListener(listener, component(context)) }
        follow(context)
    }

    fun detach(context: Context) {
        val manager = context.getSystemService(MediaSessionManager::class.java)
        sessionsListener?.let { manager?.removeOnActiveSessionsChangedListener(it) }
        sessionsListener = null
        attachedTo?.unregisterCallback(callback)
        attachedTo = null
    }

    private fun follow(context: Context) {
        val current = controller(context)
        if (current?.sessionToken == attachedTo?.sessionToken) return
        attachedTo?.unregisterCallback(callback)
        attachedTo = current
        current?.registerCallback(callback, main)
    }

    /** The session that is playing, else the most recent one. */
    /** The package of the app that is playing (ADR-029: `{{media.appIcon}}`). */
    fun playingPackage(context: Context): String? = controller(context)?.packageName

    fun controller(context: Context): MediaController? {
        if (!isEnabled(context)) return null
        val manager = context.getSystemService(MediaSessionManager::class.java) ?: return null
        val sessions = runCatching { manager.getActiveSessions(component(context)) }.getOrNull() ?: return null
        return sessions.firstOrNull { it.playbackState?.state == PlaybackState.STATE_PLAYING } ?: sessions.firstOrNull()
    }

    fun playback(context: Context, now: Instant): MediaPlayback? {
        val controller = controller(context) ?: return null
        val state = controller.playbackState ?: return null
        val duration = controller.metadata?.getLong(MediaMetadata.METADATA_KEY_DURATION) ?: 0L
        val playing = state.state == PlaybackState.STATE_PLAYING
        val moved = if (playing) (android.os.SystemClock.elapsedRealtime() - state.lastPositionUpdateTime) * state.playbackSpeed else 0f
        return MediaPlayback((state.position + moved).toDouble().coerceAtLeast(0.0) / 1000, duration / 1000.0, playing, now)
    }

    fun artwork(context: Context): Bitmap? {
        val metadata = controller(context)?.metadata ?: return null
        return metadata.getBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART) ?: metadata.getBitmap(MediaMetadata.METADATA_KEY_ART)
    }

    fun values(context: Context, language: String): Map<String, Value> {
        if (!isEnabled(context)) return mapOf("media.title" to Value.Text(if (language.startsWith("ar")) "اسمح بالوصول" else "Allow access"))
        val nothing = Value.Text(if (language.startsWith("ar")) "لا يوجد تشغيل" else "Not playing")
        val controller = controller(context) ?: return mapOf("media.title" to nothing)
        val metadata = controller.metadata ?: return mapOf("media.title" to nothing)
        val app = runCatching {
            val manager = context.packageManager
            manager.getApplicationLabel(manager.getApplicationInfo(controller.packageName, 0)).toString()
        }.getOrDefault(controller.packageName)
        return mapOf(
            "media.title" to Value.Text(metadata.getString(MediaMetadata.METADATA_KEY_TITLE) ?: ""),
            "media.artist" to Value.Text(metadata.getString(MediaMetadata.METADATA_KEY_ARTIST) ?: ""),
            "media.album" to Value.Text(metadata.getString(MediaMetadata.METADATA_KEY_ALBUM) ?: ""),
            "media.app" to Value.Text(app),
        )
    }

    /** Sends the command to the active session; what was sent to whom, or null with no session. */
    fun perform(context: Context, id: String): String? {
        val session = controller(context) ?: return null
        val controls = session.transportControls
        val sent = when (id) {
            "media.playPause" -> if (session.playbackState?.state == PlaybackState.STATE_PLAYING) "pause".also { controls.pause() } else "play".also { controls.play() }
            "media.next" -> "next".also { controls.skipToNext() }
            "media.previous" -> "previous".also { controls.skipToPrevious() }
            else -> return null
        }
        return "$sent sent to " + session.packageName
    }

    /** Nothing to control yet: the media keys wake the last player. */
    fun mediaKey(context: Context, id: String) {
        val code = when (id) {
            "media.next" -> android.view.KeyEvent.KEYCODE_MEDIA_NEXT
            "media.previous" -> android.view.KeyEvent.KEYCODE_MEDIA_PREVIOUS
            else -> android.view.KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE
        }
        val audio = context.getSystemService(AudioManager::class.java) ?: return
        audio.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_DOWN, code))
        audio.dispatchMediaKeyEvent(android.view.KeyEvent(android.view.KeyEvent.ACTION_UP, code))
    }
}

/** Waits for a value to settle before redrawing (the volume changes after the call returns). */
suspend fun settle() = delay(150)

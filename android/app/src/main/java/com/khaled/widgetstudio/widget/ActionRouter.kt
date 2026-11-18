package com.khaled.widgetstudio.widget

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.provider.Settings
import android.widget.Toast
import androidx.glance.GlanceId
import androidx.glance.action.Action
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import com.khaled.widgetstudio.data.MediaHub
import com.khaled.widgetstudio.data.settle
import com.khaled.widgetstudio.spec.Capabilities
import com.khaled.widgetstudio.spec.Capability
import com.khaled.widgetstudio.ui.MainActivity
import kotlinx.coroutines.delay

/**
 * Every tap in a widget (ADR-027), by the catalog: actions that happen in place run a callback,
 * panels and apps start an activity, and what Android forbids shows the catalog's hint. An action
 * that needs a permission the user hasn't granted opens the screen that grants it.
 * `CapabilityCatalogTest` fails when a catalog action has no branch here.
 */
object ActionRouter {
    val idKey = ActionParameters.Key<String>("action")
    val argKey = ActionParameters.Key<String>("arg")

    /** Run in place by [Perform]. */
    val inPlace = setOf(
        "counter.increment", "counter.reset", "counter.next", "stopwatch.toggle", "timer.toggle", "timer.add", "timer.reset",
        "media.playPause", "media.next", "media.previous", "volume.up", "volume.down", "volume.mute", "volume.ringUp", "volume.ringDown",
        "brightness.up", "brightness.down", "system.toggle.torch", "system.toggle.silent", "system.toggle.rotation", "system.toggle.dnd", "task.toggle",
    )

    /** Start an activity ([activity]). */
    val opens = setOf(
        "open.app", "open.url", "open.deeplink", "app.launch", "call.dial", "message.open", "shortcut.run", "camera.open", "qr.scan",
        "calendar.open", "compass.open", "weather.open", "media.open", "task.add",
        // ADR-029
        "assistant.open", "search.open", "alarm.open", "clock.open", "health.open",
    )

    fun glance(context: Context, id: String, arg: String?): Action {
        val capability = Capabilities.action(id)
        if (capability == null || capability.supportAndroid == "unsupported") return hint(id, arg)
        if (id == "open.app") return opening(context, id, arg, MainActivity.intent(context, null))
        // Tiles from before ADR-027 name an iOS Shortcut: the torch still toggles right here.
        if (id == "shortcut.run" && WidgetActions.tileKind(arg ?: "") == WidgetActions.Tile.TORCH) {
            return actionRunCallback<Perform>(actionParametersOf(idKey to "system.toggle.torch", argKey to ""))
        }
        missingPermission(context, id)?.let { return opening(context, id, arg, it) }
        if (id in inPlace) return actionRunCallback<Perform>(actionParametersOf(idKey to id, argKey to (arg ?: "")))
        if (capability.supportAndroid == "panel" && (id.startsWith("system.toggle") || capability.panel != null)) return opening(context, id, arg, panel(context, capability))
        val intent = activity(context, id, arg) ?: return hint(id, arg)
        return opening(context, id, arg, intent)
    }

    /** Opening taps go through [TapActivity], so they are logged and a dead target shows a hint. */
    private fun opening(context: Context, id: String, arg: String?, target: Intent): Action = actionStartActivity(TapActivity.intent(context, id, arg, target))

    private fun hint(id: String, arg: String?): Action = actionRunCallback<ShowHint>(actionParametersOf(idKey to id, argKey to (arg ?: "")))

    /** The settings screen to open first when a tap needs access that isn't granted. */
    fun missingPermission(context: Context, id: String): Intent? {
        val policy = context.getSystemService(NotificationManager::class.java)
        val intent = when {
            id in setOf("media.playPause", "media.next", "media.previous") && !MediaHub.isEnabled(context) -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            id in setOf("system.toggle.silent", "system.toggle.dnd") && policy?.isNotificationPolicyAccessGranted != true -> Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
            id in setOf("system.toggle.rotation", "brightness.up", "brightness.down") && !Settings.System.canWrite(context) ->
                Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:${context.packageName}"))
            else -> null
        }
        return intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    fun panel(context: Context, capability: Capability): Intent {
        val modern = Build.VERSION.SDK_INT >= 29
        val intent = when (capability.panel) {
            "wifi" -> Intent(if (modern) Settings.Panel.ACTION_WIFI else Settings.ACTION_WIFI_SETTINGS)
            "bluetooth" -> Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            "airplane" -> Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS)
            "mobileData" -> Intent(if (modern) Settings.Panel.ACTION_INTERNET_CONNECTIVITY else Settings.ACTION_DATA_ROAMING_SETTINGS)
            "display" -> Intent(Settings.ACTION_DISPLAY_SETTINGS)
            "batterySaver" -> Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
            // ADR-029
            "hotspot" -> Intent("android.settings.TETHER_SETTINGS")
            "nfc" -> Intent(if (modern) Settings.Panel.ACTION_NFC else Settings.ACTION_NFC_SETTINGS)
            "captions" -> Intent(Settings.ACTION_CAPTIONING_SETTINGS)
            else -> MainActivity.intent(context, null)
        }
        return intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    /** The screen an opening action starts; null when its value isn't set (a hint says so). */
    fun activity(context: Context, id: String, arg: String?): Intent? {
        val value = arg?.trim().orEmpty()
        val intent = when (id) {
            "open.url" -> value.takeIf { it.startsWith("https://") || it.startsWith("http://") }?.let { Intent(Intent.ACTION_VIEW, Uri.parse(it)) }
            "open.deeplink" -> value.takeIf { it.contains(":") && !it.startsWith("file:") && !it.startsWith("javascript:") }?.let { Intent(Intent.ACTION_VIEW, Uri.parse(it)) }
            "app.launch" -> value.takeIf { it.isNotEmpty() }?.let { context.packageManager.getLaunchIntentForPackage(it) }
            "call.dial" -> value.takeIf { it.isNotEmpty() }?.let { Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + Uri.encode(it))) }
            "message.open" -> value.takeIf { it.isNotEmpty() }?.let { Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:" + Uri.encode(it))) }
            "shortcut.run" -> shortcut(context, value)
            "camera.open", "qr.scan" -> Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA)
            "calendar.open" -> Intent(Intent.ACTION_VIEW, Uri.parse("content://com.android.calendar/time/${System.currentTimeMillis()}"))
            "compass.open" -> MainActivity.intent(context, MainActivity.OPEN_QIBLA)
            "task.add" -> MainActivity.intent(context, MainActivity.OPEN_TASK_ADD)
            "weather.open" -> Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com/search?q=weather"))
            "media.open" -> MediaHub.controller(context)?.packageName?.let { context.packageManager.getLaunchIntentForPackage(it) }
            "assistant.open" -> Intent(Intent.ACTION_VOICE_COMMAND)
            "search.open" -> Intent("android.search.action.GLOBAL_SEARCH")
            "alarm.open", "clock.open" -> Intent(android.provider.AlarmClock.ACTION_SHOW_ALARMS)
            "health.open" -> Intent("androidx.health.ACTION_HEALTH_CONNECT_SETTINGS")
            else -> null
        }
        return intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    /** A tile named like an iOS Shortcut does the same thing here (the old tiles keep working). */
    private fun shortcut(context: Context, name: String): Intent? = when (val kind = WidgetActions.tileKind(name)) {
        WidgetActions.Tile.CUSTOM, WidgetActions.Tile.TORCH -> null
        else -> WidgetActions.tileIntent(context, kind)
    }

    /**
     * Steps a stream one notch, keeping the system's own limits. Android refuses a raise past the
     * safe headphone level unless its warning can show, so a raise that didn't move retries with the UI.
     */
    private fun adjust(context: Context, stream: Int, direction: Int): String {
        val audio = context.getSystemService(AudioManager::class.java) ?: return "no audio service"
        val before = audio.getStreamVolume(stream)
        audio.adjustStreamVolume(stream, direction, 0)
        var after = audio.getStreamVolume(stream)
        val top = audio.getStreamMaxVolume(stream)
        if (direction == AudioManager.ADJUST_RAISE && after == before && before < top) {
            audio.adjustStreamVolume(stream, direction, AudioManager.FLAG_SHOW_UI)
            after = audio.getStreamVolume(stream)
        }
        return "$before → $after of $top"
    }

    private fun stepBrightness(context: Context, delta: Int) {
        val resolver = context.contentResolver
        val current = Settings.System.getInt(resolver, Settings.System.SCREEN_BRIGHTNESS, 128)
        Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS_MODE, Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
        Settings.System.putInt(resolver, Settings.System.SCREEN_BRIGHTNESS, (current + delta).coerceIn(5, 255))
    }

    /** Runs an in-place action, logs it and redraws every widget at once; returns what happened. */
    suspend fun perform(context: Context, id: String, arg: String, widget: Int = 0): String {
        val result = try {
            run(context, id, arg).also { TapLog.add(context, id, arg, widget, it) }
        } catch (error: Exception) {
            TapLog.add(context, id, arg, widget, "failed", error.javaClass.simpleName + ": " + error.message)
            "failed"
        }
        settle()
        UpdateLatency.changed(context, LiveUpdates.Source.ACTION)
        Widgets.updateAll(context)
        // A player reports its new state a moment after the command.
        if (id.startsWith("media.")) {
            delay(700)
            Widgets.updateAll(context)
        }
        return result
    }

    private fun run(context: Context, id: String, arg: String): String {
        val live = WidgetEnvironment.live(context)
        return when (id) {
            "counter.increment" -> { live.counter = live.counter.increment(live.settings.dhikrs); "done" }
            "counter.reset" -> { live.counter = live.counter.reset(live.settings.dhikrs); "done" }
            "counter.next" -> { live.counter = live.counter.next(live.settings.dhikrs); "done" }
            "stopwatch.toggle" -> {
                live.stopwatchStart = if (live.stopwatchStart == null) System.currentTimeMillis() else null
                MinuteTicker.schedule(context)
                "done"
            }
            "timer.toggle" -> { live.timer = live.timer.toggle(arg.toIntOrNull()); "done" }
            "timer.add" -> { live.timer = live.timer.add(arg.toIntOrNull() ?: 5); "done" }
            "timer.reset" -> { live.timer = live.timer.reset(); "done" }
            "task.toggle" -> com.khaled.widgetstudio.data.TaskStore.get(context).toggle(arg)
            "media.playPause", "media.next", "media.previous" -> MediaHub.perform(context, id) ?: "no session: media key sent".also { MediaHub.mediaKey(context, id) }
            "volume.up" -> adjust(context, AudioManager.STREAM_MUSIC, AudioManager.ADJUST_RAISE)
            "volume.down" -> adjust(context, AudioManager.STREAM_MUSIC, AudioManager.ADJUST_LOWER)
            "volume.mute" -> adjust(context, AudioManager.STREAM_MUSIC, AudioManager.ADJUST_TOGGLE_MUTE)
            "volume.ringUp" -> adjust(context, AudioManager.STREAM_RING, AudioManager.ADJUST_RAISE)
            "volume.ringDown" -> adjust(context, AudioManager.STREAM_RING, AudioManager.ADJUST_LOWER)
            "brightness.up" -> { stepBrightness(context, 25); "done" }
            "brightness.down" -> { stepBrightness(context, -25); "done" }
            "system.toggle.torch" -> if (Torch.toggle(context)) "done" else "no torch"
            "system.toggle.silent" -> context.getSystemService(AudioManager::class.java)?.let { audio ->
                audio.ringerMode = if (audio.ringerMode == AudioManager.RINGER_MODE_NORMAL) AudioManager.RINGER_MODE_SILENT else AudioManager.RINGER_MODE_NORMAL
                "done"
            } ?: "no audio service"
            "system.toggle.rotation" -> {
                val resolver = context.contentResolver
                val on = Settings.System.getInt(resolver, Settings.System.ACCELEROMETER_ROTATION, 1) != 0
                Settings.System.putInt(resolver, Settings.System.ACCELEROMETER_ROTATION, if (on) 0 else 1)
                "done"
            }
            "system.toggle.dnd" -> context.getSystemService(NotificationManager::class.java)?.let { manager ->
                val quiet = manager.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
                manager.setInterruptionFilter(if (quiet) NotificationManager.INTERRUPTION_FILTER_ALL else NotificationManager.INTERRUPTION_FILTER_PRIORITY)
                "done"
            } ?: "no notification service"
            else -> "unknown action"
        }
    }

    fun showHint(context: Context, id: String) {
        val language = WidgetEnvironment.language(context)
        val text = Capabilities.action(id)?.takeIf { it.supportAndroid == "unsupported" || it.hint != null }?.hintText(language)
            ?: Capabilities.action(id)?.let { capability ->
                val name = capability.title.resolved(language)
                if (language == "ar") "اضبط قيمة «$name» من المحرر أولًا." else "Set the value for $name in the editor first."
            }
        if (text != null) Handler(Looper.getMainLooper()).post { Toast.makeText(context.applicationContext, text, Toast.LENGTH_LONG).show() }
    }
}

/** Every in-place widget tap. */
class Perform : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val id = parameters[ActionRouter.idKey] ?: return
        val widget = runCatching { GlanceAppWidgetManager(context).getAppWidgetId(glanceId) }.getOrDefault(0)
        ActionRouter.perform(context, id, parameters[ActionRouter.argKey] ?: "", widget)
    }
}

/** A tap Android doesn't allow, or an action with no value yet: a clear message, never nothing. */
class ShowHint : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val id = parameters[ActionRouter.idKey] ?: return
        TapLog.add(context, id, parameters[ActionRouter.argKey] ?: "", 0, "hint shown")
        ActionRouter.showHint(context, id)
    }
}

/** The torch toggles directly (CameraManager); its state is remembered between taps. */
object Torch {
    fun toggle(context: Context): Boolean {
        val manager = context.getSystemService(CameraManager::class.java) ?: return false
        val camera = manager.cameraIdList.firstOrNull { id ->
            manager.getCameraCharacteristics(id).get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true
        } ?: return false
        val prefs = context.getSharedPreferences("live", Context.MODE_PRIVATE)
        val on = !prefs.getBoolean("torch", false)
        return runCatching { manager.setTorchMode(camera, on) }.isSuccess.also { if (it) prefs.edit().putBoolean("torch", on).apply() }
    }
}

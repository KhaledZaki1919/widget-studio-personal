package com.khaled.widgetstudio.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.unit.dp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalSize
import androidx.glance.LocalState
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.absolutePadding
import androidx.glance.layout.ContentScale
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.padding
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.khaled.widgetstudio.R
import com.khaled.widgetstudio.data.DataGap
import com.khaled.widgetstudio.data.DataRequirements
import com.khaled.widgetstudio.data.LiveRepository
import com.khaled.widgetstudio.data.MediaHub
import com.khaled.widgetstudio.design.DesignStore
import com.khaled.widgetstudio.render.SpecRenderer
import com.khaled.widgetstudio.spec.RenderContext
import com.khaled.widgetstudio.spec.TemplateLibrary
import com.khaled.widgetstudio.spec.Theme
import com.khaled.widgetstudio.ui.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.Instant
import com.khaled.widgetstudio.spec.BindingNames
import java.time.ZoneId

/** The app-wide renderer, template library and live data (created once per process). */
object WidgetEnvironment {
    @Volatile private var renderer: SpecRenderer? = null
    @Volatile private var library: TemplateLibrary? = null
    @Volatile private var live: LiveRepository? = null

    fun renderer(context: Context) = renderer ?: SpecRenderer(context.applicationContext).also { renderer = it }
    fun library(context: Context) = library ?: TemplateLibrary(context.applicationContext.assets).also { library = it }
    fun live(context: Context) = live ?: LiveRepository(context.applicationContext).also { live = it }

    /** "en" when the app runs in English, else Arabic (the default). */
    fun language(context: Context): String =
        if (context.resources.configuration.locales[0].language == "en") "en" else "ar"
}

/** What each placed widget shows: `design:<id>` or `template:<id>`, plus a theme for templates. */
class WidgetStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("widgets", Context.MODE_PRIVATE)

    fun choice(appWidgetId: Int): String? = prefs.getString("choice.$appWidgetId", null)
        ?: prefs.getString("template.$appWidgetId", null)?.let { "template:$it" }   // A1 widgets
    fun theme(appWidgetId: Int): Theme? = prefs.getString("theme.$appWidgetId", null)?.let { if (it == "light") Theme.LIGHT else Theme.DARK }

    fun set(appWidgetId: Int, choice: String, theme: Theme?) = prefs.edit()
        .putString("choice.$appWidgetId", choice).remove("template.$appWidgetId")
        .putString("theme.$appWidgetId", theme?.name?.lowercase()).apply()

    fun remove(appWidgetId: Int) = prefs.edit().remove("choice.$appWidgetId").remove("theme.$appWidgetId").remove("template.$appWidgetId").apply()
}

object Widgets {
    /**
     * Read while composing. A Glance session stays alive for 45 s after each update, and updating a
     * live session only recomposes what reads state; without this a tap (or the minute tick) inside
     * that window changed the value and left the old picture on screen (ADR-028).
     */
    internal val revision = mutableIntStateOf(0)

    /** Redraws every placed widget at once (after a tap, saving a design, a data refresh). */
    suspend fun updateAll(context: Context) {
        Snapshot.withMutableSnapshot { revision.intValue += 1 }
        SpecGlanceWidget().updateAll(context)
    }

    fun updateAllAsync(context: Context) {
        CoroutineScope(Dispatchers.Default).launch { updateAll(context.applicationContext) }
    }

    private val receivers = listOf(SpecWidgetReceiver::class.java, SmallWidgetReceiver::class.java, MediumWidgetReceiver::class.java, LargeWidgetReceiver::class.java,
        ExtraLargeWidgetReceiver::class.java)

    /** Redraws one placed widget (ADR-030: event-driven updates touch only the widgets that read the change). */
    suspend fun update(context: Context, appWidgetId: Int) {
        Snapshot.withMutableSnapshot { revision.intValue += 1 }
        val id = runCatching { androidx.glance.appwidget.GlanceAppWidgetManager(context).getGlanceIdBy(appWidgetId) }.getOrNull() ?: return
        SpecGlanceWidget().update(context, id)
    }

    /** The binding and action ids a placed widget's spec uses, or null when unknown (then every change redraws it). */
    fun names(context: Context, appWidgetId: Int): Set<String>? = spec(context, appWidgetId)?.let { spec ->
        BindingNames.names(spec).toSet() + spec.layers.mapNotNull { (it.content as? com.khaled.widgetstudio.spec.LayerContent.Button)?.action }
    }

    /** Every placed widget, of any size. */
    fun placedIds(context: Context): List<Int> {
        val manager = AppWidgetManager.getInstance(context)
        return receivers.flatMap { manager.getAppWidgetIds(ComponentName(context, it)).toList() }
    }

    /** The size a placed widget was added as: small, medium, large, or null for the original resizable widget. */
    fun family(context: Context, appWidgetId: Int): String? =
        when (AppWidgetManager.getInstance(context).getAppWidgetInfo(appWidgetId)?.provider?.className?.substringAfterLast('.')) {
            "SmallWidgetReceiver" -> "small"
            "MediumWidgetReceiver" -> "medium"
            "LargeWidgetReceiver" -> "large"
            "ExtraLargeWidgetReceiver" -> "xlarge"
            else -> null
        }

    private fun spec(context: Context, appWidgetId: Int): com.khaled.widgetstudio.spec.WidgetSpec? {
        val choice = WidgetStore(context).choice(appWidgetId) ?: return null
        return if (choice.startsWith("design:")) DesignStore.get(context).design(choice.removePrefix("design:"))?.spec
        else WidgetEnvironment.library(context).template(choice.removePrefix("template:"))
    }

    fun showsCompass(context: Context): Boolean = placedIds(context).any { id ->
        spec(context, id)?.let { "system" in DataRequirements.bindingGroups(it) && com.khaled.widgetstudio.spec.BindingNames.names(it).any { name -> name.startsWith("compass.") } } ?: false
    }
}

/**
 * The home-screen widget (ADR-025): the chosen design or template drawn into a bitmap at the
 * widget's exact size (re-rendered on resize) with live data, shown with Glance, with a tap area
 * over each button. Missing data shows a message (DataGap), never sample numbers.
 */
class SpecGlanceWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Exact

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val appWidgetId = GlanceAppWidgetManager(context).getAppWidgetId(id)
        provideContent { Content(context, appWidgetId) }
    }

    @Composable
    private fun Content(context: Context, appWidgetId: Int) {
        // Both make a running session redraw on update (see Widgets.revision).
        Widgets.revision.intValue
        LocalState.current
        val store = WidgetStore(context)
        val choice = store.choice(appWidgetId)
        val live = WidgetEnvironment.live(context)
        val language = WidgetEnvironment.language(context)
        val now = Instant.now()
        val data = live.snapshot(now, language)
        val design = choice?.takeIf { it.startsWith("design:") }?.let { DesignStore.get(context).design(it.removePrefix("design:")) }
        val template = choice?.takeIf { it.startsWith("template:") }?.let { WidgetEnvironment.library(context).template(it.removePrefix("template:")) }
        val spec = design?.spec ?: template
        if (spec == null) {
            Message(context, appWidgetId, context.getString(if (choice == null) R.string.widget_choose else R.string.widget_missing))
            return
        }
        if (MediaHub.needsAccess(context, spec)) {
            Message(context, appWidgetId, if (language == "ar") "اسمح بالوصول إلى الإشعارات لعرض الموسيقى والتحكم بها" else "Allow access to show and control music", Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            return
        }
        val gap = DataRequirements.gap(spec, live, data)
        if (gap != null) {
            Message(context, appWidgetId, gapText(language, gap), MainActivity.intent(context, MainActivity.OPEN_SETTINGS))
            return
        }
        val renderContext = design?.renderContext(context, now, language, data, DesignStore.get(context).image(design), live.settings.clockFormat)
            ?: RenderContext(now = now, language = language, zone = ZoneId.systemDefault(), data = data, uses24Hour = live.settings.clockFormat.uses24Hour(context), theme = store.theme(appWidgetId))
        val artwork = if ("media" in DataRequirements.bindingGroups(spec)) MediaHub.artwork(context) else null
        val size = LocalSize.current
        val density = context.resources.displayMetrics.density
        val radius = if (Build.VERSION.SDK_INT < 31) 16 * density else 0f
        // ADR-029: the playing app's icon and the icons of the design's app fields.
        val images = com.khaled.widgetstudio.data.Extras.images(context, spec) { key -> (design?.fieldValues?.get(key) ?: spec.field(key)?.default)?.resolved(language) }
        val result = WidgetEnvironment.renderer(context).render(spec, renderContext.copy(mediaArtwork = artwork, images = images), (size.width.value * density).toInt(), (size.height.value * density).toInt(), cornerRadius = radius)
        // ADR-030: how long the change this render shows took to arrive.
        UpdateLatency.drawn(context, BindingNames.names(spec).toSet())
        var modifier = GlanceModifier.fillMaxSize().appWidgetBackground()
        if (Build.VERSION.SDK_INT >= 31) modifier = modifier.cornerRadius(android.R.dimen.system_app_widget_background_radius)
        Box(modifier = modifier) {
            Image(ImageProvider(result.bitmap), contentDescription = spec.name.resolved(language), modifier = GlanceModifier.fillMaxSize(), contentScale = ContentScale.FillBounds)
            // Glance keeps only the first 10 children of a Box, so tap areas go in groups.
            for (group in TapZones.groups(result.buttons)) {
                Box(modifier = GlanceModifier.fillMaxSize()) {
                    for (button in group) TapZone(context, button, size.width.value, size.height.value, density)
                }
            }
        }
    }

    /**
     * Fills the widget and pads in from all four sides with absolute (left/right) padding. Start
     * padding and start alignment follow the launcher's direction, which landed every tap area on
     * the mirrored side on an Arabic phone; this lands on the same spot in either direction (ADR-028).
     */
    @Composable
    private fun TapZone(context: Context, button: com.khaled.widgetstudio.render.HitArea, widthDp: Float, heightDp: Float, density: Float) {
        val inset = TapZones.insets(button.rect.left, button.rect.top, button.rect.right, button.rect.bottom, widthDp, heightDp, density)
        Box(modifier = GlanceModifier.fillMaxSize().absolutePadding(left = inset.left.dp, top = inset.top.dp, right = inset.right.dp, bottom = inset.bottom.dp)) {
            Box(modifier = GlanceModifier.fillMaxSize().clickable(ActionRouter.glance(context, button.action, button.arg))) {}
        }
    }

    @Composable
    private fun Message(context: Context, appWidgetId: Int, text: String, intent: Intent? = null) {
        Box(
            modifier = GlanceModifier.fillMaxSize().appWidgetBackground().background(ColorProvider(R.color.widget_empty))
                .clickable(actionStartActivity(intent ?: ConfigureActivity.intent(context, appWidgetId))),
            contentAlignment = Alignment.Center,
        ) {
            Text(text, modifier = GlanceModifier.padding(12.dp), style = TextStyle(color = ColorProvider(R.color.widget_empty_text), textAlign = TextAlign.Center))
        }
    }

    private fun gapText(language: String, gap: DataGap): String {
        val ar = language == "ar"
        return when (gap) {
            DataGap.NO_LOCATION -> if (ar) "اسمح بالموقع في ستوديو الويدجت لعرض الطقس والصلاة" else "Allow location in Widget Studio for weather and prayer times"
            DataGap.NO_WEATHER -> if (ar) "لا توجد بيانات طقس بعد. افتح التطبيق مع الاتصال بالإنترنت" else "No weather yet. Open the app while online"
            DataGap.NO_HEALTH -> if (ar) "اسمح بالوصول إلى Health Connect لعرض الخطوات والنوم" else "Allow Health Connect to show steps and sleep"
            DataGap.NO_BATTERY -> if (ar) "تعذّرت قراءة البطارية" else "Battery level unavailable"
        }
    }
}

/** Where a tap area sits, in dp from each edge of the widget; pure, so the tests pin it. */
object TapZones {
    data class Insets(val left: Float, val top: Float, val right: Float, val bottom: Float)

    /** Children of one Box that Glance keeps. */
    const val perBox = 10

    fun <T> groups(buttons: List<T>): List<List<T>> = buttons.chunked(perBox)

    fun insets(leftPx: Float, topPx: Float, rightPx: Float, bottomPx: Float, widthDp: Float, heightDp: Float, density: Float) = Insets(
        left = (leftPx / density).coerceAtLeast(0f),
        top = (topPx / density).coerceAtLeast(0f),
        right = (widthDp - rightPx / density).coerceAtLeast(0f),
        bottom = (heightDp - bottomPx / density).coerceAtLeast(0f),
    )
}

/** Old tile designs name an iOS Shortcut; these map the name to Android (TileSetup.forName). Taps go through ActionRouter. */
object WidgetActions {
    /** What a tile named like the iOS Shortcut does on Android (TileSetup.forName). */
    enum class Tile { WIFI, TORCH, APPEARANCE, BLUETOOTH, AIRPLANE, LOW_POWER, CELLULAR, ORIENTATION, SILENT, QR, CAMERA, CUSTOM }

    fun tileKind(name: String): Tile {
        val key = name.lowercase().filter { it.isLetterOrDigit() }
        fun has(vararg words: String) = words.any { key.contains(it) }
        return when {
            has("wifi", "wlan", "واي") -> Tile.WIFI
            has("torch", "flash", "كشاف", "فلاش") -> Tile.TORCH
            has("dark", "appearance", "داكن", "ليلي", "مظهر") -> Tile.APPEARANCE
            has("bluetooth", "بلوتوث") -> Tile.BLUETOOTH
            has("airplane", "aeroplane", "flight", "طيران") -> Tile.AIRPLANE
            has("lowpower", "battery", "توفير", "طاقة") -> Tile.LOW_POWER
            has("cellular", "mobiledata", "data", "بيانات") -> Tile.CELLULAR
            has("rotation", "orientation", "rotate", "تدوير") -> Tile.ORIENTATION
            has("mute", "silent", "silence", "صامت", "كتم") -> Tile.SILENT
            has("qr", "barcode", "باركود") -> Tile.QR
            has("camera", "كاميرا") -> Tile.CAMERA
            else -> Tile.CUSTOM
        }
    }

    /** Android doesn't let apps toggle Wi-Fi, Bluetooth, dark mode and the like: they open the matching panel or settings page. */
    fun tileIntent(context: Context, kind: Tile): Intent {
        val panel = Build.VERSION.SDK_INT >= 29
        val intent = when (kind) {
            Tile.WIFI -> Intent(if (panel) Settings.Panel.ACTION_WIFI else Settings.ACTION_WIFI_SETTINGS)
            Tile.BLUETOOTH -> Intent(Settings.ACTION_BLUETOOTH_SETTINGS)
            Tile.APPEARANCE, Tile.ORIENTATION -> Intent(Settings.ACTION_DISPLAY_SETTINGS)
            Tile.AIRPLANE -> Intent(Settings.ACTION_AIRPLANE_MODE_SETTINGS)
            Tile.LOW_POWER -> Intent(Settings.ACTION_BATTERY_SAVER_SETTINGS)
            Tile.CELLULAR -> Intent(if (panel) Settings.Panel.ACTION_INTERNET_CONNECTIVITY else Settings.ACTION_DATA_ROAMING_SETTINGS)
            Tile.SILENT -> Intent(if (panel) Settings.Panel.ACTION_VOLUME else Settings.ACTION_SOUND_SETTINGS)
            Tile.QR, Tile.CAMERA -> Intent(MediaStore.INTENT_ACTION_STILL_IMAGE_CAMERA)
            Tile.TORCH, Tile.CUSTOM -> MainActivity.intent(context, null)
        }
        return intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

}

/**
 * The widget receivers. [SpecWidgetReceiver] is the original resizable one: hidden from the picker,
 * it keeps widgets placed before ADR-027 working. The three sizes each have a picker entry.
 */
open class SpecWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = SpecGlanceWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        MinuteTicker.schedule(context)
        com.khaled.widgetstudio.data.RefreshWorker.schedule(context)
        LiveWidgetsService.sync(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        MinuteTicker.cancel(context)
    }

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        MinuteTicker.schedule(context)
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        val store = WidgetStore(context)
        appWidgetIds.forEach(store::remove)
    }
}

class SmallWidgetReceiver : SpecWidgetReceiver()
class MediumWidgetReceiver : SpecWidgetReceiver()
class LargeWidgetReceiver : SpecWidgetReceiver()
/** ADR-030: the 4 × 6 size (xlarge designs; any smaller design scales in). */
class ExtraLargeWidgetReceiver : SpecWidgetReceiver()

/**
 * Clocks, dates, countdowns and the stopwatch re-render once a minute (ADR-025): a windowed alarm
 * at the start of each minute. TextClock/Chronometer would format digits with the phone's locale
 * (Arabic-Indic on ar-EG), which the dot font can't draw.
 */
object MinuteTicker {
    private const val ACTION = "com.khaled.widgetstudio.TICK"

    fun schedule(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val next = (System.currentTimeMillis() / 60_000 + 1) * 60_000
        alarms.setWindow(AlarmManager.RTC, next, 5_000, pending(context))
    }

    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java)?.cancel(pending(context))
    }

    private fun pending(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context, 0, Intent(context, TickReceiver::class.java).setAction(ACTION), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    fun hasWidgets(context: Context): Boolean = Widgets.placedIds(context).isNotEmpty()
}

class TickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (!MinuteTicker.hasWidgets(context)) return
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                if (Widgets.showsCompass(context)) com.khaled.widgetstudio.data.DeviceState.sampleCompass(context)
                Widgets.updateAll(context)
            } finally {
                MinuteTicker.schedule(context)
                pending.finish()
            }
        }
    }
}

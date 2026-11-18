package com.khaled.widgetstudio.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.widget.RemoteViews
import com.khaled.widgetstudio.R
import com.khaled.widgetstudio.spec.DataSnapshot
import com.khaled.widgetstudio.spec.Family
import com.khaled.widgetstudio.spec.RenderContext
import java.time.Instant
import java.time.ZoneId

/**
 * Picker previews on Android 15+ (ADR-027): a real design drawn for each size. Older versions use
 * the static images. The system limits how often these may change, so it runs once per app version.
 */
object WidgetPreviews {
    private val sizes = listOf(
        Triple(SmallWidgetReceiver::class.java, Family.SMALL, "mono.clock.dotAnalog"),
        Triple(MediumWidgetReceiver::class.java, Family.MEDIUM, "mono.weather.forecast"),
        Triple(LargeWidgetReceiver::class.java, Family.LARGE, "mono.control.center"),
    )

    fun publish(context: Context) {
        if (Build.VERSION.SDK_INT < 35) return
        val prefs = context.getSharedPreferences("widgets", Context.MODE_PRIVATE)
        val version = context.packageManager.getPackageInfo(context.packageName, 0).longVersionCode
        if (prefs.getLong("previewsFor", -1) == version) return
        val manager = AppWidgetManager.getInstance(context)
        val language = WidgetEnvironment.language(context)
        val now = Instant.now()
        val density = context.resources.displayMetrics.density
        for ((receiver, family, id) in sizes) {
            val spec = WidgetEnvironment.library(context).template(id) ?: continue
            val data = DataSnapshot.sample(now, ZoneId.systemDefault())
            val result = WidgetEnvironment.renderer(context).render(
                spec, RenderContext(now = now, language = language, data = data), (family.width * density).toInt(), (family.height * density).toInt(),
            )
            val views = RemoteViews(context.packageName, R.layout.widget_preview)
            views.setImageViewBitmap(R.id.preview, result.bitmap)
            manager.setWidgetPreview(ComponentName(context, receiver), AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN, views)
        }
        prefs.edit().putLong("previewsFor", version).apply()
    }
}

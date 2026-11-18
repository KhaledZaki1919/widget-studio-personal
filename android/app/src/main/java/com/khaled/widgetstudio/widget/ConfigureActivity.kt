package com.khaled.widgetstudio.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.lifecycle.lifecycleScope
import com.khaled.widgetstudio.design.DesignStore
import com.khaled.widgetstudio.spec.RenderContext
import com.khaled.widgetstudio.spec.Theme
import com.khaled.widgetstudio.ui.DesignPreview
import com.khaled.widgetstudio.ui.Segmented
import com.khaled.widgetstudio.ui.SpecPreview
import com.khaled.widgetstudio.ui.StudioTheme
import com.khaled.widgetstudio.ui.appLanguage
import com.khaled.widgetstudio.ui.tr
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

/**
 * Shown when a Widget Studio widget is added or reconfigured: the user's saved designs first,
 * then the templates, with search and light/dark for templates. Nothing is picked automatically;
 * backing out leaves the widget unplaced.
 */
class ConfigureActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val appWidgetId = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        setResult(RESULT_CANCELED, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId))
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
            finish()
            return
        }
        enableEdgeToEdge()
        setContent {
            StudioTheme {
                Picker(Widgets.family(this, appWidgetId)) { choice, theme ->
                    WidgetStore(this).set(appWidgetId, choice, theme)
                    lifecycleScope.launch {
                        SpecGlanceWidget().update(this@ConfigureActivity, GlanceAppWidgetManager(this@ConfigureActivity).getGlanceIdBy(appWidgetId))
                        MinuteTicker.schedule(this@ConfigureActivity)
                        com.khaled.widgetstudio.data.RefreshWorker.schedule(this@ConfigureActivity)
                        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId))
                        finish()
                    }
                }
            }
        }
    }

    companion object {
        fun intent(context: Context, appWidgetId: Int) = Intent(context, ConfigureActivity::class.java)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Picker(family: String?, onPick: (String, Theme?) -> Unit) {
    val context = LocalContext.current
    val language = appLanguage()
    val designs by DesignStore.get(context).designs.collectAsState()
    val templates = remember { WidgetEnvironment.library(context).all }
    var query by rememberSaveable { mutableStateOf("") }
    var theme by rememberSaveable { mutableStateOf<String?>(null) }
    fun matches(vararg names: String) = query.isBlank() || names.any { it.contains(query.trim(), ignoreCase = true) }
    /** A size widget lists only that size (ADR-027); the original widget lists everything. */
    fun fits(spec: com.khaled.widgetstudio.spec.WidgetSpec) = family == null || spec.family.name.lowercase() == family
    val shownDesigns = designs.filter { matches(it.name) && fits(it.spec) }
    val shownTemplates = templates.filter { matches(it.name.resolved("en"), it.name.resolved("ar")) && fits(it) }
    Scaffold(topBar = { TopAppBar(title = { Text(tr("Choose a design", "اختر تصميمًا للويدجت")) }) }) { padding ->
        LazyVerticalGrid(
            columns = GridCells.Adaptive(160.dp),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding() + 8.dp, bottom = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    OutlinedTextField(query, { query = it }, label = { Text(tr("Search", "بحث")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    Segmented(listOf(null to tr("Template", "حسب القالب"), "light" to tr("Light", "فاتح"), "dark" to tr("Dark", "داكن")), theme, { theme = it })
                }
            }
            if (shownDesigns.isNotEmpty()) {
                item(span = { GridItemSpan(maxLineSpan) }) { Text(tr("My widgets", "ودجاتي"), style = MaterialTheme.typography.titleMedium) }
                items(shownDesigns, key = { "d" + it.id }, span = { GridItemSpan(if (it.spec.family.width > 200) maxLineSpan else 1) }) { design ->
                    Choice(design.name, { onPick("design:${design.id}", null) }) {
                        DesignPreview(design, language, DesignStore.get(context).image(design), Modifier.fillMaxWidth())
                    }
                }
            }
            item(span = { GridItemSpan(maxLineSpan) }) { Text(tr("Templates", "القوالب"), style = MaterialTheme.typography.titleMedium) }
            items(shownTemplates, key = { "t" + it.id }, span = { GridItemSpan(if (it.family.width > 200) maxLineSpan else 1) }) { spec ->
                val chosenTheme = theme?.let { if (it == "light") Theme.LIGHT else Theme.DARK }
                Choice(spec.name.resolved(language), { onPick("template:${spec.id}", chosenTheme) }) {
                    SpecPreview(spec, spec.id + theme + language, Modifier.fillMaxWidth()) {
                        val now = Instant.now()
                        RenderContext(now = now, language = language, zone = ZoneId.systemDefault(), data = WidgetEnvironment.live(context).previewSnapshot(now), theme = chosenTheme)
                    }
                }
            }
        }
    }
}

@Composable
private fun Choice(title: String, onClick: () -> Unit, preview: @Composable () -> Unit) {
    Card(shape = RoundedCornerShape(16.dp), modifier = Modifier.clickable(onClick = onClick)) {
        Column(Modifier.padding(10.dp)) {
            Column(Modifier.clip(RoundedCornerShape(16.dp))) { preview() }
            Text(title, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 8.dp), maxLines = 1)
        }
    }
}

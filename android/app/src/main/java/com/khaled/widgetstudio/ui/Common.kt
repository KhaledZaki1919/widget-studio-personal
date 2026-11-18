package com.khaled.widgetstudio.ui

import android.graphics.Bitmap
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.khaled.widgetstudio.design.SavedDesign
import com.khaled.widgetstudio.render.Drawing
import com.khaled.widgetstudio.spec.RenderContext
import com.khaled.widgetstudio.spec.WidgetSpec
import com.khaled.widgetstudio.widget.WidgetEnvironment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** The app's language for UI text: English when the app runs in English, else Arabic (default). */
@Composable
fun appLanguage(): String = if (LocalConfiguration.current.locales[0].language == "en") "en" else "ar"

/** UI text in the app's language; both languages live side by side, so neither is ever missing. */
@Composable
fun tr(en: String, ar: String): String = if (appLanguage() == "en") en else ar

/** The app's colors: the Mono red accent on black or white. */
@Composable
fun StudioTheme(content: @Composable () -> Unit) {
    val accent = Color(0xFFE2231A)
    val scheme = if (isSystemInDarkTheme()) darkColorScheme(primary = accent, secondary = accent) else lightColorScheme(primary = accent, secondary = accent)
    MaterialTheme(colorScheme = scheme, content = content)
}

/** A spec drawn by the real renderer, at real proportions. [render] builds the context off the main thread. */
@Composable
fun SpecPreview(spec: WidgetSpec, key: Any, modifier: Modifier = Modifier, context: () -> RenderContext) {
    val app = LocalContext.current
    val density = LocalDensity.current.density
    val bitmap by produceState<ImageBitmap?>(null, key) {
        value = withContext(Dispatchers.Default) {
            val width = (spec.family.width * density).toInt()
            val height = (spec.family.height * density).toInt()
            WidgetEnvironment.renderer(app).render(spec, context(), width, height, cornerRadius = 22 * density).bitmap.asImageBitmap()
        }
    }
    Box(modifier.aspectRatio((spec.family.width / spec.family.height).toFloat())) {
        bitmap?.let { Image(it, contentDescription = null, modifier = Modifier.fillMaxSize()) }
    }
}

/** A saved design previewed with live data and its photo. */
@Composable
fun DesignPreview(design: SavedDesign, language: String, photo: Bitmap?, modifier: Modifier = Modifier, forced: Map<String, String> = emptyMap(), overrides: Map<String, String> = emptyMap()) {
    val app = LocalContext.current
    SpecPreview(design.spec, listOf(design, language, photo, forced, overrides), modifier) {
        val live = WidgetEnvironment.live(app)
        design.renderContext(app, java.time.Instant.now(), language, live.previewSnapshot(), photo, live.settings.clockFormat).copy(forcedStates = forced, overrides = overrides)
    }
}

@Composable
fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 20.dp, bottom = 6.dp))
}

@Composable
fun SectionCard(content: @Composable () -> Unit) {
    Card(shape = RoundedCornerShape(16.dp), modifier = Modifier.fillMaxWidth()) { Column(Modifier.padding(14.dp)) { content() } }
}

@Composable
fun Footnote(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 6.dp))
}

/** A segmented choice of [options] (value to label). */
@Composable
fun <T> Segmented(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit, modifier: Modifier = Modifier) {
    SingleChoiceSegmentedButtonRow(modifier.fillMaxWidth()) {
        options.forEachIndexed { index, (value, label) ->
            SegmentedButton(selected = selected == value, onClick = { onSelect(value) }, shape = SegmentedButtonDefaults.itemShape(index, options.size)) {
                Text(label, maxLines = 1)
            }
        }
    }
}

/** A labeled dropdown of [options]. */
@Composable
fun <T> Dropdown(label: String, options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().clickable { open = true }.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f))
        Box {
            Text(options.firstOrNull { it.first == selected }?.second ?: "—", color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Medium)
            DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
                options.forEach { (value, text) -> DropdownMenuItem(text = { Text(text) }, onClick = { onSelect(value); open = false }) }
            }
        }
    }
}

private val swatches = listOf(
    "#FFFFFF", "#0E0E0E", "#7A7A7A", "#E2231A", "#FF3B30", "#FF9500", "#FFCC00", "#34C759", "#00C7BE", "#30B0C7",
    "#007AFF", "#5856D6", "#AF52DE", "#FF2D55", "#A2845E", "#1C1C1E", "#F2F2F7", "#CFE3F5", "#FAF6F0", "#2B2B2B",
)

/** A color as swatches plus a hex field; [onReset] shows a reset button when the color is overridden. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ColorChooser(label: String, hex: String, onChange: (String) -> Unit, onReset: (() -> Unit)? = null) {
    var open by remember { mutableStateOf(false) }
    Column {
        Row(Modifier.fillMaxWidth().clickable { open = !open }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(label, modifier = Modifier.weight(1f))
            if (onReset != null) TextButton(onClick = onReset) { Text(tr("Reset", "إعادة")) }
            Box(Modifier.size(28.dp).clip(CircleShape).background(composeColor(hex)).border(1.dp, MaterialTheme.colorScheme.outline, CircleShape))
        }
        if (open) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 6.dp)) {
                swatches.forEach { swatch ->
                    Box(Modifier.size(32.dp).clip(CircleShape).background(composeColor(swatch)).border(if (swatch.equals(hex, true)) 3.dp else 1.dp, MaterialTheme.colorScheme.primary, CircleShape).clickable { onChange(swatch) })
                }
            }
            var text by remember(hex) { mutableStateOf(hex) }
            OutlinedTextField(text, onValueChange = { value ->
                text = value
                if (Drawing.parseHex(value) != null) onChange(value.uppercase())
            }, label = { Text("#RRGGBB") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        }
    }
}

fun composeColor(hex: String): Color = Drawing.parseHex(hex)?.let { Color(it) } ?: Color.Transparent

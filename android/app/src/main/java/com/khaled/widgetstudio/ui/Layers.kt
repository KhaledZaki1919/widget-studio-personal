package com.khaled.widgetstudio.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.khaled.widgetstudio.design.AILayoutFix
import com.khaled.widgetstudio.design.LayerEditing
import com.khaled.widgetstudio.design.SpecLayout
import com.khaled.widgetstudio.design.SpecValidator
import com.khaled.widgetstudio.spec.Bindings
import com.khaled.widgetstudio.spec.Capabilities
import com.khaled.widgetstudio.spec.FontSpec
import com.khaled.widgetstudio.spec.LText
import com.khaled.widgetstudio.spec.Layer
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.SpecExpression
import com.khaled.widgetstudio.spec.SpecTokens
import com.khaled.widgetstudio.spec.StateVariant

private fun EditorState.layers() = design.spec.layers
private fun EditorState.setLayers(key: String? = null, change: (List<Layer>) -> List<Layer>) =
    update(key) { it.copy(spec = it.spec.copy(layers = change(it.spec.layers))) }

@Composable
private fun kindName(content: LayerContent): String = when (content) {
    is LayerContent.Text -> tr("Text", "نص")
    is LayerContent.Image -> tr("Photo", "صورة")
    is LayerContent.Shape -> tr("Shape", "شكل")
    is LayerContent.Icon -> tr("Icon", "أيقونة")
    is LayerContent.AnalogClock -> tr("Clock", "ساعة")
    is LayerContent.DotGrid, is LayerContent.DotBars -> tr("Dots", "نقاط")
    is LayerContent.Ring -> tr("Ring", "حلقة")
    is LayerContent.ForecastRow -> tr("Forecast", "توقعات الطقس")
    is LayerContent.Button -> tr("Button", "زر")
    is LayerContent.CalendarMonth -> tr("Calendar", "تقويم")
    is LayerContent.ListL -> tr("List", "قائمة")
    is LayerContent.ProgressBar -> tr("Progress bar", "شريط التقدم")
    is LayerContent.Stack -> when (content.axis) {
        "horizontal" -> tr("Row", "صف")
        "grid" -> tr("Grid", "شبكة")
        "radial" -> tr("Circle", "دائرة")
        else -> tr("Column", "عمود")
    }
    is LayerContent.Spacer -> tr("Space", "مسافة")
    is LayerContent.States -> tr("States", "الحالات")
    is LayerContent.Chart -> tr("Chart", "رسم بياني")
    is LayerContent.Unknown -> tr("Unknown layer", "طبقة غير معروفة")
}

private fun summary(layer: Layer, language: String): String = when (val c = layer.content) {
    is LayerContent.Text -> c.value.resolved(language)
    is LayerContent.Icon -> c.symbol
    is LayerContent.Stack -> c.children.joinToString(" · ") { summary(it, language) }.take(60)
    is LayerContent.ListL -> c.items.joinToString(" · ") { it.title.resolved(language) }.take(60)
    else -> ""
}

/** The layers of the design (or a stack's items), back to front, with overlap marks. */
@Composable
fun LayersList(state: EditorState, parent: List<Int>, onOpen: (List<Int>) -> Unit) {
    val language = appLanguage()
    val layers = if (parent.isEmpty()) state.layers() else (LayerEditing.layer(parent, state.layers())?.content as? LayerContent.Stack)?.children ?: emptyList()
    val overlapping = if (parent.isEmpty()) SpecLayout.overlapping(layers) else emptySet()
    var selecting by remember { mutableStateOf(false) }
    var selection by remember { mutableStateOf(setOf<Int>()) }
    var groupFailed by remember { mutableStateOf(false) }
    SectionTitle(if (parent.isEmpty()) tr("Layers, back to front", "الطبقات من الخلف إلى الأمام") else tr("Items, in order", "العناصر بالترتيب"))
    if (overlapping.isNotEmpty()) SectionCard {
        Text("⚠ " + tr("Some texts cover each other (marked below).", "بعض النصوص يغطي بعضها بعضًا (مُعلَّمة بالأسفل)."), color = MaterialTheme.colorScheme.error)
        TextButton(onClick = { state.update { it.copy(spec = AILayoutFix.fix(it.spec)) } }) { Text(tr("Arrange automatically", "رتّب تلقائيًا")) }
    }
    if (parent.isEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(vertical = 6.dp)) {
        OutlinedButton(onClick = { selecting = !selecting; selection = emptySet() }) { Text(if (selecting) tr("Done", "تم") else tr("Select", "تحديد")) }
        if (selecting) OutlinedButton(enabled = selection.size >= 2, onClick = {
            val grouped = LayerEditing.group(selection, state.layers())
            if (grouped == null) groupFailed = true else { state.setLayers { grouped.first }; selection = emptySet(); selecting = false }
        }) { Text(tr("Stack", "اجمع في مجموعة")) }
    }
    if (groupFailed) Footnote(tr("Lists, calendars, forecasts, photos and buttons keep their own frame. Pick texts, icons, shapes or stacks.", "القوائم والتقويمات والتوقعات والصور والأزرار تبقى في إطارها. اختر نصوصًا أو أيقونات أو أشكالًا أو مجموعات."))
    SectionCard {
        layers.forEachIndexed { index, layer ->
            val path = parent + index
            Row(Modifier.fillMaxWidth().clickable { if (selecting) selection = if (index in selection) selection - index else selection + index else onOpen(path) }.padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (selecting) Checkbox(checked = index in selection, onCheckedChange = { selection = if (it) selection + index else selection - index })
                Column(Modifier.weight(1f)) {
                    Text(kindName(layer.content) + if (index in overlapping) "  ⚠" else "", style = MaterialTheme.typography.bodyLarge)
                    summary(layer, language).takeIf { it.isNotEmpty() }?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1) }
                }
                TextButton(enabled = index > 0, onClick = { state.setLayers { LayerEditing.move(parent, index, index - 1, it) } }) { Text("↑") }
                TextButton(enabled = index < layers.size - 1, onClick = { state.setLayers { LayerEditing.move(parent, index, index + 1, it) } }) { Text("↓") }
            }
            if (index < layers.size - 1) HorizontalDivider()
        }
    }
    Footnote(tr("Tap a layer to edit it. ↑ ↓ change the order; Select puts several in one stack that lines them up without overlapping.", "اضغط طبقة لتعديلها. ↑ ↓ لتغيير الترتيب، و«تحديد» لجمع عدة طبقات في مجموعة تصفّها دون تداخل."))
}

/** One layer: frame, opacity, mirror and the settings of its kind. */
@Composable
fun LayerDetail(state: EditorState, path: List<Int>, onOpenItems: (List<Int>) -> Unit, onGone: () -> Unit) {
    val layer = LayerEditing.layer(path, state.layers())
    if (layer == null) {
        Footnote(tr("This layer was removed.", "حُذفت هذه الطبقة."))
        TextButton(onClick = onGone) { Text(tr("Back to layers", "عودة إلى الطبقات")) }
        return
    }
    val top = path.size == 1
    val key = path.joinToString(".")
    fun edit(field: String, change: (Layer) -> Layer) = state.setLayers("$key.$field") { LayerEditing.replace(path, it, change(LayerEditing.layer(path, it) ?: layer)) }

    SectionTitle(kindName(layer.content))
    SectionCard {
        Text(if (top) tr("Position and size", "الموضع والحجم") else tr("Size (0 = automatic)", "الحجم (0 = تلقائي)"), style = MaterialTheme.typography.labelLarge)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (top) {
                NumberField(tr("Left", "من اليسار"), layer.frame.x, Modifier.weight(1f)) { v -> edit("x") { it.copy(frame = it.frame.copy(x = v)) } }
                NumberField(tr("Top", "من الأعلى"), layer.frame.y, Modifier.weight(1f)) { v -> edit("y") { it.copy(frame = it.frame.copy(y = v)) } }
            }
            NumberField(tr("Width", "العرض"), layer.frame.w, Modifier.weight(1f)) { v -> edit("w") { it.copy(frame = it.frame.copy(w = v)) } }
            NumberField(tr("Height", "الارتفاع"), layer.frame.h, Modifier.weight(1f)) { v -> edit("h") { it.copy(frame = it.frame.copy(h = v)) } }
        }
        Text(tr("Opacity", "الشفافية"), modifier = Modifier.padding(top = 8.dp))
        Slider(value = (layer.opacity ?: 1.0).toFloat(), valueRange = 0.1f..1f, onValueChange = { v -> edit("opacity") { it.copy(opacity = if (v >= 0.99f) null else v.toDouble()) } })
        if (top) Row(verticalAlignment = Alignment.CenterVertically) {
            Text(tr("Mirror in Arabic", "اعكس الموضع بالعربية"), modifier = Modifier.weight(1f))
            Switch(checked = layer.mirror == true, onCheckedChange = { on -> edit("mirror") { it.copy(mirror = if (on) true else null) } })
        }
        Footnote(tr("Positions are widget points from the top left. Mirrored layers move to the other side in Arabic; text never flips.", "المواضع بنقاط الويدجت من أعلى اليسار. الطبقات المعكوسة تنتقل إلى الجهة الأخرى بالعربية، ولا تنقلب النصوص."))
    }
    when (val c = layer.content) {
        is LayerContent.Text -> TextSettings(c) { field, change -> edit(field) { it.copy(content = change(it.content as? LayerContent.Text ?: c)) } }
        is LayerContent.States -> StatesSettings(state, c) { change -> edit("states") { l -> l.copy(content = change(l.content as LayerContent.States)) } }
        is LayerContent.Icon -> SectionCard {
            NumberField(tr("Size", "الحجم"), c.size) { v -> edit("size") { it.copy(content = (it.content as LayerContent.Icon).copy(size = v)) } }
            TokenColor(tr("Color", "اللون"), c.color) { v -> edit("color") { it.copy(content = (it.content as LayerContent.Icon).copy(color = v)) } }
        }
        is LayerContent.Shape -> SectionCard {
            Dropdown(tr("Shape", "الشكل"), listOf("rect" to tr("Rectangle", "مستطيل"), "roundedRect" to tr("Rounded rectangle", "مستطيل بحواف دائرية"), "circle" to tr("Circle", "دائرة"), "capsule" to tr("Capsule", "كبسولة")), c.kind) { v ->
                edit("kind") { it.copy(content = (it.content as LayerContent.Shape).copy(kind = v)) }
            }
            TokenColor(tr("Fill", "التعبئة"), c.fill ?: "@accent") { v -> edit("fill") { it.copy(content = (it.content as LayerContent.Shape).copy(fill = v)) } }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(tr("Frosted glass", "زجاج مصنفر"), modifier = Modifier.weight(1f))
                Switch(checked = c.glass == true, onCheckedChange = { on ->
                    edit("glass") { l ->
                        val s = l.content as LayerContent.Shape
                        val opaque = s.fill?.let { !it.startsWith("#") || it.length == 7 } ?: true
                        l.copy(content = s.copy(glass = if (on) true else null, fill = if (on && opaque) "#FFFFFF2E" else s.fill))
                    }
                })
            }
        }
        is LayerContent.Stack -> SectionCard {
            Dropdown(tr("Direction", "الاتجاه"), listOf("vertical" to tr("Column", "عمود"), "horizontal" to tr("Row", "صف"), "grid" to tr("Grid", "شبكة")), c.axis) { v ->
                edit("axis") { l -> val s = l.content as LayerContent.Stack; l.copy(content = s.copy(axis = v, columns = if (v == "grid") s.columns ?: 2 else null, children = if (v == "grid") s.children.filter { it.content !is LayerContent.Spacer } else s.children)) }
            }
            NumberField(tr("Spacing", "المسافة بين العناصر"), c.spacing ?: 4.0) { v -> edit("spacing") { it.copy(content = (it.content as LayerContent.Stack).copy(spacing = v)) } }
            NumberField(tr("Padding", "الهامش الداخلي"), c.padding ?: 0.0) { v -> edit("padding") { it.copy(content = (it.content as LayerContent.Stack).copy(padding = v)) } }
            val aligns = listOf("start" to tr("Start", "البداية"), "center" to tr("Center", "الوسط"), "end" to tr("End", "النهاية"))
            Dropdown(tr("Align items", "محاذاة العناصر"), aligns, c.alignItems ?: if (c.axis == "horizontal") "center" else "start") { v -> edit("alignItems") { it.copy(content = (it.content as LayerContent.Stack).copy(alignItems = v)) } }
            Dropdown(tr("Position in frame", "الموضع داخل الإطار"), aligns, c.justify ?: "start") { v -> edit("justify") { it.copy(content = (it.content as LayerContent.Stack).copy(justify = v)) } }
            if (c.axis == "grid") NumberField(tr("Columns", "الأعمدة"), (c.columns ?: 2).toDouble()) { v -> edit("columns") { it.copy(content = (it.content as LayerContent.Stack).copy(columns = v.toInt().coerceIn(1, 8))) } }
            TextButton(onClick = { onOpenItems(path) }) { Text(tr("Items", "العناصر") + " (${c.children.size})") }
            if (top) TextButton(onClick = { state.setLayers { LayerEditing.ungroup(path[0], it) }; onGone() }) { Text(tr("Ungroup", "فك المجموعة")) }
        }
        else -> Unit
    }
    WiringCards(state, path)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 12.dp)) {
        OutlinedButton(onClick = { state.setLayers { LayerEditing.duplicate(path, it) } }) { Text(tr("Duplicate", "تكرار")) }
        OutlinedButton(onClick = { state.setLayers { LayerEditing.remove(path, it) }; onGone() }) { Text(tr("Delete", "حذف"), color = MaterialTheme.colorScheme.error) }
    }
}

@Composable
private fun TextSettings(text: LayerContent.Text, edit: (String, (LayerContent.Text) -> LayerContent.Text) -> Unit) {
    SectionCard {
        fun setValue(en: String? = null, ar: String? = null) = edit("value") { t -> t.copy(value = LText.Localized(en ?: t.value.resolved("en"), ar ?: t.value.resolved("ar"))) }
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
            OutlinedTextField(text.value.resolved("ar"), { setValue(ar = it) }, label = { Text(tr("Arabic", "العربية")) }, modifier = Modifier.fillMaxWidth())
        }
        CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
            OutlinedTextField(text.value.resolved("en"), { setValue(en = it) }, label = { Text("English") }, modifier = Modifier.fillMaxWidth())
        }
        Footnote(tr("Keep {{…}} parts: they show live data such as the time or the weather.", "أبقِ الأجزاء {{…}}: فهي تعرض بيانات حية مثل الوقت أو الطقس."))
        val families = listOf("system" to tr("System", "النظام"), "system-rounded" to tr("Rounded", "دائري"), "system-serif" to tr("Serif", "مذيّل"), "system-mono" to tr("Monospace", "ثابت العرض"),
            "dot" to tr("Dot matrix", "نقطي"), "arabic" to tr("Arabic", "عربي"), "hand" to tr("Handwritten", "بخط اليد"), "serif-display" to tr("Display serif", "مذيّل عريض"), "condensed" to tr("Condensed", "مضغوط"))
        Dropdown(tr("Font", "الخط"), families, text.font.family) { v -> edit("family") { it.copy(font = it.font.copy(family = v)) } }
        NumberField(tr("Font size", "حجم الخط"), text.font.size) { v -> edit("size") { it.copy(font = it.font.copy(size = v.coerceIn(SpecValidator.FONT_SIZES))) } }
        val weights = listOf("ultraLight", "thin", "light", "regular", "medium", "semibold", "bold", "heavy", "black")
        Dropdown(tr("Weight", "السُمك"), weights.map { it to it }, text.font.weight ?: "regular") { v -> edit("weight") { it.copy(font = FontSpec(it.font.family, it.font.size, v)) } }
        Text(tr("Alignment", "المحاذاة"))
        Segmented(listOf("leading" to tr("Start", "البداية"), "center" to tr("Center", "الوسط"), "trailing" to tr("End", "النهاية")), text.align ?: "leading", { v -> edit("align") { it.copy(align = v) } })
        NumberField(tr("Lines", "عدد الأسطر"), (text.maxLines ?: 1).toDouble()) { v -> edit("lines") { it.copy(maxLines = v.toInt().coerceIn(1, 6)) } }
        TokenColor(tr("Color", "اللون"), text.color) { v -> edit("color") { it.copy(color = v) } }
    }
}

/** A theme color (so the design's colors keep reaching it) or a custom hex. */
@Composable
private fun TokenColor(label: String, value: String, onChange: (String) -> Unit) {
    val tokens = listOf("@fg" to tr("Text", "النص"), "@muted" to tr("Secondary text", "النص الثانوي"), "@accent" to tr("Accent", "اللون المميز"), "@bg" to tr("Background", "الخلفية"), "@onAccent" to tr("On accent", "فوق اللون المميز"))
    val custom = tokens.none { it.first == value }
    Dropdown(label, tokens + ("custom" to tr("Custom", "مخصص")), if (custom) "custom" else value) { v ->
        onChange(if (v == "custom") SpecTokens.hex(value.drop(1), com.khaled.widgetstudio.spec.Theme.DARK) ?: "#FFFFFF" else v)
    }
    if (custom) ColorChooser(tr("Custom color", "لون مخصص"), value, onChange)
}

/** A number in canvas units, with − and + buttons. */
@Composable
private fun NumberField(label: String, value: Double, modifier: Modifier = Modifier, onChange: (Double) -> Unit) {
    var text by remember(value) { mutableStateOf(if (value == Math.rint(value)) value.toLong().toString() else value.toString()) }
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        OutlinedTextField(text, { t -> text = t; t.toDoubleOrNull()?.let(onChange) }, label = { Text(label, maxLines = 1) }, singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal), modifier = Modifier.weight(1f))
        Column {
            TextButton(onClick = { onChange(value + 1) }, modifier = Modifier.width(44.dp)) { Text("+") }
            TextButton(onClick = { onChange(value - 1) }, modifier = Modifier.width(44.dp)) { Text("−") }
        }
    }
}

/**
 * The States panel (ADR-028): preview each state with a picker or a level slider, choose a built-in
 * set and its colors, and edit each variant. Editing a variant writes the set's variants into the
 * design, so the catalog's own set stays as it is.
 */
@Composable
private fun StatesSettings(state: EditorState, states: LayerContent.States, change: ((LayerContent.States) -> LayerContent.States) -> Unit) {
    val language = appLanguage()
    var picked by remember { mutableStateOf("") }
    var level by remember { mutableStateOf(0.5f) }
    val resolver = remember(state.design) { com.khaled.widgetstudio.spec.BindingResolver(state.design.spec, com.khaled.widgetstudio.spec.RenderContext(now = java.time.Instant.now())) }
    val variants = states.expanded
    fun title(variant: StateVariant) = variant.title?.resolved(language) ?: variant.id
    fun clearPreview() {
        picked = ""
        state.previewForced = emptyMap()
        state.previewOverrides = emptyMap()
    }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { state.previewForced = emptyMap(); state.previewOverrides = emptyMap() } }
    val followed = listOfNotNull(states.value?.let(Bindings::soleBinding)) + (states.set?.let { Capabilities.stateSet(it)?.needs } ?: emptyList())
    val levelBinding = followed.firstOrNull { Capabilities.binding(it)?.isShare == true }
    SectionTitle(tr("Preview a state", "معاينة حالة"))
    SectionCard {
        Dropdown(tr("Show", "اعرض"), listOf("" to tr("The real state now", "الحالة الحقيقية الآن")) + variants.map { it.id to title(it) }, picked) { id ->
            picked = id
            val variant = variants.firstOrNull { it.id == id }
            state.previewForced = if (variant == null) emptyMap() else mapOf(states.key to id)
            state.previewOverrides = variant?.let(resolver::overrides) ?: emptyMap()
        }
        if (levelBinding != null) {
            Text(Math.round(level * 100).toString() + "%", style = MaterialTheme.typography.bodySmall)
            androidx.compose.material3.Slider(value = level, onValueChange = { value ->
                level = value
                picked = ""
                state.previewForced = emptyMap()
                state.previewOverrides = mapOf(levelBinding to value.toString())
            })
        }
    }
    SectionTitle(tr("Look", "الشكل"))
    SectionCard {
        Dropdown(tr("Set", "المجموعة"), (if (states.set == null) listOf("" to tr("Custom", "مخصصة")) else emptyList()) + Capabilities.stateSets.map { it.id to it.title.resolved(language) }, states.set ?: "") { id ->
            if (id.isNotEmpty()) {
                change { it.copy(set = id, variants = null, box = null, value = Capabilities.stateSet(id)?.value) }
                clearPreview()
            }
        }
        TokenColor(tr("Color", "اللون"), states.color) { value -> change { it.copy(color = value) } }
        TokenColor(tr("Accent", "لون التمييز"), states.accent) { value -> change { it.copy(accent = value) } }
    }
    SectionTitle(tr("States", "الحالات"))
    SectionCard {
        /** The first edit turns a built-in set into variants of this design. */
        fun editVariant(id: String, edit: (StateVariant) -> StateVariant) = change { current ->
            val box = current.box ?: current.set?.let { Capabilities.stateSet(it)?.box }
            current.copy(set = null, box = box, variants = current.expanded.map { if (it.id == id) edit(it) else it })
        }
        for (variant in variants) {
            Text(title(variant), style = MaterialTheme.typography.titleSmall)
            OutlinedTextField(variant.condition ?: "", { text -> editVariant(variant.id) { it.copy(condition = text.ifEmpty { null }) } }, label = { Text(tr("Condition", "الشرط")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            if (variant.condition != null && SpecExpression.parse(variant.condition) == null) Footnote(tr("This condition isn't valid.", "هذا الشرط غير صحيح."))
            variant.layers.firstOrNull { it.content is LayerContent.Icon }?.let { layer ->
                val icon = layer.content as LayerContent.Icon
                OutlinedTextField(icon.symbol, { symbol ->
                    editVariant(variant.id) { v -> v.copy(layers = v.layers.map { if (it === layer) it.copy(content = icon.copy(symbol = symbol)) else it }) }
                }, label = { Text(tr("Symbol", "الرمز")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            }
            if (variants.size > 1) TextButton(onClick = { change { current -> current.copy(set = null, box = current.box ?: current.set?.let { Capabilities.stateSet(it)?.box }, variants = current.expanded.filter { it.id != variant.id }) } }) {
                Text(tr("Remove this state", "احذف هذه الحالة"), color = MaterialTheme.colorScheme.error)
            }
        }
        Footnote(tr("The first state whose condition holds is shown. Leave a condition empty for the default. Editing a state makes a copy for this design.", "يُعرض أول شكل يتحقق شرطه. اترك الشرط فارغًا ليكون الافتراضي. تعديل أي حالة ينشئ نسخة خاصة بهذا التصميم."))
    }
}

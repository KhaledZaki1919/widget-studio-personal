package com.khaled.widgetstudio.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimeInput
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.khaled.widgetstudio.design.ClockFormat
import com.khaled.widgetstudio.design.DesignEditing
import com.khaled.widgetstudio.design.DesignStore
import com.khaled.widgetstudio.design.IconWhitelist
import com.khaled.widgetstudio.design.ImageProcessing
import com.khaled.widgetstudio.design.LayoutRepair
import com.khaled.widgetstudio.design.SavedDesign
import com.khaled.widgetstudio.spec.Background
import com.khaled.widgetstudio.spec.FieldSpec
import com.khaled.widgetstudio.spec.LText
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.SpecTokens
import com.khaled.widgetstudio.spec.Theme
import com.khaled.widgetstudio.widget.WidgetEnvironment
import com.khaled.widgetstudio.widget.Widgets
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/** The design being edited, with undo and redo (consecutive edits of one control count as one step). */
class EditorState(initial: SavedDesign, val isNew: Boolean, photo: Bitmap?) {
    var design by mutableStateOf(initial)
        private set
    var newPhoto by mutableStateOf(photo)
    private val undoStack = ArrayDeque<SavedDesign>()
    private val redoStack = ArrayDeque<SavedDesign>()
    private var lastKey: String? = null
    /** The States panel's preview: which state to show, and with what values (ADR-028). */
    var previewForced by mutableStateOf<Map<String, String>>(emptyMap())
    var previewOverrides by mutableStateOf<Map<String, String>>(emptyMap())
    var canUndo by mutableStateOf(false)
        private set
    var canRedo by mutableStateOf(false)
        private set

    /** Applies [change]; edits with the same [key] in a row (typing) merge into one undo step. */
    fun update(key: String? = null, change: (SavedDesign) -> SavedDesign) {
        val next = change(design)
        if (next == design) return
        if (key == null || key != lastKey) undoStack.addLast(design)
        if (undoStack.size > 100) undoStack.removeFirst()
        redoStack.clear()
        lastKey = key
        design = next
        refresh()
    }

    fun undo() {
        val previous = undoStack.removeLastOrNull() ?: return
        redoStack.addLast(design)
        design = previous
        lastKey = null
        refresh()
    }

    fun redo() {
        val next = redoStack.removeLastOrNull() ?: return
        undoStack.addLast(design)
        design = next
        lastKey = null
        refresh()
    }

    private fun refresh() {
        canUndo = undoStack.isNotEmpty()
        canRedo = redoStack.isNotEmpty()
    }

    val issues get() = DesignEditing.issues(design)
}

/** Editor screens: the main form, the layer list (path of the stack shown) and a layer's detail. */
private sealed class EditorScreen {
    data object Main : EditorScreen()
    data class Layers(val parent: List<Int>) : EditorScreen()
    data class Layer(val path: List<Int>) : EditorScreen()
}

/**
 * The editor (brief §7.3, M3 + M6.1): a live preview (tap a layer to edit it), name, photo,
 * appearance, every field the template defines and the layer editor, with undo/redo. Save
 * validates the design, stores it and updates every placed widget at once.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditorScreen(state: EditorState, onClose: () -> Unit, onSaved: () -> Unit, layout: LayoutRepair? = null, onRegenerate: (() -> Unit)? = null) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var screen by remember { mutableStateOf<EditorScreen>(EditorScreen.Main) }
    var language by remember { mutableStateOf(WidgetEnvironment.language(context)) }
    var confirmDiscard by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    if (confirmDelete) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text(tr("Delete this design?", "هل تحذف هذا التصميم؟")) },
            text = { Text(tr("Widgets showing it will ask you to choose another design.", "الودجات التي تعرضه ستطلب منك اختيار تصميم آخر.")) },
            confirmButton = {
                TextButton(onClick = {
                    DesignStore.get(context).delete(state.design.id)
                    scope.launch { Widgets.updateAll(context) }
                    onClose()
                }) { Text(tr("Delete", "حذف"), color = androidx.compose.material3.MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text(tr("Cancel", "إلغاء")) } },
        )
    }
    BackHandler {
        when (val s = screen) {
            is EditorScreen.Main -> confirmDiscard = true
            is EditorScreen.Layers -> screen = if (s.parent.isEmpty()) EditorScreen.Main else EditorScreen.Layer(s.parent)
            is EditorScreen.Layer -> screen = EditorScreen.Layers(s.path.dropLast(1))
        }
    }
    val design = state.design
    val issues = state.issues
    Scaffold(topBar = {
        TopAppBar(
            title = { Text(if (state.isNew) tr("New design", "تصميم جديد") else tr("Edit design", "تعديل التصميم"), maxLines = 1) },
            navigationIcon = { TextButton(onClick = { if (screen is EditorScreen.Main) confirmDiscard = true else screen = EditorScreen.Main }) { Text(if (screen is EditorScreen.Main) tr("Cancel", "إلغاء") else tr("Back", "رجوع")) } },
            actions = {
                TextButton(onClick = state::undo, enabled = state.canUndo) { Text("↶", fontSize = 20.sp) }
                TextButton(onClick = state::redo, enabled = state.canRedo) { Text("↷", fontSize = 20.sp) }
                TextButton(enabled = issues.isEmpty(), onClick = {
                    scope.launch {
                        withContext(Dispatchers.IO) { DesignStore.get(context).save(state.design, state.newPhoto) }
                        Widgets.updateAll(context)
                        onSaved()
                    }
                }) { Text(tr("Save", "حفظ")) }
            },
        )
    }) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp)) {
            Segmented(listOf("ar" to "العربية", "en" to "English"), language, { language = it })
            Spacer(Modifier.height(10.dp))
            EditorPreview(state, language) { path -> screen = EditorScreen.Layer(path) }
            Footnote(tr("Real-size preview with your real data. Tap a part to edit it.", "معاينة بالحجم الحقيقي ببياناتك. اضغط أي جزء لتعديله."))
            // ADR-029: the render and a fix request for the AI that wrote the JSON.
            TextButton(onClick = { sharePreview(context, state) }) { Text(tr("Copy preview + fix request", "نسخ المعاينة وطلب التصحيح")) }
            when (val s = screen) {
                is EditorScreen.Main -> {
                    InteractiveCard(state) { screen = EditorScreen.Layer(it) }
                    MainForm(state, layout, onRegenerate) { screen = EditorScreen.Layers(emptyList()) }
                    if (!state.isNew) TextButton(onClick = { confirmDelete = true }) { Text(tr("Delete design", "حذف التصميم"), color = androidx.compose.material3.MaterialTheme.colorScheme.error) }
                }
                is EditorScreen.Layers -> LayersList(state, s.parent, onOpen = { screen = EditorScreen.Layer(it) })
                is EditorScreen.Layer -> LayerDetail(state, s.path, onOpenItems = { screen = EditorScreen.Layers(it) }, onGone = { screen = EditorScreen.Layers(s.path.dropLast(1)) })
            }
            if (issues.isNotEmpty()) {
                SectionTitle(tr("Fix these before saving", "يجب تصحيح ما يلي قبل الحفظ"))
                SectionCard { issues.take(8).forEach { Text("⚠ $it", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) } }
            }
            Spacer(Modifier.height(32.dp))
        }
    }
    if (confirmDiscard) {
        AlertDialog(
            onDismissRequest = { confirmDiscard = false },
            title = { Text(tr("Discard changes?", "تجاهل التغييرات؟")) },
            confirmButton = { TextButton(onClick = { confirmDiscard = false; onClose() }) { Text(tr("Discard", "تجاهل")) } },
            dismissButton = { TextButton(onClick = { confirmDiscard = false }) { Text(tr("Keep editing", "متابعة التعديل")) } },
        )
    }
}

/** The design at real proportions; a tap selects the topmost layer under the finger. */
@Composable
private fun EditorPreview(state: EditorState, language: String, onPick: (List<Int>) -> Unit) {
    val context = LocalContext.current
    val design = state.design
    val photo = state.newPhoto ?: remember(design.imageFile) { DesignStore.get(context).image(design) }
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        Box(Modifier.widthIn(max = (design.spec.family.width * 1.15).dp).pointerInput(design, language) {
            detectTapGestures { offset ->
                val x = offset.x / size.width * design.spec.family.width
                val y = offset.y / size.height * design.spec.family.height
                val layers = design.spec.layers
                val index = layers.indices.reversed().firstOrNull { i ->
                    val layer = layers[i]
                    if (layer.content is LayerContent.Button) return@firstOrNull false
                    val f = if (language == "ar" && layer.mirror == true) layer.frame.mirrored(design.spec.family.width) else layer.frame
                    x >= f.x && x <= f.x + f.w && y >= f.y && y <= f.y + f.h
                }
                if (index != null) onPick(listOf(index))
            }
        }) {
            DesignPreview(design, language, photo, Modifier.fillMaxWidth(), state.previewForced, state.previewOverrides)
        }
    }
}

@Composable
private fun MainForm(state: EditorState, layout: LayoutRepair?, onRegenerate: (() -> Unit)?, onLayers: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val design = state.design
    when (layout) {
        is LayoutRepair.Fixed -> { Spacer(Modifier.height(10.dp)); SectionCard { Text(tr("Some texts the AI placed on top of each other were lined up automatically.", "رُتّبت تلقائيًا بعض النصوص التي وضعها الذكاء الاصطناعي فوق بعضها.")) } }
        is LayoutRepair.NeedsEditing -> {
            Spacer(Modifier.height(10.dp))
            SectionCard {
                Text(tr("Some texts still overlap and couldn't be arranged automatically. Fix them in Layers before saving, or regenerate.", "ما زالت بعض النصوص متداخلة ولم يمكن ترتيبها تلقائيًا. أصلحها في «الطبقات» قبل الحفظ، أو صمّم مرة أخرى."), color = MaterialTheme.colorScheme.error)
                TextButton(onClick = onLayers) { Text(tr("Fix in Layers", "أصلح في الطبقات")) }
            }
        }
        else -> Unit
    }
    if (onRegenerate != null) {
        Spacer(Modifier.height(10.dp))
        OutlinedButton(onClick = onRegenerate, modifier = Modifier.fillMaxWidth()) { Text(tr("Regenerate", "صمّم مرة أخرى")) }
        Footnote(tr("A new design from the same image. Your edits here won't be kept.", "تصميم جديد من الصورة نفسها. لن تُحفظ تعديلاتك هنا."))
    }
    SectionTitle(tr("Name", "الاسم"))
    OutlinedTextField(design.name, { value -> state.update("name") { it.copy(name = value.take(SavedDesign.MAX_NAME_LENGTH)) } }, singleLine = true, modifier = Modifier.fillMaxWidth())

    design.imageLayer?.let { (frame, layer) ->
        val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
            if (uri != null) scope.launch {
                val processed = withContext(Dispatchers.Default) {
                    context.contentResolver.openInputStream(uri)?.use { stream ->
                        BitmapFactory.decodeStream(stream, null, BitmapFactory.Options().apply { inSampleSize = 1 })
                    }?.let { full -> ImageProcessing.prepare(downscale(full, 2048), frame, layer) }
                }
                if (processed != null) state.newPhoto = processed
            }
        }
        SectionTitle(tr("Photo", "الصورة"))
        SectionCard {
            Button(onClick = { picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) {
                Text(if (design.imageFile == null && state.newPhoto == null) tr("Pick a photo", "اختر صورة") else tr("Change photo", "غيّر الصورة"))
            }
            Footnote(if (layer.filter == "halftone") tr("The photo becomes dots for this design.", "تتحول الصورة إلى نقاط في هذا التصميم.") else tr("The photo is resized to the widget and stays on your phone.", "يُصغَّر حجم الصورة لتناسب الويدجت وتبقى على هاتفك."))
        }
    }

    SectionTitle(tr("Appearance", "المظهر"))
    SectionCard {
        Text(tr("Mode", "الوضع"))
        Segmented(listOf(null to tr("Template", "حسب القالب"), Theme.LIGHT to tr("Light", "فاتح"), Theme.DARK to tr("Dark", "داكن")), design.theme, { value -> state.update { it.copy(theme = value) } })
        Dropdown(tr("Clock", "الساعة"), listOf(null to tr("As in Settings", "كما في الإعدادات"), ClockFormat.DEVICE to tr("Device", "حسب الجهاز"), ClockFormat.H12 to tr("12-hour", "12 ساعة"), ClockFormat.H24 to tr("24-hour", "24 ساعة")), design.clockFormat) { value -> state.update { it.copy(clockFormat = value) } }
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
            Text(tr("Glass background", "خلفية زجاجية"), modifier = Modifier.weight(1f))
            Switch(checked = design.spec.background.type == "glass", onCheckedChange = { on ->
                state.update { d ->
                    val current = d.spec.background
                    val background = if (on) Background("glass", null, null, null, current.outerColor, current.cardShape) else Background("solid", "@bg", null, null, current.outerColor, current.cardShape)
                    d.copy(spec = d.spec.copy(background = background))
                }
            })
        }
        val tokens = listOf("accent" to tr("Accent", "اللون المميز"), "bg" to tr("Background", "الخلفية"), "fg" to tr("Text", "النص"), "muted" to tr("Secondary text", "النص الثانوي")) +
            if (design.spec.background.outerColor == "@outer") listOf("outer" to tr("Outside the card", "حول البطاقة")) else emptyList()
        tokens.forEach { (token, label) ->
            ColorChooser(label, design.colors[token] ?: SpecTokens.hex(token, design.effectiveTheme) ?: "#000000",
                onChange = { hex -> state.update("color.$token") { it.copy(colors = it.colors + (token to hex)) } },
                onReset = if (design.colors.containsKey(token)) ({ state.update { it.copy(colors = it.colors - token) } }) else null)
        }
    }

    val fields = design.spec.fields.filter { it.type != "image" }
    if (fields.isNotEmpty()) {
        SectionTitle(tr("Fields", "الحقول"))
        SectionCard { fields.forEach { FieldEditor(state, it) } }
    }

    SectionTitle(tr("Layers", "الطبقات"))
    SectionCard {
        val overlaps = com.khaled.widgetstudio.design.SpecLayout.overlapping(design.spec.layers)
        TextButton(onClick = onLayers) { Text(tr("Edit layers", "عدّل الطبقات") + " (${design.spec.layers.size})" + if (overlaps.isNotEmpty()) "  ⚠" else "") }
        Footnote(tr("Move, resize and restyle each part of the widget.", "حرّك كل جزء من الويدجت وغيّر حجمه وشكله."))
    }
}

/** At most [maxSide] px on the longest side. */
fun downscale(image: Bitmap, maxSide: Int): Bitmap {
    val longest = maxOf(image.width, image.height)
    if (longest <= maxSide) return image
    val ratio = maxSide.toFloat() / longest
    return Bitmap.createScaledBitmap(image, (image.width * ratio).toInt().coerceAtLeast(1), (image.height * ratio).toInt().coerceAtLeast(1), true)
}

/** The control for one template field, by type (brief §4.3). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun FieldEditor(state: EditorState, field: FieldSpec) {
    val language = appLanguage()
    val title = field.label.resolved(language)
    val current = state.design.fieldValues[field.key] ?: field.default
    fun setPlain(value: String) = state.update("field.${field.key}") { it.copy(fieldValues = it.fieldValues + (field.key to LText.Plain(value))) }
    Column(Modifier.padding(vertical = 6.dp)) {
        when (field.type) {
            "text", "city" -> {
                Text(title, style = MaterialTheme.typography.labelLarge)
                fun set(en: String? = null, ar: String? = null) = state.update("field.${field.key}") { d ->
                    val c = d.fieldValues[field.key] ?: field.default
                    d.copy(fieldValues = d.fieldValues + (field.key to LText.Localized(en ?: c?.resolved("en") ?: "", ar ?: c?.resolved("ar") ?: "")))
                }
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                    OutlinedTextField(current?.resolved("ar") ?: "", { set(ar = it) }, label = { Text(tr("Arabic", "العربية")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                }
                CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Ltr) {
                    OutlinedTextField(current?.resolved("en") ?: "", { set(en = it) }, label = { Text("English") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                }
            }
            "number", "url", "shortcut" -> OutlinedTextField(current?.resolved("en") ?: "", ::setPlain, label = { Text(title) }, singleLine = true, modifier = Modifier.fillMaxWidth(),
                placeholder = { Text(if (field.type == "url") "https://" else if (field.type == "number") "0" else tr("Tile name, e.g. Torch", "اسم الزر، مثل الكشاف")) })
            "color" -> ColorChooser(title, current?.resolved("en") ?: "#FFFFFF", ::setPlain)
            "date" -> DateField(title, current?.resolved("en") ?: "", hasTime = field.default?.resolved("en")?.contains('T') == true, onChange = ::setPlain)
            "timezone" -> {
                var query by remember { mutableStateOf("") }
                var open by remember { mutableStateOf(false) }
                TextButton(onClick = { open = true }) { Text("$title: " + (current?.resolved("en")?.ifEmpty { null } ?: tr("Device", "حسب الجهاز"))) }
                if (open) AlertDialog(onDismissRequest = { open = false }, confirmButton = { TextButton(onClick = { open = false }) { Text(tr("Done", "تم")) } }, title = { Text(title) }, text = {
                    Column {
                        OutlinedTextField(query, { query = it }, label = { Text(tr("Search", "بحث")) }, singleLine = true)
                        Column(Modifier.height(320.dp).verticalScroll(rememberScrollState())) {
                            ZoneId.getAvailableZoneIds().sorted().filter { it.contains(query, true) }.take(80).forEach { zone ->
                                TextButton(onClick = { setPlain(zone); open = false }) { Text(zone) }
                            }
                        }
                    }
                })
            }
            "icon" -> {
                var open by remember { mutableStateOf(false) }
                val symbol = current?.resolved("en") ?: ""
                TextButton(onClick = { open = true }) { Text("$title: ", maxLines = 1); SymbolText(symbol) }
                if (open) AlertDialog(onDismissRequest = { open = false }, confirmButton = { TextButton(onClick = { open = false }) { Text(tr("Done", "تم")) } }, title = { Text(title) }, text = {
                    Column(Modifier.height(360.dp).verticalScroll(rememberScrollState())) {
                        IconWhitelist.names.keys.sorted().chunked(5).forEach { row ->
                            Row(horizontalArrangement = Arrangement.SpaceEvenly, modifier = Modifier.fillMaxWidth()) {
                                row.forEach { name -> TextButton(onClick = { setPlain(name); open = false }) { SymbolText(name) } }
                            }
                        }
                    }
                })
            }
            else -> Unit
        }
    }
}

/** A whitelisted symbol drawn with the Material Symbols font (like the widget). */
@Composable
fun SymbolText(symbol: String, size: Int = 24) {
    val context = LocalContext.current
    val family = remember { FontFamily(androidx.compose.ui.text.font.Font("fonts/MaterialSymbolsRounded-Filled.ttf", context.assets)) }
    Text(IconWhitelist.names[symbol] ?: "help", fontFamily = family, fontSize = size.sp, textAlign = TextAlign.Center)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DateField(title: String, value: String, hasTime: Boolean, onChange: (String) -> Unit) {
    val zone = ZoneId.systemDefault()
    val parsed = runCatching { LocalDateTime.parse(value.removeSuffix("Z").take(19)) }.getOrNull()
        ?: runCatching { LocalDate.parse(value.take(10)).atStartOfDay() }.getOrNull() ?: LocalDateTime.now()
    var pickDate by remember { mutableStateOf(false) }
    var pickTime by remember { mutableStateOf(false) }
    fun write(date: LocalDate, time: LocalTime) = onChange(
        if (hasTime) date.atTime(time).atZone(zone).toInstant().toString() else date.format(DateTimeFormatter.ISO_LOCAL_DATE),
    )
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, modifier = Modifier.weight(1f))
        TextButton(onClick = { pickDate = true }) { Text(parsed.toLocalDate().toString()) }
        if (hasTime) TextButton(onClick = { pickTime = true }) { Text(parsed.toLocalTime().toString().take(5)) }
    }
    if (pickDate) {
        val picker = rememberDatePickerState(initialSelectedDateMillis = parsed.toLocalDate().atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(onDismissRequest = { pickDate = false }, confirmButton = {
            TextButton(onClick = {
                picker.selectedDateMillis?.let { write(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate(), parsed.toLocalTime()) }
                pickDate = false
            }) { Text(tr("Done", "تم")) }
        }) { DatePicker(picker) }
    }
    if (pickTime) {
        val picker = rememberTimePickerState(parsed.hour, parsed.minute)
        AlertDialog(onDismissRequest = { pickTime = false }, text = { TimeInput(picker) }, confirmButton = {
            TextButton(onClick = { write(parsed.toLocalDate(), LocalTime.of(picker.hour, picker.minute)); pickTime = false }) { Text(tr("Done", "تم")) }
        })
    }
}

/** "Copy preview + fix request" (ADR-029): the design drawn with sample data, shared as a PNG with the request text (also copied). */
private fun sharePreview(context: android.content.Context, state: EditorState) {
    val design = state.design
    val spec = design.spec
    val now = java.time.Instant.now()
    val zone = java.time.ZoneId.systemDefault()
    val renderContext = com.khaled.widgetstudio.spec.RenderContext(now = now, language = "en", zone = zone,
        data = com.khaled.widgetstudio.spec.DataSnapshot.sample(now, zone), tokenOverrides = design.colors)
    val bitmap = com.khaled.widgetstudio.widget.WidgetEnvironment.renderer(context).render(spec, renderContext, (spec.family.width * 3).toInt(), (spec.family.height * 3).toInt()).bitmap
    val notes = com.khaled.widgetstudio.design.DesignRules.check(spec).findings.map { it.message.resolved("en") } + state.issues
    val text = com.khaled.widgetstudio.ai.ExternalAI.previewRequest(listOf(design.name), notes)
    context.getSystemService(android.content.ClipboardManager::class.java)?.setPrimaryClip(android.content.ClipData.newPlainText("Widget Studio", text))
    val folder = java.io.File(context.cacheDir, "shared").apply { mkdirs() }
    val file = java.io.File(folder, "widget-preview.png")
    file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
    val uri = androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    val send = android.content.Intent(android.content.Intent.ACTION_SEND).setType("image/png").putExtra(android.content.Intent.EXTRA_STREAM, uri)
        .putExtra(android.content.Intent.EXTRA_TEXT, text).addFlags(android.content.Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(android.content.Intent.createChooser(send, null).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK))
}

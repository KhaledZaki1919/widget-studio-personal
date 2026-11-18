package com.khaled.widgetstudio.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import com.khaled.widgetstudio.ai.AIError
import com.khaled.widgetstudio.ai.CardShape
import com.khaled.widgetstudio.ai.DetectedWidget
import com.khaled.widgetstudio.ai.ExternalAI
import com.khaled.widgetstudio.ai.GeminiSettings
import com.khaled.widgetstudio.ai.GenerationMode
import com.khaled.widgetstudio.ai.GenerationOptions
import com.khaled.widgetstudio.ai.PreparedImage
import com.khaled.widgetstudio.ai.WidgetDetector
import com.khaled.widgetstudio.ai.WidgetGenerator
import com.khaled.widgetstudio.ai.WidgetPrompt
import com.khaled.widgetstudio.design.DesignStore
import com.khaled.widgetstudio.design.ImageProcessing
import com.khaled.widgetstudio.design.LayoutRepair
import com.khaled.widgetstudio.design.SavedDesign
import com.khaled.widgetstudio.widget.WidgetEnvironment
import com.khaled.widgetstudio.widget.Widgets
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** Text shared to the app (a chat's reply, a .json file), waiting for the import screen. */
object PendingImport {
    @Volatile var text: String? = null
    /** Files shared or opened in the app (ADR-027): they go to bulk import. */
    @Volatile var bulk: BulkRequest? = null
}

private sealed class CreateStep {
    data object Setup : CreateStep()
    data object Crop : CreateStep()
    data object Generating : CreateStep()
    data class Failed(val error: AIError) : CreateStep()
    data class Batch(val total: Int, val current: Int, val created: Int, val failed: Int, val finished: Boolean) : CreateStep()
    data object External : CreateStep()
}

/** Loads a picked image upright, longest side at most [maxSide]. */
fun loadImage(context: Context, uri: Uri, maxSide: Int = 2048): Bitmap? = runCatching {
    val bitmap = if (Build.VERSION.SDK_INT >= 28) ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
        val longest = maxOf(info.size.width, info.size.height)
        if (longest > maxSide) decoder.setTargetSampleSize(longest / maxSide)
    } else @Suppress("DEPRECATION") MediaStore.Images.Media.getBitmap(context.contentResolver, uri)
    downscale(bitmap.copy(Bitmap.Config.ARGB_8888, false), maxSide)
}.getOrNull()

/**
 * Create from image (brief §5, ADR-018/024), Gemini only: pick an image → crop to the widget →
 * mode, size, wishes → consent once → generating (Cancel) → the editor (Regenerate). Several
 * widgets: Create all. "Use another AI" copies instructions and imports the JSON reply.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CreateScreen(onClose: () -> Unit, onResult: (SavedDesign, Bitmap?, LayoutRepair, () -> Unit) -> Unit, onCreatedAll: () -> Unit, onBulk: (BulkRequest) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val gemini = remember { GeminiSettings(context) }
    val prompt = remember { WidgetPrompt(context.assets) }
    val language = appLanguage()
    var step by remember { mutableStateOf<CreateStep>(if (PendingImport.text != null) CreateStep.External else CreateStep.Setup) }
    var picked by remember { mutableStateOf<Bitmap?>(null) }
    var detected by remember { mutableStateOf<List<DetectedWidget>>(emptyList()) }
    var crop by remember { mutableStateOf<RectF?>(null) }
    var cardShape by remember { mutableStateOf<CardShape?>(null) }
    var options by remember { mutableStateOf(GenerationOptions()) }
    var askConsent by remember { mutableStateOf<(() -> Unit)?>(null) }
    var job by remember { mutableStateOf<Job?>(null) }
    var cropForExternal by remember { mutableStateOf(false) }

    val cropped: Bitmap? = picked?.let { image -> crop?.let { WidgetDetector.crop(image, it) } }

    val pick = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        if (uri != null) scope.launch {
            val image = withContext(Dispatchers.Default) { loadImage(context, uri) } ?: return@launch
            picked = image
            crop = null
            cardShape = null
            detected = withContext(Dispatchers.Default) { WidgetDetector.detect(image) }
            step = CreateStep.Crop
        }
    }

    fun withConsent(action: () -> Unit) {
        if (gemini.consented) action() else askConsent = action
    }

    fun generate() {
        val image = picked ?: return
        val source = cropped ?: image
        job?.cancel()
        step = CreateStep.Generating
        val run = options.copy(detectedCard = cardShape, cropped = crop != null, wallpaperColor = WidgetDetector.wallpaperColor(image, crop))
        job = scope.launch {
            try {
                val generated = WidgetGenerator(prompt, gemini).generate(withContext(Dispatchers.Default) { PreparedImage.from(source) }, run)
                val design = generated.design(language)
                val photo = if (run.mode == GenerationMode.PHOTO) design.imageLayer?.let { (frame, layer) -> ImageProcessing.prepare(image, frame, layer) } else null
                onResult(design, photo, generated.layout) { withConsent(::generate) }
            } catch (error: AIError) {
                step = CreateStep.Failed(error)
            } catch (cancel: CancellationException) {
                step = CreateStep.Setup
            } catch (error: Exception) {
                step = CreateStep.Failed(AIError.Network)
            }
        }
    }

    fun createAll(widgets: List<DetectedWidget>) {
        val image = picked ?: return
        job?.cancel()
        var created = 0
        var failed = 0
        step = CreateStep.Batch(widgets.size, 0, 0, 0, false)
        job = scope.launch {
            for ((index, widget) in widgets.withIndex()) {
                step = CreateStep.Batch(widgets.size, index, created, failed, false)
                val source = WidgetDetector.crop(image, widget.rect) ?: run { failed++; null } ?: continue
                val run = options.copy(mode = GenerationMode.RECREATE, size = if (options.size == "auto") widget.suggestedSize(image.width) else options.size,
                    detectedCard = widget.shape, cropped = true, wallpaperColor = WidgetDetector.wallpaperColor(image, widget.rect))
                try {
                    val generated = WidgetGenerator(prompt, gemini).generate(withContext(Dispatchers.Default) { PreparedImage.from(source) }, run)
                    withContext(Dispatchers.IO) { DesignStore.get(context).save(generated.design(language)) }
                    created++
                } catch (cancel: CancellationException) {
                    break
                } catch (error: Exception) {
                    failed++
                }
            }
            Widgets.updateAll(context)
            step = CreateStep.Batch(widgets.size, widgets.size, created, failed, true)
        }
    }

    BackHandler {
        when (step) {
            CreateStep.Crop, CreateStep.External -> step = CreateStep.Setup
            CreateStep.Generating -> { job?.cancel(); step = CreateStep.Setup }
            else -> onClose()
        }
    }

    Scaffold(topBar = {
        TopAppBar(title = { Text(if (step == CreateStep.External) tr("Use another AI", "ذكاء اصطناعي آخر") else tr("Create from image", "صمّم من صورة")) },
            navigationIcon = { TextButton(onClick = { job?.cancel(); onClose() }) { Text(tr("Cancel", "إلغاء")) } })
    }) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
            when (val s = step) {
                CreateStep.Setup -> {
                    picked?.let { image ->
                        Image((cropped ?: image).asImageBitmap(), null, Modifier.fillMaxWidth().heightIn(max = 240.dp), contentScale = ContentScale.Fit)
                        TextButton(onClick = { cropForExternal = false; step = CreateStep.Crop }) { Text(tr("Adjust crop", "اضبط الاقتصاص")) }
                    }
                    Button(onClick = { pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }, modifier = Modifier.fillMaxWidth()) {
                        Text(if (picked == null) tr("Pick an image", "اختر صورة") else tr("Pick another image", "اختر صورة أخرى"))
                    }
                    Footnote(tr("A widget design, a screenshot or a photo. Only the image you pick is sent, to Google, with your own key.", "تصميم ويدجت أو لقطة شاشة أو صورة. لا يُرسل إلا ما تختاره، إلى Google، بمفتاحك."))
                    SectionTitle(tr("What is it?", "ما هذه الصورة؟"))
                    Segmented(listOf(GenerationMode.RECREATE to tr("Recreate a widget", "أعِد تصميم ويدجت"), GenerationMode.PHOTO to tr("Build around my photo", "صمّم حول صورتي")), options.mode, { options = options.copy(mode = it) })
                    SectionTitle(tr("Size", "الحجم"))
                    Segmented(listOf("auto" to tr("Auto", "تلقائي"), "small" to tr("Small", "صغير"), "medium" to tr("Medium", "متوسط"), "large" to tr("Large", "كبير"), "xlarge" to tr("XL", "كبير جدًا")), options.size, { options = options.copy(size = it) })
                    SectionTitle(tr("Wishes (optional)", "طلبات إضافية (اختياري)"))
                    OutlinedTextField(options.instructions, { options = options.copy(instructions = it.take(GenerationOptions.MAX_INSTRUCTIONS)) }, modifier = Modifier.fillMaxWidth(), minLines = 2,
                        placeholder = { Text(tr("e.g. use a red accent, show the date in Arabic", "مثلًا: استخدم لونًا أحمر، واعرض التاريخ بالعربية")) })
                    Spacer(Modifier.height(16.dp))
                    Button(enabled = picked != null, onClick = {
                        if (!gemini.hasKey()) step = CreateStep.Failed(AIError.NoKey) else withConsent(::generate)
                    }, modifier = Modifier.fillMaxWidth()) { Text(tr("Create widget", "صمّم الويدجت")) }
                    Footnote(tr("Gemini · ", "Gemini · ") + gemini.model)
                    SectionTitle(tr("No key?", "بلا مفتاح؟"))
                    OutlinedButton(onClick = { step = CreateStep.External }, modifier = Modifier.fillMaxWidth()) { Text(tr("Use another AI", "استخدم ذكاءً اصطناعيًا آخر")) }
                    Footnote(tr("Design with ChatGPT, Claude or Gemini on the web, then import the result here.", "صمّم باستخدام ChatGPT أو Claude أو Gemini على الويب، ثم استورد النتيجة هنا."))
                }
                CreateStep.Crop -> picked?.let { image ->
                    CropView(image, detected, allowsAll = !cropForExternal, onDone = { rect, shape, size ->
                        crop = rect
                        cardShape = shape
                        if (size != "auto") options = options.copy(size = size)
                        step = if (cropForExternal) CreateStep.External else CreateStep.Setup
                    }, onAll = { widgets -> withConsent { createAll(widgets) } })
                }
                CreateStep.Generating -> Column(Modifier.fillMaxWidth().padding(top = 80.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator()
                    Text(tr("Designing your widget…", "جارٍ تصميم الويدجت…"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 16.dp))
                    Footnote(tr("This can take up to a minute.", "قد يستغرق ذلك دقيقة."))
                    OutlinedButton(onClick = { job?.cancel(); step = CreateStep.Setup }, modifier = Modifier.padding(top = 24.dp)) { Text(tr("Cancel", "إلغاء")) }
                }
                is CreateStep.Failed -> Column(Modifier.fillMaxWidth().padding(top = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    MaterialSymbol("error", 48)
                    Text(s.error.message(language, gemini.model), textAlign = TextAlign.Center, modifier = Modifier.padding(16.dp))
                    if (s.error != AIError.NoKey) Button(onClick = { withConsent(::generate) }) { Text(tr("Try again", "حاول مجددًا")) }
                    TextButton(onClick = { step = CreateStep.Setup }) { Text(tr("Back", "رجوع")) }
                    if (s.error == AIError.NoKey || s.error == AIError.InvalidKey || s.error is AIError.DailyQuota) TextButton(onClick = { step = CreateStep.External }) { Text(tr("Use another AI instead", "استخدم ذكاءً اصطناعيًا آخر بدلًا من ذلك")) }
                }
                is CreateStep.Batch -> Column(Modifier.fillMaxWidth().padding(top = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    if (s.finished) {
                        MaterialSymbol(if (s.created > 0) "check_circle" else "error", 48)
                        Text(tr("Created ${s.created} of ${s.total} widgets", "أُنشئ ${s.created} من ${s.total} ويدجت"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
                        if (s.failed > 0) Footnote(tr("${s.failed} couldn't be created. Try them one at a time.", "تعذّر إنشاء ${s.failed}. جرّبها واحدًا تلو الآخر."))
                        Button(onClick = onCreatedAll, modifier = Modifier.padding(top = 16.dp)) { Text(tr("Show My widgets", "اعرض ودجاتي")) }
                    } else {
                        LinearProgressIndicator(progress = { s.current / maxOf(s.total, 1).toFloat() }, modifier = Modifier.fillMaxWidth())
                        Text(tr("Creating ${s.current + 1} of ${s.total}", "جارٍ إنشاء ${s.current + 1} من ${s.total}"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
                        Footnote(tr("One request per widget. Each one is saved to My widgets as it's done.", "طلب واحد لكل ويدجت، ويُحفظ كل واحد في ودجاتي فور انتهائه."))
                        OutlinedButton(onClick = { job?.cancel() }, modifier = Modifier.padding(top = 16.dp)) { Text(tr("Stop", "إيقاف"), color = MaterialTheme.colorScheme.error) }
                    }
                }
                CreateStep.External -> ExternalAIView(prompt, picked, cropped, crop, cardShape, options.size,
                    onPick = { cropForExternal = true; pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) },
                    onCrop = { cropForExternal = true; step = CreateStep.Crop },
                    onImported = { design, layout -> onResult(design, null, layout) { } }, onBulk = onBulk)
            }
        }
    }
    askConsent?.let { action ->
        AlertDialog(
            onDismissRequest = { askConsent = null },
            title = { Text(tr("Send the image to Google?", "إرسال الصورة إلى Google؟")) },
            text = { Text(tr("The image you picked goes to Google Gemini with your own key, to design the widget. Nothing else is sent, and nothing goes to us. You can withdraw this by removing the key in Settings.", "تُرسل الصورة التي اخترتها إلى Google Gemini بمفتاحك لتصميم الويدجت. لا يُرسل شيء غيرها، ولا يصلنا شيء. يمكنك التراجع بحذف المفتاح من الإعدادات.")) },
            confirmButton = { TextButton(onClick = { gemini.consented = true; askConsent = null; action() }) { Text(tr("Allow", "اسمح")) } },
            dismissButton = { TextButton(onClick = { askConsent = null }) { Text(tr("Cancel", "إلغاء")) } },
        )
    }
}

/** The crop step (ADR-024): detected widgets outlined, the biggest selected; corner handles, size presets, whole image, Create all. */
@Composable
private fun CropView(image: Bitmap, detected: List<DetectedWidget>, allowsAll: Boolean, onDone: (RectF?, CardShape?, String) -> Unit, onAll: (List<DetectedWidget>) -> Unit) {
    val biggest = detected.maxByOrNull { it.rect.width() * it.rect.height() }
    var selection by remember { mutableStateOf(biggest?.rect ?: RectF(0f, 0f, image.width.toFloat(), image.height.toFloat())) }
    var shape by remember { mutableStateOf(biggest?.shape) }
    var preset by remember { mutableStateOf("free") }
    var version by remember { mutableIntStateOf(0) }
    val primary = MaterialTheme.colorScheme.primary
    Text(tr("Crop to the widget", "اقتصاص الويدجت"), style = MaterialTheme.typography.titleMedium)
    Footnote(when {
        detected.isEmpty() -> tr("No widget outline found. Drag the corners around it, or use the whole image.", "لم يُعثر على حدود ويدجت. اسحب الزوايا حوله، أو استخدم الصورة كاملة.")
        detected.size > 1 -> tr("${detected.size} widgets found. Tap one to select it, or create all of them.", "عُثر على ${detected.size} ويدجت. اضغط واحدًا لتحديده، أو أنشئها كلها.")
        else -> tr("The widget is selected. Drag the corners to adjust.", "تم تحديد الويدجت. اسحب الزوايا لضبطه.")
    })
    BoxWithConstraints(Modifier.fillMaxWidth().padding(vertical = 8.dp)) {
        val density = LocalDensity.current
        val widthPx = with(density) { maxWidth.toPx() }
        val scale = widthPx / image.width
        val heightDp = with(density) { (image.height * scale).toDp() }
        Box(Modifier.fillMaxWidth().height(heightDp)) {
            Image(image.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds)
            Canvas(Modifier.fillMaxSize().pointerInput(detected) {
                detectTapGestures { offset ->
                    val x = offset.x / scale
                    val y = offset.y / scale
                    detected.firstOrNull { it.rect.contains(x, y) }?.let { selection = RectF(it.rect); shape = it.shape; preset = "free"; version++ }
                }
            }.pointerInput(version) {
                var corner = -1
                detectDragGestures(onDragStart = { start ->
                    val corners = listOf(selection.left to selection.top, selection.right to selection.top, selection.left to selection.bottom, selection.right to selection.bottom)
                    corner = corners.indexOfFirst { (cx, cy) -> kotlin.math.hypot(cx * scale - start.x, cy * scale - start.y) < 60 }
                }) { change, drag ->
                    if (corner < 0) return@detectDragGestures
                    change.consume()
                    val dx = drag.x / scale
                    val dy = drag.y / scale
                    val r = RectF(selection)
                    when (corner) {
                        0 -> { r.left += dx; r.top += dy }
                        1 -> { r.right += dx; r.top += dy }
                        2 -> { r.left += dx; r.bottom += dy }
                        else -> { r.right += dx; r.bottom += dy }
                    }
                    if (r.width() >= 40 && r.height() >= 40) {
                        r.intersect(0f, 0f, image.width.toFloat(), image.height.toFloat())
                        selection = r
                        shape = null
                    }
                }
            }) {
                detected.forEach { widget ->
                    drawRect(Color.White.copy(alpha = 0.8f), Offset(widget.rect.left * scale, widget.rect.top * scale), Size(widget.rect.width() * scale, widget.rect.height() * scale), style = Stroke(2.dp.toPx()))
                }
                val topLeft = Offset(selection.left * scale, selection.top * scale)
                val size = Size(selection.width() * scale, selection.height() * scale)
                drawRect(Color.Black.copy(alpha = 0.35f), Offset.Zero, Size(this.size.width, topLeft.y))
                drawRect(Color.Black.copy(alpha = 0.35f), Offset(0f, topLeft.y + size.height), Size(this.size.width, this.size.height - topLeft.y - size.height))
                drawRect(Color.Black.copy(alpha = 0.35f), Offset(0f, topLeft.y), Size(topLeft.x, size.height))
                drawRect(Color.Black.copy(alpha = 0.35f), Offset(topLeft.x + size.width, topLeft.y), Size(this.size.width - topLeft.x - size.width, size.height))
                drawRect(primary, topLeft, size, style = Stroke(3.dp.toPx()))
                listOf(topLeft, Offset(topLeft.x + size.width, topLeft.y), Offset(topLeft.x, topLeft.y + size.height), Offset(topLeft.x + size.width, topLeft.y + size.height)).forEach {
                    drawCircle(Color.White, 11.dp.toPx(), it)
                    drawCircle(primary, 11.dp.toPx(), it, style = Stroke(2.dp.toPx()))
                }
            }
        }
    }
    Segmented(listOf("free" to tr("Free", "حر"), "small" to tr("Small", "صغير"), "medium" to tr("Medium", "متوسط"), "large" to tr("Large", "كبير")), preset, { value ->
        preset = value
        val aspect = when (value) { "small" -> 1f; "medium" -> 2.14f; "large" -> 0.95f; else -> null }
        if (aspect != null) {
            val r = RectF(selection)
            if (r.width() / r.height() > aspect) { val w = r.height() * aspect; r.left = r.centerX() - w / 2; r.right = r.left + w }
            else { val h = r.width() / aspect; r.top = r.centerY() - h / 2; r.bottom = r.top + h }
            selection = r
        }
    })
    Spacer(Modifier.height(12.dp))
    Button(onClick = {
        val size = if (preset != "free") preset else DetectedWidget(selection, shape ?: CardShape.ROUNDED_RECT).suggestedSize(image.width)
        onDone(selection, shape, size)
    }, modifier = Modifier.fillMaxWidth()) { Text(tr("Use this crop", "استخدم هذا الاقتصاص")) }
    if (allowsAll && detected.size > 1) OutlinedButton(onClick = { onAll(detected) }, modifier = Modifier.fillMaxWidth()) { Text(tr("Create all ${detected.size}", "أنشئ الـ ${detected.size} كلها")) }
    TextButton(onClick = { onDone(null, null, "auto") }, modifier = Modifier.fillMaxWidth()) { Text(tr("Use whole image", "استخدم الصورة كاملة")) }
}

/** Use another AI (ADR-023): crop and share the image, copy the instructions, import the reply. */
@Composable
private fun ExternalAIView(
    prompt: WidgetPrompt, picked: Bitmap?, cropped: Bitmap?, crop: RectF?, cardShape: CardShape?, size: String,
    onPick: () -> Unit, onCrop: () -> Unit, onImported: (SavedDesign, LayoutRepair) -> Unit, onBulk: (BulkRequest) -> Unit,
) {
    val context = LocalContext.current
    val language = appLanguage()
    var copied by remember { mutableStateOf(false) }
    var pasted by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<ExternalAI.ImportError?>(null) }
    var fixCopied by remember { mutableStateOf(false) }
    /** ADR-029: every widget in the image, as {"widgets": [...]}. */
    var allWidgets by remember { mutableStateOf(false) }
    fun importText(text: String) {
        fixCopied = false
        // A JSON array or several objects in one paste (ADR-027).
        if (com.khaled.widgetstudio.ai.BulkImport.split(text).size > 1) {
            PendingImport.text = null
            onBulk(BulkRequest(text = text))
            return
        }
        try {
            val widget = ExternalAI.importWidget(text, size)
            error = null
            PendingImport.text = null
            onImported(widget.design(language), widget.layout)
        } catch (e: ExternalAI.ImportError) {
            error = e
        }
    }
    LaunchedEffect(Unit) { PendingImport.text?.let { importText(it) } }
    SectionTitle(tr("Your image", "صورتك"))
    SectionCard {
        (cropped ?: picked)?.let { Image(it.asImageBitmap(), null, Modifier.fillMaxWidth().heightIn(max = 200.dp), contentScale = ContentScale.Fit) }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = onPick) { Text(if (picked == null) tr("Pick the image", "اختر الصورة") else tr("Change", "غيّر")) }
            if (picked != null) OutlinedButton(onClick = onCrop) { Text(tr("Adjust crop", "اضبط الاقتصاص")) }
        }
        (cropped ?: picked)?.let { image ->
            TextButton(onClick = { share(context, image) }) { Text(tr("Save or share the cropped image", "احفظ الصورة المقتصّة أو شاركها")) }
        }
        Footnote(tr("Crop it to the widget, then share or save the crop and upload that image to the chat.", "اقتصّها على الويدجت، ثم شارك الاقتصاص أو احفظه وارفع تلك الصورة إلى المحادثة."))
    }
    SectionTitle(tr("1. Copy the instructions", "١. انسخ التعليمات"))
    SectionCard {
        Button(onClick = {
            val text = ExternalAI.instructions(prompt, GenerationOptions(size = size, detectedCard = cardShape, cropped = crop != null, allWidgets = allWidgets))
            context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("Widget Studio", text))
            copied = true
        }) { Text(if (copied) tr("Copied. Now paste them with your image", "نُسخت. الصقها الآن مع صورتك") else tr("Copy instructions", "انسخ التعليمات")) }
        Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
            androidx.compose.material3.Switch(checked = allWidgets, onCheckedChange = { allWidgets = it; copied = false })
            Spacer(Modifier.padding(4.dp))
            Text(tr("All widgets in the image", "كل الويدجتات في الصورة"))
        }
        Footnote(tr("Paste them into ChatGPT, Claude or Gemini on the web and attach your image in the same message.", "الصقها في ChatGPT أو Claude أو Gemini على الويب، وأرفق صورتك في الرسالة نفسها."))
    }
    SectionTitle(tr("2. Import the answer", "٢. استورد الرد"))
    SectionCard {
        Button(onClick = { importText(context.getSystemService(ClipboardManager::class.java)?.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString() ?: "") }) { Text(tr("Paste from clipboard", "الصق من الحافظة")) }
        ImportButtons(onBulk)
        OutlinedTextField(pasted, { pasted = it }, label = { Text(tr("Or paste the reply here", "أو الصق الرد هنا")) }, modifier = Modifier.fillMaxWidth(), minLines = 3, maxLines = 8)
        if (pasted.isNotEmpty()) TextButton(onClick = { importText(pasted) }) { Text(tr("Import", "استيراد")) }
        Footnote(tr("Extra text and code fences are removed; only a widget design is accepted, never code. You can also share the reply or a .json file to Widget Studio.", "يُحذف النص الزائد وعلامات الكود، ولا يُقبل إلا تصميم ويدجت، وليس كودًا أبدًا. ويمكنك أيضًا مشاركة الرد أو ملف ‎.json‎ مع ستوديو الويدجت."))
    }
    error?.let { e ->
        SectionTitle(tr("Couldn't import", "تعذّر الاستيراد"))
        SectionCard {
            Text(when (e) {
                ExternalAI.ImportError.Empty -> tr("There's nothing to import. Copy the AI's whole reply first.", "لا يوجد ما يُستورد. انسخ رد الذكاء الاصطناعي كاملًا أولًا.")
                ExternalAI.ImportError.NoJSON -> tr("No widget design found in this text. Ask the AI to reply with only the JSON object.", "لم يُعثر على تصميم ويدجت في هذا النص. اطلب من الذكاء الاصطناعي أن يرد بكائن JSON فقط.")
                ExternalAI.ImportError.Unreadable -> tr("This file can't be read.", "تعذّرت قراءة هذا الملف.")
                ExternalAI.ImportError.TooLarge -> tr("This reply is too long for a widget. Ask the AI for a simpler design.", "هذا الرد أطول من أن يكون ويدجت. اطلب من الذكاء الاصطناعي تصميمًا أبسط.")
                is ExternalAI.ImportError.Invalid -> tr("The design doesn't pass Widget Studio's checks (details below). Copy the fix request and send it to the AI.", "التصميم لا يجتاز فحوص ستوديو الويدجت (التفاصيل بالأسفل). انسخ طلب الإصلاح وأرسله إلى الذكاء الاصطناعي.")
            }, color = MaterialTheme.colorScheme.error)
            if (e is ExternalAI.ImportError.Invalid) Text(e.problems, style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = {
                context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("Widget Studio", ExternalAI.fixRequest(e)))
                fixCopied = true
            }) { Text(if (fixCopied) tr("Copied. Send it to the AI", "نُسخ. أرسله إلى الذكاء الاصطناعي") else tr("Copy a fix request", "انسخ طلب إصلاح")) }
            Footnote(tr("Send the fix request to the same chat, then import the new reply.", "أرسل طلب الإصلاح إلى المحادثة نفسها، ثم استورد الرد الجديد."))
        }
    }
}

/** Shares a PNG of [image] (the share sheet includes saving it). */
private fun share(context: Context, image: Bitmap) {
    val folder = File(context.cacheDir, "shared").apply { mkdirs() }
    val file = File(folder, "widget-crop.png")
    file.outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) }
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
    val send = Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

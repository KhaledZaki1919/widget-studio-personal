package com.khaled.widgetstudio.ui

import android.Manifest
import android.app.NotificationManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.documentfile.provider.DocumentFile
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import com.khaled.widgetstudio.ai.BulkImport
import com.khaled.widgetstudio.ai.ExternalAI
import com.khaled.widgetstudio.data.MediaHub
import com.khaled.widgetstudio.design.DesignStore
import com.khaled.widgetstudio.design.InteractiveSummary
import com.khaled.widgetstudio.design.LayerEditing
import com.khaled.widgetstudio.design.SavedDesign
import com.khaled.widgetstudio.design.Wiring
import com.khaled.widgetstudio.spec.Capabilities
import com.khaled.widgetstudio.spec.Capability
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.WidgetSpec
import com.khaled.widgetstudio.widget.WidgetEnvironment
import com.khaled.widgetstudio.widget.Widgets
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** The result screen's "Interactive" summary (ADR-027): what is live, what a tap does, what only looks like a control. */
@Composable
fun InteractiveCard(state: EditorState, onChange: (List<Int>) -> Unit) {
    val language = appLanguage()
    val summary = InteractiveSummary.build(state.design.spec, language)
    SectionTitle(tr("Interactive", "تفاعلي"))
    SectionCard {
        if (summary.isEmpty) Footnote(tr("This design shows fixed content: nothing live and nothing to tap.", "هذا التصميم يعرض محتوى ثابتًا: لا بيانات حية ولا شيء للضغط عليه."))
        @Composable
        fun group(title: String, items: List<InteractiveSummary.Item>) {
            if (items.isEmpty()) return
            Text(title, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 6.dp))
            items.forEach { item ->
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(item.title, style = MaterialTheme.typography.bodyMedium)
                        item.detail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                    if (item.path.isNotEmpty()) TextButton(onClick = { onChange(item.path) }) { Text(tr("Change", "تغيير")) }
                }
            }
        }
        group(tr("Live", "حي"), summary.live)
        group(tr("On tap", "عند الضغط"), summary.tappable)
        group(tr("Decorative", "زخرفي"), summary.decorative)
    }
    Footnote(tr("Change opens that layer. Live data and On tap are at the end of each layer.", "«تغيير» يفتح الطبقة. «بيانات حية» و«عند الضغط» في آخر كل طبقة."))
}

/** Picks a catalog capability, by group, with search; the lists come from the catalog. */
@Composable
private fun CapabilityDialog(title: String, capabilities: List<Capability>, selected: String?, onDismiss: () -> Unit, onPick: (Capability?) -> Unit) {
    val language = appLanguage()
    var query by remember { mutableStateOf("") }
    val text = query.trim().lowercase()
    val shown = capabilities.filter { c -> text.isEmpty() || c.id.lowercase().contains(text) || c.title.resolved(language).lowercase().contains(text) || c.keywords.any { it.lowercase().contains(text) } }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                OutlinedTextField(query, { query = it }, label = { Text(tr("Search", "بحث")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                LazyColumn(Modifier.heightIn(max = 380.dp).padding(top = 8.dp)) {
                    item { Row(Modifier.fillMaxWidth().clickable { onPick(null) }.padding(vertical = 10.dp)) { Text(tr("None", "بدون")) } }
                    for (group in Capabilities.groups) {
                        val inGroup = shown.filter { it.group == group.id }
                        if (inGroup.isEmpty()) continue
                        item { Text(group.title.resolved(language), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary, modifier = Modifier.padding(top = 10.dp)) }
                        items(inGroup, key = { it.id }) { capability ->
                            Column(Modifier.fillMaxWidth().clickable { onPick(capability) }.padding(vertical = 8.dp)) {
                                Text((if (capability.id == selected) "✓ " else "") + capability.title.resolved(language))
                                val note = capability.noteAndroid ?: when (capability.supportAndroid) {
                                    "panel" -> tr("Opens the system panel", "يفتح لوحة النظام")
                                    "unsupported" -> tr("Not available on Android", "غير متاح في أندرويد")
                                    else -> null
                                }
                                note?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                            }
                        }
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(tr("Cancel", "إلغاء")) } },
    )
}

/** The layer editor's Live data and On tap sections (ADR-027). */
@Composable
fun WiringCards(state: EditorState, path: List<Int>) {
    val language = appLanguage()
    val layer = LayerEditing.layer(path, state.design.spec.layers) ?: return
    var picking by remember { mutableStateOf<String?>(null) }
    val kind = Wiring.bindableKind(layer)
    val current = Wiring.binding(layer)
    val button = Wiring.button(path, state.design.spec)
    val action = button?.let { Capabilities.action(it.second.action) }
    SectionCard {
        if (kind != null) {
            Row(Modifier.fillMaxWidth().clickable { picking = "live" }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(tr("Live data", "بيانات حية"), modifier = Modifier.weight(1f))
                Text(current?.let(Capabilities::binding)?.title?.resolved(language) ?: tr("None", "بدون"), color = MaterialTheme.colorScheme.primary)
            }
            HorizontalDivider()
        }
        Row(Modifier.fillMaxWidth().clickable { picking = "tap" }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(tr("On tap", "عند الضغط"), modifier = Modifier.weight(1f))
            Text(action?.title?.resolved(language) ?: tr("None", "بدون"), color = MaterialTheme.colorScheme.primary)
        }
        if (action?.arg == "optional" && button != null) {
            OutlinedTextField(button.second.arg ?: "", { value ->
                state.update("arg") { design ->
                    val found = Wiring.button(path, design.spec) ?: return@update design
                    val layers = design.spec.layers.mapIndexed { index, item ->
                        if (index == found.first) item.copy(content = found.second.copy(arg = value.ifEmpty { null })) else item
                    }
                    design.copy(spec = design.spec.copy(layers = layers))
                }
            }, label = { Text(tr("Value (minutes, or shortcut)", "القيمة (دقائق أو shortcut)")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        }
        if (action?.argFieldType != null) Footnote(tr("Set its value under Fields.", "اضبط قيمته في قسم الحقول."))
    }
    when (picking) {
        "live" -> CapabilityDialog(tr("Live data", "بيانات حية"), Wiring.bindings(kind ?: "text"), current, { picking = null }) { picked ->
            picking = null
            state.update { design -> design.copy(spec = design.spec.copy(layers = LayerEditing.replace(path, design.spec.layers, Wiring.withBinding(picked?.id, layer)))) }
        }
        "tap" -> CapabilityDialog(tr("On tap", "عند الضغط"), Capabilities.actions, action?.id, { picking = null }) { picked ->
            picking = null
            state.update { design -> design.copy(spec = Wiring.withAction(picked?.id, null, path, design.spec)) }
        }
    }
}

/** Whether a catalog permission is already granted. */
private fun isGranted(context: Context, id: String, healthGranted: Boolean): Boolean = when (id) {
    "location" -> WidgetEnvironment.live(context).hasLocationPermission()
    "health" -> healthGranted
    "calendar" -> context.checkSelfPermission(Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED
    "notificationAccess" -> MediaHub.isEnabled(context)
    "dndAccess" -> context.getSystemService(NotificationManager::class.java)?.isNotificationPolicyAccessGranted == true
    "writeSettings" -> Settings.System.canWrite(context)
    else -> true
}

/** Asks for what a saved design needs, right after saving it (ADR-027): one row per missing permission. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PermissionsScreen(specs: List<WidgetSpec>, onDone: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val language = appLanguage()
    val live = remember { WidgetEnvironment.live(context) }
    var tick by remember { mutableIntStateOf(0) }
    var healthGranted by remember { mutableStateOf(false) }
    fun refreshed() {
        scope.launch { live.refresh(); Widgets.updateAll(context); tick++ }
    }
    LaunchedEffect(tick) {
        healthGranted = runCatching { HealthConnectClient.getOrCreate(context).permissionController.getGrantedPermissions().containsAll(live.healthPermissions) }.getOrDefault(false)
    }
    val runtime = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { refreshed() }
    val health = rememberLauncherForActivityResult(PermissionController.createRequestPermissionResultContract()) { refreshed() }
    val settings = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { refreshed() }
    val needed = specs.flatMap { Capabilities.permissions(it) }.distinctBy { it.id }
    @Suppress("UNUSED_EXPRESSION") tick
    val missing = needed.filter { !isGranted(context, it.id, healthGranted) }
    Scaffold(topBar = { TopAppBar(title = { Text(tr("This widget needs", "يحتاج هذا الويدجت إلى")) }) }) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            needed.forEach { permission ->
                SectionCard {
                    Text(permission.title.resolved(language), style = MaterialTheme.typography.titleSmall)
                    if (permission !in missing) {
                        Text("✓ " + tr("Allowed", "مسموح"), color = MaterialTheme.colorScheme.primary)
                    } else {
                        Button(onClick = {
                            when (permission.id) {
                                "location" -> runtime.launch(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION))
                                "calendar" -> runtime.launch(arrayOf(Manifest.permission.READ_CALENDAR))
                                "health" -> health.launch(live.allHealthPermissions)
                                "notificationAccess" -> settings.launch(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                                "dndAccess" -> settings.launch(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                                "writeSettings" -> settings.launch(Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS, Uri.parse("package:${context.packageName}")))
                            }
                        }) { Text(tr("Allow", "اسمح")) }
                        if (permission.id == "notificationAccess") RestrictedSettingsHint()
                    }
                }
            }
            Footnote(tr("Anything you skip shows a clear message in the widget, and a tap brings you back here.", "ما تتخطاه يظهر برسالة واضحة في الويدجت، ويعيدك الضغط إلى هنا."))
            Button(onClick = onDone, modifier = Modifier.fillMaxWidth()) { Text(if (missing.isEmpty()) tr("Done", "تم") else tr("Later", "لاحقًا")) }
        }
    }
}

/** Specs that need a permission not granted yet; the permissions screen shows only then. */
fun needsPermissions(context: Context, specs: List<WidgetSpec>): Boolean =
    specs.flatMap { Capabilities.permissions(it) }.any { !isGranted(context, it.id, healthGranted = it.id != "health") || it.id == "health" && WidgetEnvironment.live(context).healthIssue != null }

/** What to import: picked or shared files, a folder, or pasted text. */
data class BulkRequest(val uris: List<Uri> = emptyList(), val folder: Uri? = null, val text: String? = null)

/** The sources behind a request, with what couldn't be read. */
private fun load(context: Context, request: BulkRequest): Pair<List<BulkImport.Source>, List<BulkImport.Failure>> {
    val sources = mutableListOf<BulkImport.Source>()
    val failed = mutableListOf<BulkImport.Failure>()
    var total = 0L
    fun read(uri: Uri, name: String) {
        if (sources.size >= BulkImport.MAX_FILES) return
        try {
            val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: throw IllegalStateException()
            total += bytes.size
            if (total > BulkImport.MAX_TOTAL_BYTES) throw ExternalAI.ImportError.TooLarge
            sources += BulkImport.sources(bytes, name)
        } catch (error: ExternalAI.ImportError) {
            failed += BulkImport.Failure(name, error)
        } catch (error: Exception) {
            failed += BulkImport.Failure(name, ExternalAI.ImportError.Unreadable)
        }
    }
    fun walk(folder: DocumentFile, prefix: String) {
        for (file in folder.listFiles()) {
            val name = file.name ?: continue
            if (file.isDirectory) walk(file, "$prefix$name/")
            else if (name.lowercase().endsWith(".json") || name.lowercase().endsWith(".zip")) read(file.uri, prefix + name)
        }
    }
    for (uri in request.uris) read(uri, DocumentFile.fromSingleUri(context, uri)?.name ?: uri.lastPathSegment ?: "file")
    request.folder?.let { uri -> DocumentFile.fromTreeUri(context, uri)?.let { walk(it, "") } }
    request.text?.let { sources += BulkImport.sources(it, "1") }
    return sources.take(BulkImport.MAX_FILES) to failed
}

/** Bulk import (ADR-027): progress, then what happened. Valid designs are already in My widgets. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun BulkImportScreen(request: BulkRequest, onOpen: (SavedDesign) -> Unit, onClose: (List<WidgetSpec>) -> Unit) {
    val context = LocalContext.current
    val language = appLanguage()
    var done by remember { mutableIntStateOf(0) }
    var total by remember { mutableIntStateOf(0) }
    var summary by remember { mutableStateOf<BulkImport.Summary?>(null) }
    var unread by remember { mutableStateOf(emptyList<BulkImport.Failure>()) }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(request) {
        val result = withContext(Dispatchers.IO) {
            val store = DesignStore.get(context)
            val (sources, failed) = load(context, request)
            unread = failed
            total = sources.size
            val outcome = BulkImport.run(sources, store.designs.value, language) { done = it }
            outcome.added.forEach { store.save(it.design) }
            outcome
        }
        Widgets.updateAll(context)
        summary = result
    }
    val finish = { onClose(summary?.added?.map { it.design.spec } ?: emptyList()) }
    BackHandler(enabled = summary != null) { finish() }
    Scaffold(topBar = {
        TopAppBar(title = { Text(tr("Import widgets", "استيراد الويدجت")) }, actions = { if (summary != null) TextButton(onClick = finish) { Text(tr("Done", "تم")) } })
    }) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            val result = summary
            if (result == null) {
                LinearProgressIndicator(progress = { if (total > 0) done.toFloat() / total else 0f }, modifier = Modifier.fillMaxWidth())
                Text("$done / $total", style = MaterialTheme.typography.bodySmall)
            } else {
                val failed = unread + result.failed
                SectionCard {
                    Text(tr("${result.added.size} added", "أُضيف ${result.added.size}"), style = MaterialTheme.typography.titleMedium)
                    if (result.fixedCount > 0) Text(tr("${result.fixedCount} fixed automatically", "أُصلح ${result.fixedCount} تلقائيًا"))
                    if (result.duplicates.isNotEmpty()) Text(tr("${result.duplicates.size} skipped as duplicates", "تُخطي ${result.duplicates.size} لأنها مكررة"))
                    if (failed.isNotEmpty()) Text(tr("${failed.size} failed", "فشل ${failed.size}"), color = MaterialTheme.colorScheme.error)
                }
                if (result.added.isNotEmpty()) SectionCard {
                    result.added.forEach { item ->
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(item.design.name)
                                if (item.needsEditing) Text(tr("Some texts overlap: check the layers", "بعض النصوص متداخلة: راجع الطبقات"), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
                            }
                            TextButton(onClick = { onOpen(item.design) }) { Text(tr("Open", "افتح")) }
                        }
                    }
                }
                if (failed.isNotEmpty()) SectionCard {
                    failed.forEach { failure ->
                        Text(failure.name, style = MaterialTheme.typography.titleSmall)
                        Text(reason(failure.error), style = MaterialTheme.typography.bodySmall)
                    }
                    OutlinedButton(onClick = {
                        context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("Widget Studio", BulkImport.fixRequest(failed)))
                        copied = true
                    }) { Text(if (copied) tr("Copied", "نُسخ") else tr("Copy a fix request", "انسخ طلب إصلاح")) }
                }
            }
        }
    }
}

@Composable
private fun reason(error: ExternalAI.ImportError): String = when (error) {
    ExternalAI.ImportError.Empty -> tr("The file is empty.", "الملف فارغ.")
    ExternalAI.ImportError.NoJSON -> tr("No widget design found in it.", "لم يُعثر فيه على تصميم ويدجت.")
    ExternalAI.ImportError.TooLarge -> tr("Too large to import.", "أكبر من أن يُستورد.")
    ExternalAI.ImportError.Unreadable -> tr("This file can't be read.", "تعذّرت قراءة هذا الملف.")
    is ExternalAI.ImportError.Invalid -> error.problems
}

/** "Pick files" and "Pick a folder", wherever imports start. */
@Composable
fun ImportButtons(onRequest: (BulkRequest) -> Unit) {
    val files = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris -> if (uris.isNotEmpty()) onRequest(BulkRequest(uris = uris)) }
    val folder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri -> if (uri != null) onRequest(BulkRequest(folder = uri)) }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        OutlinedButton(onClick = { files.launch(arrayOf("*/*")) }) { Text(tr("Files or a .zip", "ملفات أو .zip")) }
        OutlinedButton(onClick = { folder.launch(null) }) { Text(tr("A folder", "مجلد")) }
    }
}

package com.khaled.widgetstudio.ui

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.khaled.widgetstudio.data.RefreshWorker
import com.khaled.widgetstudio.design.DesignStore
import com.khaled.widgetstudio.design.LayoutRepair
import com.khaled.widgetstudio.design.SavedDesign
import com.khaled.widgetstudio.spec.RenderContext
import com.khaled.widgetstudio.spec.TemplateLibrary
import com.khaled.widgetstudio.spec.WidgetSpec
import com.khaled.widgetstudio.widget.WidgetEnvironment
import com.khaled.widgetstudio.widget.Widgets
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId

class MainActivity : ComponentActivity() {
    // ADR-030: widgets redraw when the app opens and closes (designs, settings or data may have changed).
    override fun onStart() {
        super.onStart()
        com.khaled.widgetstudio.widget.LiveUpdates.changed(this, com.khaled.widgetstudio.widget.LiveUpdates.Source.APP)
        com.khaled.widgetstudio.widget.LiveWidgetsService.sync(this)
    }

    override fun onStop() {
        com.khaled.widgetstudio.widget.LiveUpdates.changed(this, com.khaled.widgetstudio.widget.LiveUpdates.Source.APP)
        super.onStop()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        WidgetEnvironment.renderer(this)   // loads the fonts and the icon whitelist
        RefreshWorker.schedule(this)
        com.khaled.widgetstudio.widget.WidgetPreviews.publish(this)
        setContent { StudioTheme { AppRoot(opening(intent)) } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val open = opening(intent)
        setContent { StudioTheme { AppRoot(open) } }
    }

    /** What an intent asks to show; shared text or a .json file goes to the import screen. */
    private fun opening(intent: Intent?): String? {
        when (intent?.action) {
            // Files shared or opened in the app go to bulk import (ADR-027); text to the import screen.
            Intent.ACTION_SEND -> {
                val stream = intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
                if (stream != null) { PendingImport.bulk = BulkRequest(uris = listOf(stream)); return OPEN_BULK }
                intent.getStringExtra(Intent.EXTRA_TEXT)?.let { PendingImport.text = it; return OPEN_IMPORT }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val streams = intent.getParcelableArrayListExtra<android.net.Uri>(Intent.EXTRA_STREAM).orEmpty()
                if (streams.isNotEmpty()) { PendingImport.bulk = BulkRequest(uris = streams); return OPEN_BULK }
            }
            Intent.ACTION_VIEW -> intent.data?.let { PendingImport.bulk = BulkRequest(uris = listOf(it)); return OPEN_BULK }
            "androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE", "android.intent.action.VIEW_PERMISSION_USAGE" -> {
                val anchor = if (WidgetEnvironment.language(this) == "ar") "ar" else "en"
                startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse("https://khaledzaki1919.github.io/widget-studio/privacy.html#$anchor")))
                finish()
                return null
            }
        }
        return intent?.getStringExtra(EXTRA_OPEN)
    }

    companion object {
        const val EXTRA_OPEN = "open"
        const val OPEN_SETTINGS = "settings"
        const val OPEN_QIBLA = "qibla"
        const val OPEN_IMPORT = "import"
        const val OPEN_BULK = "bulk"
        const val OPEN_TASKS = "tasks"
        const val OPEN_TASK_ADD = "taskAdd"

        fun intent(context: Context, open: String?) = Intent(context, MainActivity::class.java)
            .putExtra(EXTRA_OPEN, open).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    }
}

/** Full-screen flows over the tabs. */
sealed class Overlay {
    data class Editor(val state: EditorState, val layout: LayoutRepair? = null, val onRegenerate: (() -> Unit)? = null) : Overlay()
    data object Qibla : Overlay()
    data object Diagnostics : Overlay()
    data object Create : Overlay()
    data object Onboarding : Overlay()
    data class Bulk(val request: BulkRequest) : Overlay()
    /** Right after saving: what the design needs (ADR-027). */
    data class Permissions(val specs: List<com.khaled.widgetstudio.spec.WidgetSpec>) : Overlay()
}

enum class Tab { LIBRARY, MY_WIDGETS, TASKS, SETTINGS }

@Composable
fun AppRoot(open: String?) {
    val context = LocalContext.current
    val live = remember { WidgetEnvironment.live(context) }
    var tab by rememberSaveable { mutableStateOf(if (open == MainActivity.OPEN_SETTINGS) Tab.SETTINGS else if (open == MainActivity.OPEN_TASKS || open == MainActivity.OPEN_TASK_ADD) Tab.TASKS else Tab.LIBRARY) }
    var overlay by remember { mutableStateOf<Overlay?>(if (!live.settings.onboardingDone) Overlay.Onboarding else if (open == MainActivity.OPEN_QIBLA) Overlay.Qibla else if (open == MainActivity.OPEN_IMPORT) Overlay.Create else if (open == MainActivity.OPEN_BULK) PendingImport.bulk?.let { Overlay.Bulk(it) } else null) }
    LaunchedEffect(Unit) {
        live.refresh()
        Widgets.updateAll(context)
    }
    val language = appLanguage()
    fun edit(design: SavedDesign, isNew: Boolean, photo: Bitmap? = null) {
        overlay = Overlay.Editor(EditorState(design, isNew, photo))
    }
    fun saved(specs: List<com.khaled.widgetstudio.spec.WidgetSpec>) {
        tab = Tab.MY_WIDGETS
        overlay = if (needsPermissions(context, specs)) Overlay.Permissions(specs) else null
    }
    when (val current = overlay) {
        is Overlay.Editor -> EditorScreen(current.state, onClose = { overlay = null }, onSaved = { saved(listOf(current.state.design.spec)) }, layout = current.layout, onRegenerate = current.onRegenerate)
        is Overlay.Bulk -> BulkImportScreen(current.request, onOpen = { edit(it, false) }, onClose = { specs -> PendingImport.bulk = null; saved(specs) })
        is Overlay.Permissions -> PermissionsScreen(current.specs, onDone = { overlay = null })
        Overlay.Qibla -> QiblaScreen(onClose = { overlay = null })
        Overlay.Diagnostics -> DiagnosticsScreen(onClose = { overlay = null })
        Overlay.Create -> CreateScreen(
            onClose = { overlay = null },
            onResult = { design, photo, layout, regenerate -> overlay = Overlay.Editor(EditorState(design, true, photo), layout, regenerate) },
            onCreatedAll = { overlay = null; tab = Tab.MY_WIDGETS },
            onBulk = { overlay = Overlay.Bulk(it) },
        )
        Overlay.Onboarding -> OnboardingScreen(onFinish = { live.settings.onboardingDone = true; overlay = null })
        null -> Scaffold(bottomBar = {
            NavigationBar {
                NavigationBarItem(selected = tab == Tab.LIBRARY, onClick = { tab = Tab.LIBRARY }, icon = { MaterialSymbol("grid_view") }, label = { Text(tr("Library", "المكتبة")) })
                NavigationBarItem(selected = tab == Tab.MY_WIDGETS, onClick = { tab = Tab.MY_WIDGETS }, icon = { MaterialSymbol("widgets") }, label = { Text(tr("My widgets", "ودجاتي")) })
                NavigationBarItem(selected = tab == Tab.TASKS, onClick = { tab = Tab.TASKS }, icon = { MaterialSymbol("checklist") }, label = { Text(tr("Tasks", "المهام")) })
                NavigationBarItem(selected = tab == Tab.SETTINGS, onClick = { tab = Tab.SETTINGS }, icon = { MaterialSymbol("settings") }, label = { Text(tr("Settings", "الإعدادات")) })
            }
        }) { padding ->
            Box(Modifier.padding(bottom = padding.calculateBottomPadding())) {
                when (tab) {
                    Tab.LIBRARY -> LibraryScreen(onPick = { spec -> edit(SavedDesign.new(spec, language), true) }, onCreate = { overlay = Overlay.Create })
                    Tab.MY_WIDGETS -> MyWidgetsScreen(onEdit = { edit(it, false) }, onBrowse = { tab = Tab.LIBRARY }, onCreate = { overlay = Overlay.Create }, onImport = { overlay = Overlay.Bulk(it) })
                    Tab.TASKS -> TasksScreen(startAdding = open == MainActivity.OPEN_TASK_ADD)
                    Tab.SETTINGS -> SettingsScreen(onQibla = { overlay = Overlay.Qibla }, onIntroduction = { overlay = Overlay.Onboarding }, onDiagnostics = { overlay = Overlay.Diagnostics })
                }
            }
        }
    }
}

/** A raw Material Symbols glyph (not limited to the spec's icon whitelist). */
@Composable
fun MaterialSymbol(name: String, size: Int = 24) {
    val context = LocalContext.current
    val family = remember { FontFamily(androidx.compose.ui.text.font.Font("fonts/MaterialSymbolsRounded-Filled.ttf", context.assets)) }
    Text(name, fontFamily = family, fontSize = size.sp, textAlign = TextAlign.Center)
}

/** A template previewed with real data where there is some, like the iOS gallery. */
@Composable
fun TemplatePreview(spec: WidgetSpec, language: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    SpecPreview(spec, spec.id + language, modifier) {
        val now = Instant.now()
        val live = WidgetEnvironment.live(context)
        RenderContext(now = now, language = language, zone = ZoneId.systemDefault(), data = live.previewSnapshot(now), uses24Hour = live.settings.clockFormat.uses24Hour(context))
    }
}

/** Every template by category; a tap opens it in the editor as a new design. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(onPick: (WidgetSpec) -> Unit, onCreate: () -> Unit) {
    val context = LocalContext.current
    val library = remember { WidgetEnvironment.library(context) }
    val appLang = appLanguage()
    var language by rememberSaveable { mutableStateOf(appLang) }
    Scaffold(topBar = { TopAppBar(title = { Text(tr("Library", "المكتبة")) }) }) { padding ->
        LazyVerticalGrid(
            columns = GridCells.Adaptive(160.dp),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding() + 8.dp, bottom = 24.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Button(onClick = onCreate, modifier = Modifier.fillMaxWidth()) { Text(tr("Create from image", "صمّم من صورة")) }
                    Segmented(listOf("ar" to "العربية", "en" to "English"), language, { language = it })
                    Footnote(tr("To add a widget: long-press the home screen → Widgets → Widget Studio, then choose a design. Resize it as you like.", "لإضافة ويدجت: اضغط مطولًا على الشاشة الرئيسية ← الأدوات ← ستوديو الويدجت، ثم اختر تصميمًا. غيّر حجمه كما تريد."))
                }
            }
            for ((category, name) in TemplateLibrary.categories) {
                val specs = library.all.filter { it.category == category }
                if (specs.isEmpty()) continue
                item(span = { GridItemSpan(maxLineSpan) }) { Text(name.resolved(appLang), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp)) }
                items(specs, key = { it.id }, span = { spec -> GridItemSpan(if (spec.family.width > 200) maxLineSpan else 1) }) { spec ->
                    Card(shape = RoundedCornerShape(16.dp), modifier = Modifier.clickable { onPick(spec) }) {
                        Column(Modifier.padding(10.dp)) {
                            TemplatePreview(spec, language, Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)))
                            Text(spec.name.resolved(appLang), style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(top = 8.dp))
                        }
                    }
                }
            }
        }
    }
}

/** Saved designs: edit, rename, duplicate, delete. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun MyWidgetsScreen(onEdit: (SavedDesign) -> Unit, onBrowse: () -> Unit, onCreate: () -> Unit, onImport: (BulkRequest) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val store = remember { DesignStore.get(context) }
    val designs by store.designs.collectAsState()
    val language = appLanguage()
    val copySuffix = tr(" copy", " (نسخة)")
    var renaming by remember { mutableStateOf<SavedDesign?>(null) }
    var deleting by remember { mutableStateOf<List<SavedDesign>>(emptyList()) }
    /** Select mode: delete many at once (ADR-028). */
    var selecting by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf(setOf<String>()) }
    val snackbar = remember { SnackbarHostState() }
    val deletedLabel = tr("Deleted", "حُذف")
    val undoLabel = tr("Undo", "تراجع")
    /** Removes designs, with a few seconds to bring them back with their photos. */
    fun remove(list: List<SavedDesign>) {
        val saved = list.map { it to store.imageBytes(it) }
        list.forEach { store.delete(it.id) }
        scope.launch {
            Widgets.updateAll(context)
            if (snackbar.showSnackbar(deletedLabel, undoLabel, duration = SnackbarDuration.Short) == SnackbarResult.ActionPerformed) {
                saved.forEach { (design, image) -> store.restore(design, image) }
                Widgets.updateAll(context)
            }
        }
    }
    Scaffold(snackbarHost = { SnackbarHost(snackbar) }, bottomBar = {
        if (selecting) {
            Button(enabled = selected.isNotEmpty(), onClick = { deleting = designs.filter { it.id in selected } }, modifier = Modifier.fillMaxWidth().padding(12.dp)) {
                Text(tr("Delete", "حذف") + " (" + selected.size + ")")
            }
        }
    }, topBar = {
        Column {
            TopAppBar(title = { Text(tr("My widgets", "ودجاتي")) }, actions = {
                if (designs.isNotEmpty()) TextButton(onClick = { selecting = !selecting; selected = emptySet() }) { Text(if (selecting) tr("Done", "تم") else tr("Select", "تحديد")) }
            })
            Box(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 8.dp)) { ImportButtons(onImport) }
        }
    }) { padding ->
        if (designs.isEmpty()) {
            Column(Modifier.fillMaxSize().padding(padding).padding(32.dp), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                MaterialSymbol("widgets", 56)
                Spacer(Modifier.height(12.dp))
                Text(tr("No designs yet", "لا توجد تصاميم بعد"), style = MaterialTheme.typography.titleMedium)
                Text(tr("Customize a template or create one from an image. Saved designs appear here and in the widget's design list.", "خصّص قالبًا أو صمّم من صورة. تظهر التصاميم المحفوظة هنا وفي قائمة تصاميم الويدجت."),
                    textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 12.dp))
                Button(onClick = onBrowse) { Text(tr("Browse templates", "تصفح القوالب")) }
                OutlinedButton(onClick = onCreate, modifier = Modifier.padding(top = 8.dp)) { Text(tr("Create from image", "صمّم من صورة")) }
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(160.dp),
                contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = padding.calculateTopPadding() + 8.dp, bottom = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(designs, key = { it.id }, span = { GridItemSpan(if (it.spec.family.width > 200) maxLineSpan else 1) }) { design ->
                    var menu by remember { mutableStateOf(false) }
                    val swipe = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
                        if (value != SwipeToDismissBoxValue.Settled) deleting = listOf(design)
                        false
                    })
                    SwipeToDismissBox(state = swipe, gesturesEnabled = !selecting, backgroundContent = {
                        Box(Modifier.fillMaxSize().padding(horizontal = 16.dp), contentAlignment = Alignment.CenterEnd) { Text(tr("Delete", "حذف"), color = MaterialTheme.colorScheme.error) }
                    }) {
                    Card(shape = RoundedCornerShape(16.dp), modifier = Modifier.combinedClickable(
                        onClick = {
                            if (selecting) selected = if (design.id in selected) selected - design.id else selected + design.id else onEdit(design)
                        },
                        onLongClick = { menu = true },
                    )) {
                        Column(Modifier.padding(10.dp)) {
                            DesignPreview(design, language, store.image(design), Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                if (selecting) Checkbox(checked = design.id in selected, onCheckedChange = { on -> selected = if (on) selected + design.id else selected - design.id })
                                Text(design.name, style = MaterialTheme.typography.labelLarge, modifier = Modifier.weight(1f), maxLines = 1)
                                Box {
                                    TextButton(onClick = { menu = true }, modifier = Modifier.width(48.dp)) { Text("⋯") }
                                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                        DropdownMenuItem(text = { Text(tr("Edit", "تعديل")) }, onClick = { menu = false; onEdit(design) })
                                        DropdownMenuItem(text = { Text(tr("Rename", "إعادة التسمية")) }, onClick = { menu = false; renaming = design })
                                        DropdownMenuItem(text = { Text(tr("Duplicate", "تكرار")) }, onClick = { menu = false; store.duplicate(design, copySuffix) })
                                        DropdownMenuItem(text = { Text(tr("Delete", "حذف"), color = MaterialTheme.colorScheme.error) }, onClick = { menu = false; deleting = listOf(design) })
                                    }
                                }
                            }
                        }
                    }
                    }
                }
            }
        }
    }
    renaming?.let { design ->
        var name by remember(design.id) { mutableStateOf(design.name) }
        AlertDialog(
            onDismissRequest = { renaming = null }, title = { Text(tr("Rename", "إعادة التسمية")) },
            text = { OutlinedTextField(name, { name = it.take(SavedDesign.MAX_NAME_LENGTH) }, singleLine = true) },
            confirmButton = {
                TextButton(enabled = name.isNotBlank(), onClick = {
                    store.save(design.copy(name = name.trim()))
                    renaming = null
                    scope.launch { Widgets.updateAll(context) }
                }) { Text(tr("Save", "حفظ")) }
            },
            dismissButton = { TextButton(onClick = { renaming = null }) { Text(tr("Cancel", "إلغاء")) } },
        )
    }
    if (deleting.isNotEmpty()) {
        val first = deleting.first()
        AlertDialog(
            onDismissRequest = { deleting = emptyList() },
            title = { Text(if (deleting.size == 1) tr("Delete “${first.name}”?", "حذف «${first.name}»؟") else tr("Delete ${deleting.size} designs?", "حذف ${deleting.size} تصاميم؟")) },
            text = { Text(tr("Widgets showing it will ask you to choose another design.", "الودجات التي تعرضه ستطلب منك اختيار تصميم آخر.")) },
            confirmButton = {
                TextButton(onClick = {
                    remove(deleting)
                    deleting = emptyList()
                    selected = emptySet()
                    selecting = false
                }) { Text(tr("Delete", "حذف"), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { deleting = emptyList() }) { Text(tr("Cancel", "إلغاء")) } },
        )
    }
}

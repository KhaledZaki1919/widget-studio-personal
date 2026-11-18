package com.khaled.widgetstudio.ui

import android.Manifest
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.health.connect.client.PermissionController
import com.khaled.widgetstudio.BuildConfig
import com.khaled.widgetstudio.ai.GeminiSettings
import com.khaled.widgetstudio.design.ClockFormat
import com.khaled.widgetstudio.widget.WidgetEnvironment
import com.khaled.widgetstudio.widget.Widgets
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

private const val SITE = "https://khaledzaki1919.github.io/widget-studio/"

/** Asks for location and Health Connect in place; shared by Settings and the onboarding page. */
@Composable
fun PermissionRows() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val live = remember { WidgetEnvironment.live(context) }
    var tick by remember { mutableIntStateOf(0) }
    val location = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        scope.launch { live.refresh(); Widgets.updateAll(context); tick++ }
    }
    val health = rememberLauncherForActivityResult(PermissionController.createRequestPermissionResultContract()) {
        scope.launch { live.refreshHealth(); Widgets.updateAll(context); tick++ }
    }
    @Suppress("UNUSED_EXPRESSION") tick
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        val hasLocation = live.hasLocationPermission()
        Text(tr("Location", "الموقع"), style = MaterialTheme.typography.titleSmall)
        Text(tr("Weather, prayer times and the Qibla use your approximate location. It stays on your phone; weather requests send it rounded to about 1 km.", "يستخدم الطقس ومواقيت الصلاة والقبلة موقعك التقريبي. يبقى على هاتفك، وتُرسل طلبات الطقس الموقع مقرّبًا إلى نحو 1 كم."), style = MaterialTheme.typography.bodySmall)
        if (hasLocation) Text("✓ " + tr("Allowed", "مسموح") + (live.location?.city?.let { " · $it" } ?: ""), color = MaterialTheme.colorScheme.primary)
        else Button(onClick = { location.launch(arrayOf(Manifest.permission.ACCESS_COARSE_LOCATION, Manifest.permission.ACCESS_FINE_LOCATION)) }) { Text(tr("Allow location", "اسمح بالموقع")) }

        Text("Health Connect", style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(top = 8.dp))
        Text(tr("Steps and sleep come from Health Connect, read only, on your phone.", "تأتي الخطوات والنوم من Health Connect، للقراءة فقط وعلى هاتفك."), style = MaterialTheme.typography.bodySmall)
        when {
            !live.healthAvailable() -> OutlinedButton(onClick = {
                context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=com.google.android.apps.healthdata")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }) { Text(tr("Get Health Connect", "ثبّت Health Connect")) }
            live.healthIssue == null && live.snapshot().stepsToday != null -> Text("✓ " + tr("Allowed", "مسموح"), color = MaterialTheme.colorScheme.primary)
            else -> Button(onClick = { health.launch(live.allHealthPermissions) }) { Text(tr("Allow health data", "اسمح ببيانات الصحة")) }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(onQibla: () -> Unit, onIntroduction: () -> Unit, onDiagnostics: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val live = remember { WidgetEnvironment.live(context) }
    val settings = live.settings
    var clock by remember { mutableStateOf(settings.clockFormat) }
    var fahrenheit by remember { mutableStateOf(settings.fahrenheit) }
    var goal by remember { mutableStateOf(settings.stepGoal.toString()) }
    var dhikrs by remember { mutableStateOf(settings.dhikrs.joinToString("\n")) }
    val gemini = remember { GeminiSettings(context) }
    var key by remember { mutableStateOf(if (gemini.hasKey()) "••••••••" else "") }
    var model by remember { mutableStateOf(gemini.model) }
    fun open(url: String) = context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    Scaffold(topBar = { TopAppBar(title = { Text(tr("Settings", "الإعدادات")) }) }) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            SectionTitle(tr("Data for widgets", "بيانات الويدجت"))
            SectionCard { PermissionRows() }
            TextButton(onClick = { scope.launch { live.refresh(); Widgets.updateAll(context) } }) { Text(tr("Refresh data now", "حدّث البيانات الآن")) }

            LiveWidgetsSection()

            SectionTitle(tr("Display", "العرض"))
            SectionCard {
                Dropdown(tr("Clock", "الساعة"), listOf(ClockFormat.DEVICE to tr("Device", "حسب الجهاز"), ClockFormat.H12 to tr("12-hour", "12 ساعة"), ClockFormat.H24 to tr("24-hour", "24 ساعة")), clock) {
                    clock = it; settings.clockFormat = it; Widgets.updateAllAsync(context)
                }
                Dropdown(tr("Temperature", "درجة الحرارة"), listOf(false to "°C", true to "°F"), fahrenheit) {
                    fahrenheit = it; settings.fahrenheit = it
                    scope.launch { live.refresh(); Widgets.updateAll(context) }
                }
                OutlinedTextField(goal, { v -> goal = v.filter(Char::isDigit).take(6); goal.toIntOrNull()?.takeIf { it > 0 }?.let { settings.stepGoal = it; Widgets.updateAllAsync(context) } },
                    label = { Text(tr("Daily step goal", "هدف الخطوات اليومي")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
            }

            SectionTitle(tr("Tasbeeh", "التسبيح"))
            SectionCard {
                OutlinedTextField(dhikrs, { dhikrs = it; settings.dhikrs = it.split("\n"); Widgets.updateAllAsync(context) }, label = { Text(tr("Adhkar, one per line", "الأذكار، ذكر في كل سطر")) }, modifier = Modifier.fillMaxWidth(), minLines = 4)
                Footnote(tr("The tasbeeh widget counts each dhikr separately and moves to the next after 33.", "يعدّ ويدجت التسبيح كل ذكر على حدة وينتقل إلى التالي بعد 33."))
            }

            SectionTitle(tr("AI (Gemini)", "الذكاء الاصطناعي (Gemini)"))
            SectionCard {
                OutlinedTextField(key, { key = it }, label = { Text(tr("Gemini API key", "مفتاح Gemini")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(enabled = key.isNotBlank() && !key.startsWith("•"), onClick = { gemini.saveKey(key.trim()); key = "••••••••" }) { Text(tr("Save key", "احفظ المفتاح")) }
                    if (gemini.hasKey()) OutlinedButton(onClick = { gemini.deleteKey(); key = "" }) { Text(tr("Remove", "احذف")) }
                }
                OutlinedTextField(model, { model = it.trim(); gemini.model = model.ifEmpty { GeminiSettings.DEFAULT_MODEL } }, label = { Text(tr("Model", "النموذج")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    GeminiSettings.suggestedModels.forEach { name -> TextButton(onClick = { model = name; gemini.model = name }) { Text(name.removePrefix("gemini-"), maxLines = 1) } }
                }
                Footnote(tr("Your key is stored encrypted on this phone (Android Keystore) and sent only to Google. Free keys allow about 20 requests a day per model.", "يُحفظ مفتاحك مشفّرًا على هذا الهاتف (Android Keystore) ولا يُرسل إلا إلى Google. المفاتيح المجانية تسمح بنحو 20 طلبًا يوميًا لكل نموذج."))
                TextButton(onClick = { open("https://aistudio.google.com/apikey") }) { Text(tr("Get a free key", "احصل على مفتاح مجاني")) }
            }

            SectionTitle(tr("More", "المزيد"))
            SectionCard {
                TextButton(onClick = onQibla) { Text(tr("Qibla compass", "بوصلة القبلة")) }
                if (Build.VERSION.SDK_INT >= 33) TextButton(onClick = {
                    context.startActivity(Intent(Settings.ACTION_APP_LOCALE_SETTINGS, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                }) { Text(tr("Language", "اللغة")) }
                TextButton(onClick = onIntroduction) { Text(tr("Show the introduction", "اعرض المقدمة")) }
                TextButton(onClick = onDiagnostics) { Text(tr("Diagnostics", "التشخيص")) }
                TextButton(onClick = { open(SITE + "privacy.html#" + if (appLanguageStatic(context) == "ar") "ar" else "en") }) { Text(tr("Privacy policy", "سياسة الخصوصية")) }
                TextButton(onClick = { open(SITE + "support.html#" + if (appLanguageStatic(context) == "ar") "ar" else "en") }) { Text(tr("Support", "الدعم")) }
            }
            Text(tr("Widget Studio", "ستوديو الويدجت") + " " + BuildConfig.VERSION_NAME + " · " + tr("No accounts, no ads, no tracking.", "بلا حسابات ولا إعلانات ولا تتبّع."),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(vertical = 24.dp))
        }
    }
}

fun appLanguageStatic(context: android.content.Context) = WidgetEnvironment.language(context)

/** Three short pages and the permissions page (iOS M6 + M6.1); skippable, reopenable in Settings. */
@Composable
fun OnboardingScreen(onFinish: () -> Unit) {
    var page by remember { mutableIntStateOf(0) }
    BackHandler(enabled = page > 0) { page-- }
    val pages = listOf(
        Triple("widgets", tr("Widgets your way", "ويدجت على ذوقك"), tr("Pick a template, change its words, colors and photo, or create one from any image.", "اختر قالبًا وغيّر كلماته وألوانه وصورته، أو صمّم واحدًا من أي صورة.")),
        Triple("add_to_home_screen", tr("Add it to your home screen", "أضفه إلى شاشتك الرئيسية"), tr("Long-press the home screen → Widgets → Widget Studio, then choose a design. Resize it as you like.", "اضغط مطولًا على الشاشة الرئيسية ← الأدوات ← ستوديو الويدجت، ثم اختر تصميمًا. غيّر حجمه كما تريد.")),
        Triple("lock", tr("Private by design", "الخصوصية أولًا"), tr("No accounts, no ads, no tracking. Your designs and photos stay on your phone. The AI uses your own key and sends only the image you choose.", "بلا حسابات ولا إعلانات ولا تتبّع. تصاميمك وصورك تبقى على هاتفك، والذكاء الاصطناعي يستخدم مفتاحك ولا يرسل إلا الصورة التي تختارها.")),
    )
    Column(Modifier.fillMaxSize().padding(24.dp).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.height(48.dp))
        if (page < pages.size) {
            val (symbol, title, body) = pages[page]
            LogoMark()
            Spacer(Modifier.height(24.dp))
            MaterialSymbol(symbol, 48)
            Text(title, style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 12.dp))
            Text(body, style = MaterialTheme.typography.bodyLarge, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(top = 12.dp))
        } else {
            MaterialSymbol("location_on", 48)
            Text(tr("Allow data for your widgets", "اسمح ببيانات الويدجت"), style = MaterialTheme.typography.headlineSmall, textAlign = TextAlign.Center, modifier = Modifier.padding(vertical = 12.dp))
            SectionCard { PermissionRows() }
            Footnote(tr("You can change this later in Settings.", "يمكنك تغيير ذلك لاحقًا من الإعدادات."))
        }
        Spacer(Modifier.height(32.dp))
        Button(onClick = { if (page < pages.size) page++ else onFinish() }, modifier = Modifier.fillMaxWidth()) {
            Text(if (page < pages.size) tr("Continue", "متابعة") else tr("Start", "ابدأ"))
        }
        if (page < pages.size) TextButton(onClick = onFinish) { Text(tr("Skip", "تخطَّ")) }
    }
}

/** The app's logo: a 2×2 grid of widget shapes (LogoMark.swift, onDark). */
@Composable
fun LogoMark(size: Int = 72) {
    Canvas(Modifier.height(size.dp).aspectRatio(1f)) {
        val side = this.size.minDimension
        val tile = side * 0.28f
        val gap = side * 0.0625f
        val margin = side * 0.19f
        fun origin(column: Int, row: Int) = Offset(margin + column * (tile + gap), margin + row * (tile + gap))
        val ink = Color.White
        val background = Color(0xFF0E0E0E)
        drawRoundRect(background, cornerRadius = CornerRadius(side * 0.22f))
        val card = origin(0, 0)
        drawRoundRect(ink, card, Size(tile, tile), CornerRadius(tile * 0.26f))
        val step = tile * 0.25f
        for (column in -1..1) for (row in -1..1) {
            drawCircle(background, tile * 0.06f, Offset(card.x + tile / 2 + column * step, card.y + tile / 2 + row * step))
        }
        drawCircle(ink, tile / 2, origin(1, 0) + Offset(tile / 2, tile / 2))
        val width = tile * 0.16f
        drawCircle(ink, tile / 2 - width / 2, origin(0, 1) + Offset(tile / 2, tile / 2), style = Stroke(width))
        drawCircle(Color(0xFFE2231A), tile / 2, origin(1, 1) + Offset(tile / 2, tile / 2))
    }
}

/** The live Qibla compass: the phone's heading (rotation vector) against the Qibla bearing. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QiblaScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    val live = remember { WidgetEnvironment.live(context) }
    val bearing = remember { live.snapshot().qiblaBearing }
    var heading by remember { mutableFloatStateOf(0f) }
    var available by remember { mutableStateOf(true) }
    BackHandler(onBack = onClose)
    DisposableEffect(Unit) {
        val manager = context.getSystemService(SensorManager::class.java)
        val sensor = manager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        available = sensor != null
        val listener = object : SensorEventListener {
            private val matrix = FloatArray(9)
            private val angles = FloatArray(3)
            override fun onSensorChanged(event: SensorEvent) {
                SensorManager.getRotationMatrixFromVector(matrix, event.values)
                SensorManager.getOrientation(matrix, angles)
                val degrees = (Math.toDegrees(angles[0].toDouble()).toFloat() + 360) % 360
                heading = heading + (((degrees - heading + 540) % 360) - 180) * 0.15f
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        sensor?.let { manager.registerListener(listener, it, SensorManager.SENSOR_DELAY_UI) }
        onDispose { manager?.unregisterListener(listener) }
    }
    LaunchedEffect(Unit) { live.refreshLocation() }
    Scaffold(topBar = { TopAppBar(title = { Text(tr("Qibla", "القبلة")) }, navigationIcon = { TextButton(onClick = onClose) { Text(tr("Done", "تم")) } }) }) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().padding(24.dp), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            if (bearing == null) {
                Text(tr("Allow location to find the Qibla.", "اسمح بالموقع لمعرفة اتجاه القبلة."), textAlign = TextAlign.Center)
                Spacer(Modifier.height(12.dp))
                PermissionRows()
                return@Column
            }
            val turn = ((bearing.toFloat() - heading + 540) % 360) - 180
            val primary = MaterialTheme.colorScheme.primary
            val onSurface = MaterialTheme.colorScheme.onSurface
            Canvas(Modifier.fillMaxWidth(0.8f).aspectRatio(1f)) {
                val r = size.minDimension / 2
                drawCircle(onSurface.copy(alpha = 0.15f), radius = r, style = Stroke(width = r * 0.03f))
                rotate(-heading) {
                    for (tick in 0 until 72) {
                        val a = Math.toRadians(tick * 5.0)
                        val inner = if (tick % 18 == 0) r * 0.82f else r * 0.9f
                        drawLine(onSurface.copy(alpha = if (tick % 18 == 0) 0.9f else 0.35f), Offset(center.x + (kotlin.math.sin(a) * inner).toFloat(), center.y - (kotlin.math.cos(a) * inner).toFloat()),
                            Offset(center.x + (kotlin.math.sin(a) * r * 0.97f).toFloat(), center.y - (kotlin.math.cos(a) * r * 0.97f).toFloat()), strokeWidth = r * 0.012f)
                    }
                }
                rotate(turn) {
                    drawLine(primary, center, Offset(center.x, center.y - r * 0.75f), strokeWidth = r * 0.06f, cap = androidx.compose.ui.graphics.StrokeCap.Round)
                    drawCircle(primary, radius = r * 0.08f, center = Offset(center.x, center.y - r * 0.78f))
                }
                drawCircle(onSurface, radius = r * 0.05f)
            }
            Spacer(Modifier.height(24.dp))
            Text(if (kotlin.math.abs(turn) < 5) tr("You're facing the Qibla", "أنت تتجه نحو القبلة") else tr("Turn until the red mark points up", "استدر حتى تشير العلامة الحمراء إلى الأعلى"), style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
            Text(tr("Qibla at ${bearing.roundToInt()}° from north", "القبلة على ${bearing.roundToInt()}° من الشمال"), color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (!available) Footnote(tr("This phone has no compass sensor.", "لا يحتوي هذا الهاتف على مستشعر بوصلة."))
            Footnote(tr("Keep the phone flat and away from metal and magnets.", "أبقِ الهاتف مستويًا وبعيدًا عن المعادن والمغناطيس."))
        }
    }
}

/**
 * ADR-030: how fast widgets update, and what keeps them fast. Android needs one running component to
 * hear battery, volume, Wi-Fi and similar changes; phone makers also stop background apps, so the
 * section opens the right page for each brand.
 */
@Composable
private fun LiveWidgetsSection() {
    val context = LocalContext.current
    var live by remember { mutableStateOf(com.khaled.widgetstudio.widget.LiveWidgetsService.isEnabled(context)) }
    val listener = remember { com.khaled.widgetstudio.data.MediaHub.isEnabled(context) }
    val power = context.getSystemService(android.os.PowerManager::class.java)
    val exempt = power?.isIgnoringBatteryOptimizations(context.packageName) == true
    SectionTitle(tr("Live widgets", "ويدجتات حيّة"))
    SectionCard {
        Text(tr(
            "Widgets redraw within a second when the battery, volume, Wi-Fi, Bluetooth, airplane mode, Do Not Disturb, music or time change, as long as something of the app keeps running: notification access (if you allowed it), or the Live widgets switch below. Without either they refresh every 15 minutes and when you open the app.",
            "تتحدّث الويدجتات خلال ثانية عند تغيّر البطارية أو الصوت أو الواي فاي أو البلوتوث أو وضع الطيران أو عدم الإزعاج أو الموسيقى أو الوقت، طالما بقي جزء من التطبيق يعمل: الوصول إلى الإشعارات (إن سمحت به) أو مفتاح «ويدجتات حيّة» أدناه. وبدونهما تتحدّث كل 15 دقيقة وعند فتح التطبيق.",
        ))
        Text(if (listener) tr("Notification access is on: live updates run.", "الوصول إلى الإشعارات مفعّل: التحديث الحي يعمل.") else tr("Notification access is off.", "الوصول إلى الإشعارات غير مفعّل."), style = androidx.compose.material3.MaterialTheme.typography.bodySmall)
        Row(verticalAlignment = Alignment.CenterVertically) {
            androidx.compose.material3.Switch(checked = live, onCheckedChange = { live = it; com.khaled.widgetstudio.widget.LiveWidgetsService.setEnabled(context, it) })
            Spacer(Modifier.padding(4.dp))
            Text(tr("Live widgets (a quiet notification stays)", "ويدجتات حيّة (يبقى إشعار هادئ)"))
        }
        Text(tr(
            "Battery optimisation can still stop the app. Allow it to run in the background, and on Xiaomi, Oppo, Vivo, Huawei and Samsung phones also turn on autostart or \"no restrictions\".",
            "قد يوقف توفير البطارية التطبيق رغم ذلك. اسمح له بالعمل في الخلفية، وفي هواتف شاومي وأوبو وفيفو وهواوي وسامسونج فعّل أيضًا التشغيل التلقائي أو «بلا قيود».",
        ), style = androidx.compose.material3.MaterialTheme.typography.bodySmall)
        if (!exempt) TextButton(onClick = { BatteryPages.requestExemption(context) }) { Text(tr("Allow background use", "اسمح بالعمل في الخلفية")) }
        BatteryPages.brandPage(context)?.let { (label, intent) ->
            TextButton(onClick = { runCatching { context.startActivity(intent) } }) { Text(label) }
        }
        TextButton(onClick = { runCatching { context.startActivity(android.content.Intent(android.provider.Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) } }) {
            Text(tr("Usage access (screen time widgets)", "الوصول إلى الاستخدام (ويدجتات وقت الشاشة)"))
        }
    }
}

/** The phone maker's own background-start page, where there is one (ADR-030). */
object BatteryPages {
    fun requestExemption(context: android.content.Context) {
        val request = android.content.Intent(android.provider.Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, android.net.Uri.parse("package:" + context.packageName))
        val fallback = android.content.Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        for (intent in listOf(request, fallback)) {
            if (runCatching { context.startActivity(intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)) }.isSuccess) return
        }
    }

    private val pages = listOf(
        "xiaomi" to ("com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity"),
        "redmi" to ("com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity"),
        "poco" to ("com.miui.securitycenter" to "com.miui.permcenter.autostart.AutoStartManagementActivity"),
        "oppo" to ("com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
        "realme" to ("com.coloros.safecenter" to "com.coloros.safecenter.permission.startup.StartupAppListActivity"),
        "oneplus" to ("com.oneplus.security" to "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity"),
        "vivo" to ("com.vivo.permissionmanager" to "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
        "huawei" to ("com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
        "honor" to ("com.huawei.systemmanager" to "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"),
        "samsung" to ("com.samsung.android.lool" to "com.samsung.android.sm.battery.ui.BatteryActivity"),
        "asus" to ("com.asus.mobilemanager" to "com.asus.mobilemanager.autostart.AutoStartActivity"),
    )

    /** A label and an intent for this phone's autostart or battery page, if it has one that resolves. */
    @Composable
    fun brandPage(context: android.content.Context): Pair<String, android.content.Intent>? {
        val brand = android.os.Build.MANUFACTURER.lowercase()
        val (pkg, cls) = pages.firstOrNull { brand.contains(it.first) }?.second ?: return null
        val intent = android.content.Intent().setClassName(pkg, cls).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        if (context.packageManager.resolveActivity(intent, 0) == null) {
            // Not this model's page: the app's own settings page, where autostart usually sits too.
            val details = android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:" + context.packageName)).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
            return tr("App settings (autostart, battery)", "إعدادات التطبيق (التشغيل التلقائي، البطارية)") to details
        }
        return tr("Autostart for " + android.os.Build.MANUFACTURER, "التشغيل التلقائي في " + android.os.Build.MANUFACTURER) to intent
    }
}

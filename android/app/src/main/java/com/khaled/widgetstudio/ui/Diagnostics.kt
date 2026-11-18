package com.khaled.widgetstudio.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.khaled.widgetstudio.data.MediaHub
import com.khaled.widgetstudio.widget.ActionRouter
import com.khaled.widgetstudio.widget.TapLog
import com.khaled.widgetstudio.widget.WidgetStore
import com.khaled.widgetstudio.widget.Widgets
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Media and volume on a real phone (ADR-028). Its buttons call the same code as a widget tap, so
 * "works here, not from the widget" means the tap never arrives, and the tap log shows which.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DiagnosticsScreen(onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var tick by remember { mutableIntStateOf(0) }
    var last by remember { mutableStateOf("") }
    fun run(id: String) {
        scope.launch {
            last = id + ": " + ActionRouter.perform(context, id, "")
            tick++
        }
    }
    @Suppress("UNUSED_EXPRESSION") tick
    val audio = context.getSystemService(AudioManager::class.java)
    val access = MediaHub.isEnabled(context)
    val sessions = MediaHub.sessions(context)
    val entries = TapLog.entries(context)
    val placed = Widgets.placedIds(context)
    Scaffold(topBar = { TopAppBar(title = { Text(tr("Diagnostics", "التشخيص")) }, navigationIcon = { TextButton(onClick = onClose) { Text(tr("Close", "إغلاق")) } }) }) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            SectionTitle(tr("Music", "الموسيقى"))
            SectionCard {
                Row1(tr("Notification access", "الوصول إلى الإشعارات"), if (access) tr("Granted", "ممنوح") else tr("Not granted", "غير ممنوح"))
                if (!access) {
                    Button(onClick = { context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }) { Text(tr("Allow access", "اسمح بالوصول")) }
                    RestrictedSettingsHint()
                }
                Row1(tr("Active media sessions", "جلسات التشغيل النشطة"), if (access) sessions.size.toString() else "—")
                sessions.forEach { Text(it, style = MaterialTheme.typography.bodySmall) }
                if (access && sessions.isEmpty()) Footnote(tr("Start music in any player, then tap Refresh.", "شغّل الموسيقى في أي مشغّل ثم اضغط تحديث."))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { run("media.previous") }) { Text("⏮") }
                    OutlinedButton(onClick = { run("media.playPause") }) { Text("⏯") }
                    OutlinedButton(onClick = { run("media.next") }) { Text("⏭") }
                }
            }

            SectionTitle(tr("Volume", "الصوت"))
            SectionCard {
                if (audio != null) {
                    Row1(tr("Media volume", "صوت الوسائط"), audio.getStreamVolume(AudioManager.STREAM_MUSIC).toString() + " / " + audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC))
                    Row1(tr("Ringer", "الرنين"), audio.getStreamVolume(AudioManager.STREAM_RING).toString() + " / " + audio.getStreamMaxVolume(AudioManager.STREAM_RING))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { run("volume.down") }) { Text("−") }
                    OutlinedButton(onClick = { run("volume.up") }) { Text("+") }
                    OutlinedButton(onClick = { run("volume.mute") }) { Text(tr("Mute", "كتم")) }
                }
                if (last.isNotEmpty()) Footnote(tr("Last test: ", "آخر اختبار: ") + last)
            }

            SectionTitle(tr("Widgets on the home screen", "الويدجت على الشاشة الرئيسية"))
            SectionCard {
                Row1(tr("Placed", "الموضوعة"), placed.size.toString())
                val store = WidgetStore(context)
                placed.forEach { id -> Text("#$id · " + (store.choice(id) ?: tr("nothing chosen", "لم يُختر شيء")), style = MaterialTheme.typography.bodySmall) }
            }

            // ADR-030: how fast a change reaches the widget, per source.
            SectionTitle(tr("Update speed", "سرعة التحديث"))
            SectionCard {
                Text(tr("Live updates: ", "التحديث الحي: ") + (if (com.khaled.widgetstudio.widget.LiveUpdates.isListening) tr("listening", "يعمل") else tr("off (every 15 minutes)", "متوقف (كل 15 دقيقة)")))
                Text(com.khaled.widgetstudio.widget.UpdateLatency.summary(context), style = androidx.compose.material3.MaterialTheme.typography.bodySmall)
            }
            SectionTitle(tr("Last widget taps", "آخر ضغطات الويدجت"))
            SectionCard {
                if (entries.isEmpty()) {
                    Footnote(tr("No tap has reached the app yet. Tap a control on a widget, then Refresh.", "لم تصل أي ضغطة إلى التطبيق بعد. اضغط عنصرًا في الويدجت ثم اضغط تحديث."))
                }
                entries.take(15).forEach { entry -> Text(line(entry), style = MaterialTheme.typography.bodySmall) }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TextButton(onClick = { tick++ }) { Text(tr("Refresh", "تحديث")) }
                    TextButton(onClick = { copy(context, report(context)) }) { Text(tr("Copy report", "انسخ التقرير")) }
                    TextButton(onClick = { TapLog.clear(context); tick++ }) { Text(tr("Clear", "امسح")) }
                }
            }
        }
    }
}

/** Android 13+ blocks notification access for an app installed from a file until the user lifts it. */
@Composable
fun RestrictedSettingsHint() {
    val context = LocalContext.current
    if (Build.VERSION.SDK_INT < 33) return
    Footnote(tr(
        "If the switch is greyed out or says \"Restricted setting\": open App info, tap ⋮ at the top, choose \"Allow restricted settings\", then turn the switch on. Android does this to every app installed from a file.",
        "إذا كان المفتاح معطّلًا أو ظهرت عبارة «إعداد محظور»: افتح معلومات التطبيق، واضغط ⋮ في الأعلى، واختر «السماح بالإعدادات المحظورة»، ثم فعّل المفتاح. يفعل Android ذلك مع كل تطبيق مثبّت من ملف.",
    ))
    OutlinedButton(onClick = {
        context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }) { Text(tr("Open App info", "افتح معلومات التطبيق")) }
}

@Composable
private fun Row1(title: String, value: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

private fun line(entry: TapLog.Entry): String {
    val time = SimpleDateFormat("HH:mm:ss", Locale.US).format(Date(entry.time))
    return "$time ${entry.action}" + (if (entry.arg.isEmpty()) "" else " (${entry.arg})") + (if (entry.widget != 0) " #${entry.widget}" else "") +
        " → ${entry.result}" + (entry.error?.let { " · $it" } ?: "")
}

private fun report(context: Context): String = buildString {
    appendLine("Android ${Build.VERSION.SDK_INT} ${Build.MANUFACTURER} ${Build.MODEL}")
    appendLine("Notification access: ${MediaHub.isEnabled(context)}")
    appendLine("Sessions: " + MediaHub.sessions(context).joinToString(" | "))
    context.getSystemService(AudioManager::class.java)?.let { appendLine("Media volume: ${it.getStreamVolume(AudioManager.STREAM_MUSIC)}/${it.getStreamMaxVolume(AudioManager.STREAM_MUSIC)}") }
    appendLine("Widgets: " + Widgets.placedIds(context).joinToString())
    appendLine("Live updates: " + com.khaled.widgetstudio.widget.LiveUpdates.isListening + ", service " + com.khaled.widgetstudio.widget.LiveWidgetsService.isEnabled(context))
    appendLine("Update delays: " + com.khaled.widgetstudio.widget.UpdateLatency.summary(context).replace("\n", "; "))
    TapLog.entries(context).forEach { appendLine(line(it)) }
}

private fun copy(context: Context, text: String) {
    context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("Widget Studio diagnostics", text))
}

package com.khaled.widgetstudio.ui

import android.Manifest
import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import com.khaled.widgetstudio.data.TaskFormat
import com.khaled.widgetstudio.data.TaskItem
import com.khaled.widgetstudio.data.TaskStore
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** The Tasks tab (ADR-028): today, upcoming and done, stored in a local database. */
@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun TasksScreen(startAdding: Boolean) {
    val context = LocalContext.current
    val store = remember { TaskStore.get(context) }
    val tasks by store.tasks.collectAsState()
    val language = appLanguage()
    val zone = ZoneId.systemDefault()
    var filter by remember { mutableStateOf(TaskFormat.Filter.TODAY) }
    var editing by remember { mutableStateOf<TaskItem?>(null) }
    var deleting by remember { mutableStateOf<TaskItem?>(null) }
    LaunchedEffect(startAdding) { if (startAdding) editing = TaskItem(title = "") }
    val shown = TaskFormat.filter(tasks, filter, Instant.now(), zone)
    Scaffold(
        topBar = { TopAppBar(title = { Text(tr("Tasks", "المهام")) }) },
        floatingActionButton = { FloatingActionButton(onClick = { editing = TaskItem(title = "") }) { Text("+", style = MaterialTheme.typography.titleLarge) } },
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize()) {
            Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) {
                Segmented(
                    listOf(TaskFormat.Filter.TODAY to tr("Today", "اليوم"), TaskFormat.Filter.UPCOMING to tr("Upcoming", "القادمة"), TaskFormat.Filter.DONE to tr("Done", "المنجزة")),
                    filter, { filter = it },
                )
            }
            if (shown.isEmpty()) {
                Text(
                    when (filter) {
                        TaskFormat.Filter.TODAY -> tr("Nothing due today.", "لا مهام لليوم.")
                        TaskFormat.Filter.UPCOMING -> tr("Nothing coming up.", "لا مهام قادمة.")
                        TaskFormat.Filter.DONE -> tr("Nothing done yet.", "لم تُنجز أي مهمة بعد.")
                    },
                    color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(16.dp),
                )
            }
            LazyColumn(contentPadding = PaddingValues(bottom = 88.dp)) {
                items(shown, key = { it.id }) { task ->
                    var menu by remember { mutableStateOf(false) }
                    val swipe = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
                        if (value != SwipeToDismissBoxValue.Settled) deleting = task
                        false
                    })
                    SwipeToDismissBox(state = swipe, backgroundContent = {
                        Box(Modifier.fillMaxSize().padding(horizontal = 16.dp), contentAlignment = Alignment.CenterEnd) { Text(tr("Delete", "حذف"), color = MaterialTheme.colorScheme.error) }
                    }) {
                        Row(
                            Modifier.fillMaxWidth().combinedClickable(onClick = { editing = task }, onLongClick = { menu = true }).padding(horizontal = 8.dp, vertical = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Checkbox(checked = task.done, onCheckedChange = { store.toggle(task.id) })
                            Column(Modifier.weight(1f)) {
                                Text(task.title, textDecoration = if (task.done) TextDecoration.LineThrough else null, color = if (task.done) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface)
                                val detail = listOfNotNull(TaskFormat.dueText(task, Instant.now(), zone, language).ifEmpty { null }, task.list).joinToString(" · ")
                                if (detail.isNotEmpty()) Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            if (task.priority >= 2) Text("!", color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(horizontal = 8.dp))
                            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                DropdownMenuItem(text = { Text(tr("Edit", "تعديل")) }, onClick = { menu = false; editing = task })
                                DropdownMenuItem(text = { Text(tr("Delete", "حذف"), color = MaterialTheme.colorScheme.error) }, onClick = { menu = false; deleting = task })
                            }
                        }
                    }
                }
            }
        }
    }
    editing?.let { task ->
        TaskDialog(task, isNew = tasks.none { it.id == task.id }, onClose = { editing = null }, onSave = { store.save(it); editing = null }, onDelete = { deleting = task; editing = null })
    }
    deleting?.let { task ->
        AlertDialog(
            onDismissRequest = { deleting = null },
            title = { Text(tr("Delete this task?", "هل تحذف هذه المهمة؟")) },
            confirmButton = { TextButton(onClick = { store.delete(task.id); deleting = null }) { Text(tr("Delete", "حذف"), color = MaterialTheme.colorScheme.error) } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text(tr("Cancel", "إلغاء")) } },
        )
    }
}

@Composable
private fun TaskDialog(task: TaskItem, isNew: Boolean, onClose: () -> Unit, onSave: (TaskItem) -> Unit, onDelete: () -> Unit) {
    val context = LocalContext.current
    val zone = ZoneId.systemDefault()
    var title by remember { mutableStateOf(task.title) }
    var list by remember { mutableStateOf(task.list ?: "") }
    var priority by remember { mutableStateOf(task.priority) }
    val start = task.due?.let { Instant.ofEpochMilli(it).atZone(zone) }
    var date by remember { mutableStateOf(start?.toLocalDate()) }
    var time by remember { mutableStateOf(if (task.hasTime) start?.toLocalTime() else null) }
    var reminds by remember { mutableStateOf(task.reminds) }
    val notifications = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) {}
    AlertDialog(
        onDismissRequest = onClose,
        title = { Text(if (isNew) tr("New task", "مهمة جديدة") else tr("Edit task", "تعديل المهمة")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(title, { title = it.take(200) }, label = { Text(tr("Task", "المهمة")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                OutlinedTextField(list, { list = it.take(40) }, label = { Text(tr("List (optional)", "القائمة (اختياري)")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Dropdown(tr("Priority", "الأولوية"), listOf(0 to tr("None", "بدون"), 1 to tr("Low", "منخفضة"), 2 to tr("Medium", "متوسطة"), 3 to tr("High", "عالية")), priority) { priority = it }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    TextButton(onClick = {
                        val initial = date ?: LocalDate.now()
                        DatePickerDialog(context, { _, year, month, day -> date = LocalDate.of(year, month + 1, day) }, initial.year, initial.monthValue - 1, initial.dayOfMonth).show()
                    }) { Text(date?.toString() ?: tr("Add a date", "أضف تاريخًا")) }
                    if (date != null) {
                        TextButton(onClick = {
                            val initial = time ?: LocalTime.of(9, 0)
                            TimePickerDialog(context, { _, hour, minute -> time = LocalTime.of(hour, minute) }, initial.hour, initial.minute, true).show()
                        }) { Text(time?.format(DateTimeFormatter.ofPattern("HH:mm", Locale.US)) ?: tr("Add a time", "أضف وقتًا")) }
                        TextButton(onClick = { date = null; time = null; reminds = false }) { Text("×") }
                    }
                }
                if (date != null && time != null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(tr("Remind me", "ذكّرني"), modifier = Modifier.weight(1f))
                        Switch(checked = reminds, onCheckedChange = { on ->
                            reminds = on
                            if (on && Build.VERSION.SDK_INT >= 33) notifications.launch(Manifest.permission.POST_NOTIFICATIONS)
                        })
                    }
                }
                if (!isNew) TextButton(onClick = onDelete) { Text(tr("Delete task", "حذف المهمة"), color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            TextButton(enabled = title.isNotBlank(), onClick = {
                val due = date?.atTime(time ?: LocalTime.MIDNIGHT)?.atZone(zone)?.toInstant()?.toEpochMilli()
                onSave(task.copy(title = title.trim(), list = list.trim().ifEmpty { null }, priority = priority, due = due, hasTime = time != null, reminds = reminds && time != null))
            }) { Text(tr("Save", "حفظ")) }
        },
        dismissButton = { TextButton(onClick = onClose) { Text(tr("Cancel", "إلغاء")) } },
    )
}

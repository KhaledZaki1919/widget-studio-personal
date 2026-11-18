package com.khaled.widgetstudio.data

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.khaled.widgetstudio.R
import com.khaled.widgetstudio.spec.BindingResolver.Value
import com.khaled.widgetstudio.ui.MainActivity
import com.khaled.widgetstudio.widget.Widgets
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID

/** One task of the Tasks tab (ADR-028): a row of the local database; dates in epoch milliseconds. */
data class TaskItem(
    val id: String = UUID.randomUUID().toString(),
    val title: String,
    val due: Long? = null,
    val hasTime: Boolean = false,
    val reminds: Boolean = false,
    /** 0 none, 1 low, 2 medium, 3 high. */
    val priority: Int = 0,
    val list: String? = null,
    val done: Boolean = false,
    val doneAt: Long? = null,
)

/** Pure logic of tasks; must behave like `TaskFormat` in Tasks.swift. */
object TaskFormat {
    enum class Filter { TODAY, UPCOMING, DONE }

    /** Rows a widget can show. */
    const val ROWS = 6

    /** Open tasks: by due date, undated last, then the highest priority, then the title. */
    fun sorted(tasks: List<TaskItem>): List<TaskItem> =
        tasks.sortedWith(compareBy<TaskItem> { it.due ?: Long.MAX_VALUE }.thenByDescending { it.priority }.thenBy { it.title })

    private fun day(millis: Long, zone: ZoneId) = Instant.ofEpochMilli(millis).atZone(zone).toLocalDate()

    /** Open and due today or overdue. */
    fun isDueToday(task: TaskItem, now: Instant, zone: ZoneId): Boolean {
        val due = task.due ?: return false
        return !task.done && !day(due, zone).isAfter(now.atZone(zone).toLocalDate())
    }

    fun filter(tasks: List<TaskItem>, filter: Filter, now: Instant, zone: ZoneId): List<TaskItem> = when (filter) {
        Filter.TODAY -> sorted(tasks.filter { isDueToday(it, now, zone) })
        Filter.UPCOMING -> sorted(tasks.filter { !it.done && !isDueToday(it, now, zone) })
        Filter.DONE -> tasks.filter { it.done }.sortedByDescending { it.doneAt ?: 0L }
    }

    /** "Today 14:30", "Tomorrow", "7 Nov"; digits Latin, like every other value. */
    fun dueText(task: TaskItem, now: Instant, zone: ZoneId, language: String): String {
        val due = task.due ?: return ""
        val arabic = language.startsWith("ar")
        val date = Instant.ofEpochMilli(due).atZone(zone)
        val days = ChronoUnit.DAYS.between(now.atZone(zone).toLocalDate(), date.toLocalDate())
        val first = when {
            days == 0L -> if (arabic) "اليوم" else "Today"
            days == 1L -> if (arabic) "غدًا" else "Tomorrow"
            days < 0 -> if (arabic) "متأخرة" else "Overdue"
            else -> DateTimeFormatter.ofPattern("d MMM", if (arabic) Locale.forLanguageTag("ar-EG-u-nu-latn") else Locale.US).format(date)
        }
        return if (task.hasTime && days >= 0) first + " " + DateTimeFormatter.ofPattern("HH:mm", Locale.US).format(date) else first
    }

    private fun count(value: Int) = Value.Number(value.toDouble(), value.toString())

    /**
     * The catalog's `tasks.*` values. Rows hold the open tasks, then today's done ones, so a ticked
     * box stays ticked on the widget until the day ends. Empty rows are empty, never "--".
     */
    fun values(tasks: List<TaskItem>, now: Instant, zone: ZoneId, language: String): Map<String, Value> {
        val open = sorted(tasks.filter { !it.done })
        val dueToday = open.filter { isDueToday(it, now, zone) }
        val today = now.atZone(zone).toLocalDate()
        val doneToday = tasks.filter { task -> task.done && task.doneAt?.let { day(it, zone) == today } == true }.sortedBy { it.doneAt ?: 0L }
        val live = mutableMapOf<String, Value>(
            "tasks.list" to Value.Text(open.joinToString("\n") { it.title }),
            "tasks.today.count" to count(dueToday.size),
            "tasks.open.count" to count(open.size),
            "tasks.done.count" to count(doneToday.size),
        )
        val total = doneToday.size + dueToday.size
        val share = if (total == 0) 0.0 else doneToday.size.toDouble() / total
        live["tasks.progress"] = Value.Number(share, Math.round(share * 100).toString())
        live["tasks.next.title"] = Value.Text(open.firstOrNull()?.title ?: if (language.startsWith("ar")) "لا مهام" else "No tasks")
        live["tasks.next.due"] = Value.Text(open.firstOrNull()?.let { dueText(it, now, zone, language) } ?: "")
        live["tasks.next.id"] = Value.Text(open.firstOrNull()?.id ?: "")
        val shown = (open + doneToday).take(ROWS)
        for (row in 1..ROWS) {
            val task = shown.getOrNull(row - 1)
            live["tasks.$row.title"] = Value.Text(task?.title ?: "")
            live["tasks.$row.due"] = Value.Text(task?.let { dueText(it, now, zone, language) } ?: "")
            live["tasks.$row.done"] = Value.Text(if (task?.done == true) "1" else "0")
            live["tasks.$row.id"] = Value.Text(task?.id ?: "")
        }
        return live
    }
}

private class TaskDatabase(context: Context) : SQLiteOpenHelper(context, "tasks.db", null, 1) {
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            "CREATE TABLE tasks (id TEXT PRIMARY KEY, title TEXT NOT NULL, due INTEGER, has_time INTEGER NOT NULL, reminds INTEGER NOT NULL, " +
                "priority INTEGER NOT NULL, list TEXT, done INTEGER NOT NULL, done_at INTEGER)",
        )
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
}

/** The tasks on this phone: one local database, with every change redrawn on the widgets at once. */
class TaskStore private constructor(context: Context) {
    private val app = context.applicationContext
    private val database = TaskDatabase(app)
    private val state = MutableStateFlow(load())

    val tasks: StateFlow<List<TaskItem>> = state

    private fun load(): List<TaskItem> {
        val rows = mutableListOf<TaskItem>()
        database.readableDatabase.query("tasks", null, null, null, null, null, null).use { c ->
            val (id, title, due, time, reminds) = listOf("id", "title", "due", "has_time", "reminds").map(c::getColumnIndexOrThrow)
            val priority = c.getColumnIndexOrThrow("priority")
            val list = c.getColumnIndexOrThrow("list")
            val done = c.getColumnIndexOrThrow("done")
            val doneAt = c.getColumnIndexOrThrow("done_at")
            while (c.moveToNext()) {
                rows += TaskItem(
                    c.getString(id), c.getString(title), if (c.isNull(due)) null else c.getLong(due), c.getInt(time) != 0, c.getInt(reminds) != 0,
                    c.getInt(priority), if (c.isNull(list)) null else c.getString(list), c.getInt(done) != 0, if (c.isNull(doneAt)) null else c.getLong(doneAt),
                )
            }
        }
        return rows
    }

    private fun changed() {
        state.value = load()
        Widgets.updateAllAsync(app)
    }

    fun save(task: TaskItem) {
        val values = ContentValues().apply {
            put("id", task.id)
            put("title", task.title)
            put("due", task.due)
            put("has_time", if (task.hasTime) 1 else 0)
            put("reminds", if (task.reminds) 1 else 0)
            put("priority", task.priority)
            put("list", task.list)
            put("done", if (task.done) 1 else 0)
            put("done_at", task.doneAt)
        }
        database.writableDatabase.insertWithOnConflict("tasks", null, values, SQLiteDatabase.CONFLICT_REPLACE)
        TaskReminders.schedule(app, task)
        changed()
    }

    fun delete(id: String) {
        state.value.firstOrNull { it.id == id }?.let { TaskReminders.cancel(app, it) }
        database.writableDatabase.delete("tasks", "id = ?", arrayOf(id))
        changed()
    }

    /** Ticks or unticks; a false id does nothing. Returns what happened, for the tap log. */
    fun toggle(id: String): String {
        val task = state.value.firstOrNull { it.id == id } ?: return "no such task"
        save(task.copy(done = !task.done, doneAt = if (task.done) null else System.currentTimeMillis()))
        return if (task.done) "reopened" else "completed"
    }

    fun values(now: Instant, zone: ZoneId, language: String) = TaskFormat.values(state.value, now, zone, language)

    /** After a reboot the system has forgotten every alarm. */
    fun rescheduleAll() = state.value.forEach { TaskReminders.schedule(app, it) }

    companion object {
        @Volatile private var instance: TaskStore? = null

        fun get(context: Context): TaskStore = instance ?: synchronized(this) { instance ?: TaskStore(context).also { instance = it } }
    }
}

/** Reminder notifications: one alarm per task. Inexact, so no exact-alarm permission is needed. */
object TaskReminders {
    private const val CHANNEL = "tasks"
    private const val ACTION = "com.khaled.widgetstudio.TASK_REMINDER"
    private const val EXTRA_TITLE = "title"

    private fun pending(context: Context, task: TaskItem): PendingIntent = PendingIntent.getBroadcast(
        context, 0,
        Intent(context, TaskAlarmReceiver::class.java).setAction(ACTION).setData(Uri.parse("task:" + task.id)).putExtra(EXTRA_TITLE, task.title),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    fun schedule(context: Context, task: TaskItem) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val due = task.due
        alarms.cancel(pending(context, task))
        if (task.reminds && !task.done && due != null && due > System.currentTimeMillis()) {
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, due, pending(context, task))
        }
    }

    fun cancel(context: Context, task: TaskItem) {
        context.getSystemService(AlarmManager::class.java)?.cancel(pending(context, task))
    }

    fun show(context: Context, intent: Intent) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val arabic = context.resources.configuration.locales[0].language != "en"
        manager.createNotificationChannel(NotificationChannel(CHANNEL, if (arabic) "المهام" else "Tasks", NotificationManager.IMPORTANCE_DEFAULT))
        val open = PendingIntent.getActivity(context, 0, MainActivity.intent(context, MainActivity.OPEN_TASKS), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(intent.getStringExtra(EXTRA_TITLE) ?: "")
            .setContentText(if (arabic) "حان موعد المهمة" else "Task due")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        if (NotificationManagerCompat.from(context).areNotificationsEnabled()) manager.notify((intent.data?.toString() ?: "").hashCode(), notification)
    }
}

class TaskAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            TaskStore.get(context).rescheduleAll()
            com.khaled.widgetstudio.widget.LiveWidgetsService.sync(context)
        } else TaskReminders.show(context, intent)
    }
}

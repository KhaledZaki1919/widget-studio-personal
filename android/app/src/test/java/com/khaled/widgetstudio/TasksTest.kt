package com.khaled.widgetstudio

import com.khaled.widgetstudio.data.TaskFormat
import com.khaled.widgetstudio.data.TaskItem
import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

/** Tasks' pure logic (ADR-028), the same answers as TaskFormatTests in Swift. */
class TasksTest {
    private val zone = ZoneId.of("Africa/Cairo")
    private val now = Instant.parse("2026-11-05T10:00:00Z")
    private fun at(text: String) = Instant.parse(text).toEpochMilli()

    private val tasks = listOf(
        TaskItem(id = "c", title = "No date"),
        TaskItem(id = "b", title = "Later", due = at("2026-11-08T10:00:00Z")),
        TaskItem(id = "a", title = "Today", due = at("2026-11-05T12:30:00Z"), hasTime = true, priority = 3),
        TaskItem(id = "o", title = "Late", due = at("2026-11-01T10:00:00Z")),
        TaskItem(id = "d", title = "Done", done = true, doneAt = at("2026-11-05T08:00:00Z")),
        TaskItem(id = "e", title = "Old", done = true, doneAt = at("2026-11-01T08:00:00Z")),
    )

    @Test
    fun filters() {
        assertEquals(listOf("o", "a"), TaskFormat.filter(tasks, TaskFormat.Filter.TODAY, now, zone).map { it.id })
        assertEquals(listOf("b", "c"), TaskFormat.filter(tasks, TaskFormat.Filter.UPCOMING, now, zone).map { it.id })
        assertEquals(listOf("d", "e"), TaskFormat.filter(tasks, TaskFormat.Filter.DONE, now, zone).map { it.id })
    }

    @Test
    fun dueTexts() {
        assertEquals("Today 14:30", TaskFormat.dueText(tasks[2], now, zone, "en"))
        assertEquals("Overdue", TaskFormat.dueText(tasks[3], now, zone, "en"))
        assertEquals("8 Nov", TaskFormat.dueText(tasks[1], now, zone, "en"))
    }

    @Test
    fun widgetValues() {
        val live = TaskFormat.values(tasks, now, zone, "en")
        fun shown(key: String) = when (val value = live[key]) {
            is com.khaled.widgetstudio.spec.BindingResolver.Value.Text -> value.text
            is com.khaled.widgetstudio.spec.BindingResolver.Value.Number -> value.display
            else -> null
        }
        assertEquals("2", shown("tasks.today.count"))
        assertEquals("4", shown("tasks.open.count"))
        assertEquals("1", shown("tasks.done.count"))
        assertEquals("33", shown("tasks.progress"))
        assertEquals("Late", shown("tasks.next.title"))
        assertEquals("o", shown("tasks.1.id"))
        assertEquals("Done", shown("tasks.5.title"))
        assertEquals("1", shown("tasks.5.done"))
        assertEquals("", shown("tasks.6.title"))
        assertEquals("Late\nToday\nLater\nNo date", shown("tasks.list"))
    }
}

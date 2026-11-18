package com.khaled.widgetstudio.spec

import android.content.res.AssetManager

/**
 * The bundled templates (TemplateLibrary.swift): the shared JSON files in assets/templates, in
 * the catalog order from the iOS source (assets/spec/catalog-order.txt, written at build time).
 */
class TemplateLibrary(private val assets: AssetManager) {
    val all: List<WidgetSpec> by lazy {
        val files = assets.list("templates").orEmpty().filter { it.endsWith(".json") }
        val specs = files.mapNotNull { file ->
            runCatching { SpecParser.parse(assets.open("templates/$file").bufferedReader().readText()) }.getOrNull()
        }
        val order = runCatching { assets.open("spec/catalog-order.txt").bufferedReader().readLines().filter { it.isNotBlank() } }.getOrDefault(emptyList())
        specs.sortedBy { spec -> order.indexOf(spec.id).let { if (it < 0) Int.MAX_VALUE else it } }
    }

    fun template(id: String): WidgetSpec? = all.firstOrNull { it.id == id }

    companion object {
        /** The categories in library order with their names (SpecCategory.title in Swift). */
        val categories = listOf(
            "time" to LText.Localized("Time", "الوقت"), "weather" to LText.Localized("Weather", "الطقس"),
            "health" to LText.Localized("Health", "الصحة"), "prayer" to LText.Localized("Prayer", "الصلاة"),
            "countdown" to LText.Localized("Countdown", "العد التنازلي"), "photo" to LText.Localized("Photo", "صور"),
            "tiles" to LText.Localized("Tiles", "أزرار"), "counters" to LText.Localized("Counters", "عدّادات"), "tasks" to LText.Localized("Tasks", "المهام"),
        )
    }
}

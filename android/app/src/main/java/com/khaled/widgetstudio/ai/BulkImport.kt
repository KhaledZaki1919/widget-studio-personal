package com.khaled.widgetstudio.ai

import com.khaled.widgetstudio.design.LayoutRepair
import com.khaled.widgetstudio.design.SavedDesign
import com.khaled.widgetstudio.spec.SpecWriter
import com.khaled.widgetstudio.spec.WidgetSpec
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.util.zip.ZipInputStream

/**
 * Many designs at once (BulkImport.swift, ADR-027): files, a .zip, a folder, a JSON array or several
 * objects pasted together. Each goes through the single-import pipeline; valid ones are saved
 * straight to My widgets.
 */
object BulkImport {
    const val MAX_FILES = 200
    const val MAX_TOTAL_BYTES = 20_000_000

    data class Source(val name: String, val text: String)
    data class Failure(val name: String, val error: ExternalAI.ImportError)
    data class Added(val design: SavedDesign, val fixed: Boolean, val needsEditing: Boolean)
    data class Summary(val added: List<Added>, val failed: List<Failure>, val duplicates: List<String>) {
        val fixedCount get() = added.count { it.fixed }
    }

    /** The designs in one text: an object, an array, several objects in a row, or `{"widgets": […]}`. */
    fun split(text: String): List<String> {
        val objects = topLevelObjects(text)
        if (objects.isEmpty()) return listOf(text)
        if (objects.size == 1) {
            val root = runCatching { Json.parseToJsonElement(objects[0]) }.getOrNull() as? JsonObject
            if (root != null && "layers" !in root) {
                for (value in root.values) {
                    val nested = (value as? JsonArray)?.filterIsInstance<JsonObject>()?.map { it.toString() } ?: continue
                    if (nested.isNotEmpty()) return nested
                }
            }
        }
        return objects
    }

    /** Every `{…}` that isn't inside another one, respecting strings and escapes. */
    fun topLevelObjects(text: String): List<String> {
        val objects = mutableListOf<String>()
        var depth = 0
        var inString = false
        var escaped = false
        var start = -1
        text.forEachIndexed { index, c ->
            when {
                inString -> when {
                    escaped -> escaped = false
                    c == '\\' -> escaped = true
                    c == '"' -> inString = false
                }
                depth > 0 && c == '"' -> inString = true
                c == '{' -> {
                    if (depth == 0) start = index
                    depth += 1
                }
                c == '}' && depth > 0 -> {
                    depth -= 1
                    if (depth == 0) objects += text.substring(start, index + 1)
                }
            }
        }
        return objects
    }

    fun sources(text: String, name: String): List<Source> {
        val parts = split(text)
        return parts.mapIndexed { index, part -> Source(if (parts.size > 1) "$name #${index + 1}" else name, part) }
    }

    /** The sources in one file's bytes: a zip by its signature, anything else as text. */
    fun sources(data: ByteArray, name: String): List<Source> {
        val zip = data.size >= 4 && data[0] == 0x50.toByte() && data[1] == 0x4B.toByte() && (data[2] == 3.toByte() || data[2] == 5.toByte())
        return if (zip) zipEntries(data).flatMap { sources(it.text, it.name) } else sources(decoded(data), name)
    }

    fun decoded(data: ByteArray): String = when {
        data.size >= 3 && data[0] == 0xEF.toByte() && data[1] == 0xBB.toByte() && data[2] == 0xBF.toByte() -> String(data, 3, data.size - 3, Charsets.UTF_8)
        data.size >= 2 && ((data[0] == 0xFF.toByte() && data[1] == 0xFE.toByte()) || (data[0] == 0xFE.toByte() && data[1] == 0xFF.toByte())) -> String(data, Charsets.UTF_16)
        else -> String(data, Charsets.UTF_8)
    }

    /** A safe name inside a zip: relative, no `..`, no backslashes or drive letters. */
    fun isSafe(name: String) = name.isNotEmpty() && !name.startsWith("/") && !name.contains('\\') && !name.contains(':') && ".." !in name.split("/")

    /** The `.json` files in a zip, nested folders too; other files are ignored. An unsafe name or a broken limit fails the whole zip. */
    fun zipEntries(data: ByteArray): List<Source> {
        val entries = mutableListOf<Source>()
        var total = 0L
        ZipInputStream(ByteArrayInputStream(data)).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val name = entry.name
                if (!isSafe(name)) throw ExternalAI.ImportError.Invalid("unsafe path in the zip: $name")
                val leaf = name.substringAfterLast('/')
                if (entry.isDirectory || name.startsWith("__MACOSX/") || leaf.startsWith(".") || !leaf.lowercase().endsWith(".json")) continue
                if (entries.size >= MAX_FILES) throw ExternalAI.ImportError.Invalid("too many files in the zip")
                // Reads by hand, so a bomb stops at the limit whatever the header says.
                val out = ByteArrayOutputStream()
                val buffer = ByteArray(16 * 1024)
                while (true) {
                    val read = zip.read(buffer)
                    if (read < 0) break
                    total += read
                    if (total > MAX_TOTAL_BYTES) throw ExternalAI.ImportError.TooLarge
                    out.write(buffer, 0, read)
                }
                entries += Source(name, decoded(out.toByteArray()))
            }
        }
        return entries
    }

    /** What makes two designs the same: everything but ids and dates. */
    fun fingerprint(spec: WidgetSpec, colors: Map<String, String>): String =
        SpecWriter.write(spec.copy(id = "")).toString() + colors.toSortedMap().entries.joinToString(",") { "${it.key}=${it.value}" }

    /** Runs every source through the import pipeline; duplicates are skipped, a taken name gets " (2)". */
    fun run(sources: List<Source>, existing: List<SavedDesign>, language: String, size: String = "auto", progress: (Int) -> Unit = {}): Summary {
        val added = mutableListOf<Added>()
        val failed = mutableListOf<Failure>()
        val duplicates = mutableListOf<String>()
        val seen = existing.map { fingerprint(it.spec, it.colors) }.toMutableSet()
        val names = existing.map { it.name }.toMutableSet()
        sources.forEachIndexed { index, source ->
            progress(index)
            try {
                val widget = ExternalAI.importWidget(source.text, size)
                if (!seen.add(fingerprint(widget.spec, widget.colors))) {
                    duplicates += source.name
                } else {
                    val design = widget.design(language).let { it.copy(name = uniqueName(it.name, names)) }
                    names += design.name
                    added += Added(design, widget.autoWired.isNotEmpty() || widget.layout is LayoutRepair.Fixed, widget.layout is LayoutRepair.NeedsEditing)
                }
            } catch (error: ExternalAI.ImportError) {
                failed += Failure(source.name, error)
            }
        }
        progress(sources.size)
        return Summary(added, failed, duplicates)
    }

    fun uniqueName(name: String, taken: Set<String>): String {
        if (name !in taken) return name
        var number = 2
        while ("$name ($number)" in taken) number += 1
        return "$name ($number)"
    }

    fun fixRequest(failures: List<Failure>): String =
        "Widget Studio could not import these widgets. Fix each one and reply with the corrected JSON objects only, as a JSON array.\n\n" +
            failures.joinToString("\n\n") { "${it.name}: ${ExternalAI.fixRequest(it.error)}" }
}

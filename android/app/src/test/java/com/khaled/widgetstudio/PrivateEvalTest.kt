package com.khaled.widgetstudio

import android.app.Application
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import androidx.test.core.app.ApplicationProvider
import com.khaled.widgetstudio.ai.ExternalAI
import com.khaled.widgetstudio.design.DesignRules
import com.khaled.widgetstudio.render.SpecRenderer
import com.khaled.widgetstudio.spec.DataSnapshot
import com.khaled.widgetstudio.spec.RenderContext
import com.khaled.widgetstudio.spec.WidgetSpec
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.int
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.time.Instant
import java.time.ZoneId

/**
 * Local-only eval of the "Use another AI" flow on the owner's private images (never in CI: it does
 * nothing unless PRIVATE_EVAL names a folder outside the repository's tracked files).
 *
 * PRIVATE_EVAL=<dir> with <dir>/cases.json ([{id, file, crop:[x,y,w,h]}]) and the source images in
 * <dir>/../private-eval; PRIVATE_EVAL_PHASE=<sub-folder> holds one reply per case (<id>.json), exactly
 * as an outside model wrote it. Each reply goes through the app's import (validate, auto-fix,
 * auto-wire), is rendered with sample data, checked by DesignRules and set beside the source crop.
 * Output: <dir>/<phase>-out/<id>.png and report.md.
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35])
class PrivateEvalTest {
    private val app = ApplicationProvider.getApplicationContext<Application>()

    @Test
    fun privateEval() {
        val root = System.getenv("PRIVATE_EVAL")?.let(::File)?.takeIf { it.isDirectory } ?: return
        val phase = System.getenv("PRIVATE_EVAL_PHASE") ?: "before"
        val images = File(root.parentFile, "private-eval")
        val out = File(root, "$phase-out").apply { mkdirs() }
        val cases = Json.parseToJsonElement(File(root, "cases.json").readText()).jsonArray
        val renderer = SpecRenderer(app)
        val zone = ZoneId.of("Africa/Cairo")
        val now = Instant.parse("2026-11-12T08:30:00Z")
        val rows = mutableListOf("| Case | Import | Widgets | Size | Live | Interactive | Alive | Correct | Auto-wired | Problems |", "|---|---|---|---|---|---|---|---|---|---|")
        val summary = mutableListOf<String>()
        val pairs = mutableListOf<Bitmap>()
        for (entry in cases) {
            val case = entry.jsonObject
            val id = case.getValue("id").jsonPrimitive.content
            val reply = File(root, "$phase/$id.json").takeIf { it.exists() }?.readText() ?: continue
            val crop = case.getValue("crop").jsonArray.map { it.jsonPrimitive.int }
            val source = BitmapFactory.decodeFile(File(images, case.getValue("file").jsonPrimitive.content).path)
            val cropped = Bitmap.createBitmap(source, crop[0], crop[1], crop[2], crop[3])
            val widgets = try {
                ExternalAI.importAll(reply).map { Triple(it.spec, it.autoWired, it.colors) }
            } catch (error: Exception) {
                rows += "| $id | ✗ | 0 | | | | | | | ${error.message?.replace("|", "/")?.replace("\n", " ")?.take(400)} |"
                summary += """{"id":"$id","imported":false}"""
                sideBySide(cropped, listOf(failed())).also { pairs += it; write(it, File(out, "$id.png")) }
                continue
            }
            val renders = mutableListOf<Bitmap>()
            for ((index, pair) in widgets.withIndex()) {
                val (spec, wired, colors) = pair
                val context = RenderContext(now = now, language = "en", zone = zone, data = DataSnapshot.sample(now, zone), tokenOverrides = colors)
                val size = spec.canvasSize()
                renders += renderer.render(spec, context, (size.first * 2).toInt(), (size.second * 2).toInt()).bitmap
                val report = DesignRules.check(spec)
                val s = report.scores
                val problems = report.findings.joinToString("; ") { "${it.rule.name.lowercase()}: ${it.element}" }.replace("|", "/")
                rows += "| $id${if (widgets.size > 1) "#${index + 1}" else ""} | ✓ | ${widgets.size} | ${spec.sizeLabel()} | ${pct(s["live"])} | ${pct(s["interactive"])} | ${pct(s["alive"])} | ${pct(s["correct"])} | ${wired.size} | ${problems.take(300)} |"
                summary += """{"id":"$id","imported":true,"live":${s["live"]},"interactive":${s["interactive"]},"alive":${s["alive"]},"correct":${s["correct"]}}"""
            }
            sideBySide(cropped, renders).also { pairs += it; write(it, File(out, "$id.png")) }
        }
        pairs.chunked(6).forEachIndexed { index, chunk -> write(sheet(chunk), File(out, "sheet-${index + 1}.png")) }
        File(out, "report.md").writeText(rows.joinToString("\n") + "\n")
        File(out, "summary.jsonl").writeText(summary.joinToString("\n") + "\n")
    }

    private fun WidgetSpec.canvasSize(): Pair<Float, Float> = family.width.toFloat() to family.height.toFloat()
    private fun WidgetSpec.sizeLabel(): String = family.name.lowercase()

    private fun pct(value: Double?) = value?.let { "%.0f".format(it * 100) } ?: ""

    private fun failed(): Bitmap = Bitmap.createBitmap(340, 340, Bitmap.Config.ARGB_8888).apply {
        Canvas(this).apply {
            drawColor(Color.rgb(250, 220, 220))
            drawText("import failed", 40f, 170f, Paint().apply { textSize = 36f; color = Color.RED })
        }
    }

    /** The source crop (left) and every render (right), all 340 px high, on a light gray sheet. */
    private fun sideBySide(left: Bitmap, rights: List<Bitmap>): Bitmap {
        val pad = 24
        val height = 340
        fun width(b: Bitmap) = b.width * height / b.height
        val total = pad + width(left) + rights.sumOf { pad + width(it) } + pad
        val sheet = Bitmap.createBitmap(total, height + pad * 2, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(sheet)
        canvas.drawColor(Color.rgb(200, 204, 210))
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        var x = pad
        for (b in listOf(left) + rights) {
            canvas.drawBitmap(b, null, Rect(x, pad, x + width(b), pad + height), paint)
            x += width(b) + pad
        }
        return sheet
    }

    /** Pairs stacked at 200 px high, for reviewing several at once. */
    private fun sheet(pairs: List<Bitmap>): Bitmap {
        val rowHeight = 200
        val width = pairs.maxOf { it.width * rowHeight / it.height }
        val sheet = Bitmap.createBitmap(width, rowHeight * pairs.size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(sheet)
        canvas.drawColor(Color.WHITE)
        pairs.forEachIndexed { i, b -> canvas.drawBitmap(b, null, Rect(0, i * rowHeight, b.width * rowHeight / b.height, (i + 1) * rowHeight), Paint(Paint.FILTER_BITMAP_FLAG)) }
        return sheet
    }

    private fun write(bitmap: Bitmap, file: File) {
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    @Suppress("unused")
    private fun JsonArray.ids() = map { it.jsonObject.getValue("id").jsonPrimitive.content }
}

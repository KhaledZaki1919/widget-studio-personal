package com.khaled.widgetstudio

import android.app.Application
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import androidx.test.core.app.ApplicationProvider
import com.khaled.widgetstudio.render.SpecRenderer
import com.khaled.widgetstudio.spec.DataSnapshot
import com.khaled.widgetstudio.spec.RenderContext
import com.khaled.widgetstudio.spec.TemplateLibrary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.time.Instant
import java.time.ZoneId
import kotlin.math.abs

/**
 * Every template rendered in Arabic and English with real fonts (Robolectric native graphics), at
 * the iOS snapshot tests' date, zone, data and scale (SnapshotSupport.swift), and set beside the
 * iOS reference (ios/WidgetStudioTests/Snapshots) with a similarity score. Writes to RENDER_OUT
 * (CI artifact android-renders).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35])
class TemplateRenderTest {
    private val app = ApplicationProvider.getApplicationContext<Application>()
    private val out = File(System.getenv("RENDER_OUT") ?: "build/renders")
    private val references = File("../../ios/WidgetStudioTests/Snapshots")

    @Test
    fun everyTemplateRendersAndIsComparedWithIos() {
        val renderer = SpecRenderer(app)
        val templates = TemplateLibrary(app.assets).all
        assertEquals("all 37 templates load from the shared assets", 37, templates.size)
        val zone = ZoneId.of("Africa/Cairo")
        val now = Instant.ofEpochSecond(1_792_580_700)
        val summary = mutableListOf("| Template | Language | Similarity to iOS |", "|---|---|---|")
        File(out, "templates").mkdirs()
        for (spec in templates) for (language in listOf("ar", "en")) {
            val context = RenderContext(now = now, language = language, zone = zone, data = DataSnapshot.sample(now, zone))
            val width = (spec.family.width * 2).toInt()
            val height = (spec.family.height * 2).toInt()
            val bitmap = renderer.render(spec, context, width, height).bitmap
            assertTrue("${spec.id} $language renders something", distinctColors(bitmap) > 1)
            val reference = File(references, "${spec.id}.$language.png").takeIf { it.exists() }?.let { BitmapFactory.decodeFile(it.path) }
            val score = reference?.let { similarity(it, bitmap) }
            summary += "| ${spec.id} | $language | ${score?.let { "%.0f %%".format(it * 100) } ?: "no reference"} |"
            write(if (reference != null) sideBySide(reference, bitmap) else bitmap, File(out, "templates/${spec.id}.$language.png"))
        }
        File(out, "templates/summary.md").writeText(summary.joinToString("\n") + "\n")
    }

    /** The hand-written test specs (every layer type, ADR-029's drawing tools in 14-xlarge-drawing) in both languages. */
    @Test
    fun everyTestSpecRenders() {
        val renderer = SpecRenderer(app)
        val zone = ZoneId.of("Africa/Cairo")
        val now = Instant.ofEpochSecond(1_792_580_700)
        File(out, "testspecs").mkdirs()
        val folder = File("../../ios/WidgetKitCore/Sources/WidgetKitCore/Resources/TestSpecs")
        for (file in folder.listFiles { f -> f.extension == "json" }.orEmpty().sortedBy { it.name }) {
            val spec = com.khaled.widgetstudio.spec.SpecParser.parse(file.readText())
            for (language in listOf("ar", "en")) {
                val context = RenderContext(now = now, language = language, zone = zone, data = DataSnapshot.sample(now, zone))
                val bitmap = renderer.render(spec, context, (spec.family.width * 2).toInt(), (spec.family.height * 2).toInt()).bitmap
                assertTrue("${spec.id} $language renders something", distinctColors(bitmap) > 1)
                write(bitmap, File(out, "testspecs/${spec.id}.$language.png"))
            }
        }
    }

    private fun distinctColors(bitmap: Bitmap): Int {
        val seen = HashSet<Int>()
        for (y in 0 until bitmap.height step 4) for (x in 0 until bitmap.width step 4) {
            seen += bitmap.getPixel(x, y)
            if (seen.size > 1) return seen.size
        }
        return seen.size
    }

    /** 1 − mean channel difference of both images scaled to 48×48 (1 = identical). */
    private fun similarity(a: Bitmap, b: Bitmap): Double {
        val sa = Bitmap.createScaledBitmap(a, 48, 48, true)
        val sb = Bitmap.createScaledBitmap(b, 48, 48, true)
        var total = 0.0
        for (y in 0 until 48) for (x in 0 until 48) {
            val p = sa.getPixel(x, y)
            val q = sb.getPixel(x, y)
            total += (abs(Color.red(p) - Color.red(q)) + abs(Color.green(p) - Color.green(q)) + abs(Color.blue(p) - Color.blue(q))) / (3 * 255.0)
        }
        return 1 - total / (48 * 48)
    }

    /** iOS (left) and Android (right) at the same height on a light gray sheet. */
    private fun sideBySide(left: Bitmap, right: Bitmap): Bitmap {
        val pad = 24
        val height = maxOf(left.height, right.height)
        val sheet = Bitmap.createBitmap(left.width + right.width + pad * 3, height + pad * 2, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(sheet)
        canvas.drawColor(Color.rgb(230, 232, 236))
        val paint = Paint(Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(left, null, Rect(pad, pad, pad + left.width, pad + left.height), paint)
        canvas.drawBitmap(right, null, Rect(pad * 2 + left.width, pad, pad * 2 + left.width + right.width, pad + right.height), paint)
        return sheet
    }

    private fun write(bitmap: Bitmap, file: File) {
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }
}

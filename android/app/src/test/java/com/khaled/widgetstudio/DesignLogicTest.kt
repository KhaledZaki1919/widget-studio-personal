package com.khaled.widgetstudio

import android.app.Application
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import androidx.test.core.app.ApplicationProvider
import com.khaled.widgetstudio.ai.AIError
import com.khaled.widgetstudio.ai.AIValidationError
import com.khaled.widgetstudio.ai.AIWidgetParser
import com.khaled.widgetstudio.ai.CardShape
import com.khaled.widgetstudio.ai.ExternalAI
import com.khaled.widgetstudio.widget.LiveUpdates.Source
import com.khaled.widgetstudio.ai.GeminiClient
import com.khaled.widgetstudio.ai.GenerationMode
import com.khaled.widgetstudio.ai.GenerationOptions
import com.khaled.widgetstudio.ai.WidgetDetector
import com.khaled.widgetstudio.ai.WidgetPrompt
import com.khaled.widgetstudio.data.CounterState
import com.khaled.widgetstudio.design.AILayoutFix
import com.khaled.widgetstudio.design.LayerEditing
import com.khaled.widgetstudio.design.SavedDesign
import com.khaled.widgetstudio.design.SpecValidator
import com.khaled.widgetstudio.render.Icons
import com.khaled.widgetstudio.spec.LText
import com.khaled.widgetstudio.spec.SpecParser
import com.khaled.widgetstudio.spec.SpecWriter
import com.khaled.widgetstudio.spec.TemplateLibrary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File
import java.time.LocalDate

/** The A2–A4 logic ported from Swift: validator, spec writer, designs, layer editing, counter, AI parsing, Gemini errors, detector. */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [35])
class DesignLogicTest {
    private val app = ApplicationProvider.getApplicationContext<Application>()
    private val fixtures = File("../../ios/WidgetKitCore/Tests/WidgetKitCoreTests/Fixtures/AI")
    private val templates by lazy { TemplateLibrary(app.assets).all }

    @Before
    fun loadIcons() {
        Icons(app.assets)
    }

    @Test
    fun everyTemplatePassesTheValidator() {
        for (spec in templates) assertEquals(spec.id, emptyList<String>(), SpecValidator(ai = false).validate(spec))
    }

    @Test
    fun specWriterRoundTripsEveryTemplate() {
        for (spec in templates) {
            val written = SpecWriter.write(spec)
            assertEquals(spec.id, written, SpecWriter.write(SpecParser.spec(written)))
        }
    }

    @Test
    fun savedDesignRoundTripsThroughJson() {
        val design = SavedDesign.new(templates.first(), "ar").copy(fieldValues = mapOf("title" to LText.Localized("Hi", "أهلًا")), colors = mapOf("accent" to "#FF0000"))
        val back = SavedDesign.fromJson(design.toJson())
        assertEquals(design.toJson(), back.toJson())
        assertEquals(design.name, back.name)
    }

    @Test
    fun layerEditingKeepsTextsWhenMovingAndGrouping() {
        val spec = templates.first { it.layers.size >= 3 }
        val texts = AILayoutFix.texts(spec)
        val moved = LayerEditing.move(emptyList(), 0, spec.layers.size - 1, spec.layers)
        assertEquals(spec.layers.size, moved.size)
        assertEquals(texts.sorted(), AILayoutFix.texts(spec.copy(layers = moved)).sorted())
        val grouped = LayerEditing.group(listOf(0, 1), spec.layers)
        if (grouped != null) {
            val (layers, index) = grouped
            assertEquals(texts.sorted(), AILayoutFix.texts(spec.copy(layers = layers)).sorted())
            val ungrouped = LayerEditing.ungroup(index, layers)
            assertEquals(texts.sorted(), AILayoutFix.texts(spec.copy(layers = ungrouped)).sorted())
        }
    }

    @Test
    fun tasbeehAdvancesAfter33() {
        val list = listOf("سبحان الله", "الحمد لله", "الله أكبر", "لا إله إلا الله")
        var state = CounterState()
        repeat(33) { state = state.increment(list) }
        assertEquals(0, state.index)
        assertEquals(33, state.count(list))
        // The tap after 33 moves to the next dhikr, counting from 1 (33 stays visible until then).
        state = state.increment(list)
        assertEquals(1, state.index)
        assertEquals(1, state.count(list))
        state = state.next(list).next(list).next(list)
        assertEquals(0, state.index)
    }

    @Test
    fun aiReplyParsesIntoAValidSpec() {
        val reply = File(fixtures, "spec-recreate.json").readText()
        val parsed = AIWidgetParser.parseWidget(reply, GenerationOptions(), "ai.test", enforceLayout = false)
        assertEquals("ai.test", parsed.spec.id)
        assertEquals(emptyList<String>(), SpecValidator(ai = true, checksTextOverlaps = false).validate(parsed.spec))
        assertTrue(parsed.colors.keys.containsAll(listOf("accent", "bg", "fg")))
        // Wrapped in prose and fences, as chat apps answer.
        val imported = ExternalAI.importWidget("Here you go:\n```json\n$reply\n```\nEnjoy!")
        assertEquals(parsed.spec.layers.size, imported.spec.layers.size)
    }

    @Test
    fun aiReplyErrorsAreReported() {
        try {
            AIWidgetParser.parseWidget("""{"palette":{"bg":"#000000","fg":"#111111","accent":"#FF0000"}}""", GenerationOptions(), "x")
            fail("expected a validation error")
        } catch (error: AIValidationError) {
            assertTrue(error.message, error.message?.contains("contrast") == true)
        }
        try {
            ExternalAI.importWidget("no json here")
            fail("expected NoJSON")
        } catch (error: ExternalAI.ImportError) {
            assertEquals(ExternalAI.ImportError.NoJSON, error)
        }
    }

    @Test
    fun promptAndInstructionsUseTheSharedExport() {
        val prompt = WidgetPrompt(app.assets)
        assertTrue(prompt.system.length > 2000)
        val request = prompt.request(GenerationOptions(size = "small"), com.khaled.widgetstudio.ai.PreparedImage(ByteArray(4), 10, 10))
        // ADR-029: the schema goes as structured output; the fallback puts it in the prompt.
        assertFalse(request.system.contains("JSON Schema"))
        assertTrue(request.schema?.contains("\"specVersion\"") == true)
        assertTrue(request.withSchemaInstructions().system.contains("JSON Schema"))
        assertTrue(ExternalAI.instructions(prompt, GenerationOptions()).contains("Child, one of") || ExternalAI.instructions(prompt, GenerationOptions()).contains("Layer, one of"))
        assertTrue(request.userText.contains("\"family\" must be \"small\""))
        val text = WidgetPrompt.userText(GenerationOptions(detectedCard = CardShape.CIRCLE, cropped = true, instructions = "<b>red</b>"), 300, 300, LocalDate.of(2026, 11, 3))
        assertTrue(text.contains("a circle"))
        assertTrue(text.contains("‹b›red‹/b›"))
        assertTrue(ExternalAI.instructions(prompt, GenerationOptions()).contains("Widget Studio"))
        assertFalse(WidgetPrompt.userText(GenerationOptions(mode = GenerationMode.PHOTO), 10, 10).contains("Do not use image layers"))
    }

    /** ADR-029: {"widgets": [...]} imports every widget; a v2 card keeps its shape and ratio; errors name their widget. */
    @Test
    fun multiWidgetRepliesAndV2Cards() {
        val example = WidgetPrompt(app.assets).example
        val two = ExternalAI.importAll("{\"specVersion\":2,\"widgets\":[$example,$example]}")
        assertEquals(2, two.size)
        val pill = example.replace("\"card\":{\"shape\":\"roundedRect\",\"aspect\":1,\"cornerRadius\":28}", "\"card\":{\"shape\":\"capsule\",\"aspect\":0.66,\"orientation\":\"vertical\"}")
        val spec = ExternalAI.importAll(pill).single().spec
        assertEquals("capsule", spec.card?.shape)
        assertEquals(170.0, spec.canvasHeight, 0.01)
        assertTrue(spec.canvasWidth < 115)
        val broken = example.replace("\"name\":{\"en\":\"Clock\"", "\"name\":{\"en\":\"Broken\"").replace("\"size\":14", "\"size\":3")
        try {
            ExternalAI.importAll("{\"specVersion\":2,\"widgets\":[$example,$broken]}")
            org.junit.Assert.fail("imported a broken widget")
        } catch (error: ExternalAI.ImportError.Invalid) {
            assertTrue(error.problems, error.problems.contains("Widget 2 «Broken»"))
            assertTrue(ExternalAI.fixRequest(error).contains("- Widget 2"))
        }
    }

    /** ADR-030: an event redraws only the widgets that read its data, and its delay is recorded. */
    @Test
    fun liveUpdatesTouchOnlyAffectedWidgets() {

        assertTrue(Source.BATTERY.affects(setOf("battery.level")))
        assertFalse(Source.VOLUME.affects(setOf("battery.level", "time.hh")))
        assertTrue(Source.TIME.affects(setOf("day.progress")))
        assertTrue(Source.SCREEN.affects(setOf("weather.temp")))
        assertTrue(Source.MEDIA.affects(setOf("media.title")) && !Source.MEDIA.affects(setOf("weather.temp")))
        val latency = com.khaled.widgetstudio.widget.UpdateLatency
        latency.changed(app, Source.BATTERY)
        latency.drawn(app, setOf("weather.temp"))
        assertTrue("an unrelated render doesn't close the event", latency.all(app)["battery"].isNullOrEmpty())
        latency.drawn(app, setOf("battery.level"))
        assertEquals(1, latency.all(app)["battery"]?.size)
    }

    @Test
    fun geminiRepliesAndErrorsMapLikeIos() {
        assertEquals("{\"ok\":true}", GeminiClient.parse(File(fixtures, "gemini-ok.json").readText()))
        assertEquals(AIError.DailyQuota, GeminiClient.mapError(429, File(fixtures, "gemini-429-daily.json").readText()))
        assertEquals(AIError.RateLimited, GeminiClient.mapError(429, File(fixtures, "gemini-429.json").readText()))
        assertEquals(AIError.Busy, GeminiClient.mapError(503, File(fixtures, "gemini-503.json").readText()))
        assertEquals(AIError.InvalidKey, GeminiClient.mapError(400, File(fixtures, "gemini-400-key.json").readText()))
        for (name in listOf("gemini-blocked.json", "gemini-image-safety.json")) {
            try { GeminiClient.parse(File(fixtures, name).readText()); fail(name) } catch (error: AIError) { assertEquals(name, AIError.Refused, error) }
        }
        try { GeminiClient.parse(File(fixtures, "gemini-max-tokens.json").readText()); fail("max tokens") } catch (error: AIError) { assertEquals(AIError.Truncated, error) }
    }

    @Test
    fun detectorFindsCardShapesOnAWallpaper() {
        val image = Bitmap.createBitmap(1000, 800, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(image)
        canvas.drawColor(Color.rgb(40, 90, 160))
        val card = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(250, 250, 250) }
        val text = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK; textSize = 40f }
        canvas.drawRoundRect(RectF(60f, 80f, 440f, 460f), 60f, 60f, card)
        canvas.drawText("12:30", 150f, 280f, text)
        canvas.drawCircle(730f, 270f, 190f, card)
        canvas.drawRoundRect(RectF(60f, 560f, 940f, 740f), 90f, 90f, card)
        val found = WidgetDetector.detect(image)
        assertEquals(found.toString(), 3, found.size)
        assertEquals(listOf(CardShape.ROUNDED_RECT, CardShape.CIRCLE, CardShape.CAPSULE), found.map { it.shape })
        assertEquals("medium", found[2].suggestedSize(image.width))
        val first = found[0].rect
        assertTrue(first.toString(), kotlin.math.abs(first.left - 60) < 12 && kotlin.math.abs(first.right - 440) < 12)
        assertNotNull(WidgetDetector.crop(image, first))
        assertEquals("#285AA0", WidgetDetector.wallpaperColor(image, first))
    }
}

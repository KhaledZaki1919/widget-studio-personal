package com.khaled.widgetstudio

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import com.khaled.widgetstudio.ai.AIWidgetParser
import com.khaled.widgetstudio.ai.BulkImport
import com.khaled.widgetstudio.ai.ExternalAI
import com.khaled.widgetstudio.ai.GenerationOptions
import com.khaled.widgetstudio.data.DeviceState
import com.khaled.widgetstudio.design.AutoWire
import com.khaled.widgetstudio.design.BindingCatalog
import com.khaled.widgetstudio.design.SpecValidator
import com.khaled.widgetstudio.render.Icons
import com.khaled.widgetstudio.spec.BindingResolver
import com.khaled.widgetstudio.spec.Capabilities
import com.khaled.widgetstudio.spec.DataSnapshot
import com.khaled.widgetstudio.spec.RenderContext
import com.khaled.widgetstudio.spec.SpecParser
import com.khaled.widgetstudio.spec.TemplateLibrary
import com.khaled.widgetstudio.spec.WiringScore
import com.khaled.widgetstudio.widget.ActionRouter
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File
import java.time.Instant
import java.time.ZoneId

/** The catalog is the single source of truth (ADR-027): these fail when something drifts or has no implementation. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CapabilityCatalogTest {
    private val app = ApplicationProvider.getApplicationContext<Application>()

    @Before
    fun load() {
        Icons(app.assets)
        Capabilities.load(app.assets)
    }

    @Test
    fun theCatalogLoads() {
        assertTrue("capabilities.json did not load", Capabilities.bindings.size > 80 && Capabilities.actions.size > 30)
        assertEquals(Capabilities.bindings.filter { !it.parametric }.map { it.id }.toSet(), BindingCatalog.catalog.keys)
    }

    @Test
    fun everyActionHasABranch() {
        val router = ActionRouter.inPlace + ActionRouter.opens
        for (action in Capabilities.actions) {
            when (action.supportAndroid) {
                "unsupported" -> Unit
                "panel" -> assertTrue("${action.id}: panel without a target", action.panel != null || action.id in router)
                else -> assertTrue("${action.id} is native on Android but ActionRouter has no branch", action.id in router)
            }
        }
        for (id in router) assertNotNull("ActionRouter handles unknown action $id", Capabilities.action(id))
    }

    @Test
    fun everyNativeBindingHasAProvider() {
        val core = listOf("time.", "date.", "tz.", "year.", "month.", "week.", "day.", "forecast.", "hourly.", "tasks.", "weather.", "steps.", "sleep.", "counter.", "stopwatch.", "focus.", "timer.", "prayer.", "qibla.", "location.", "field.", "days.", "media.", "battery.level")
        for (binding in Capabilities.bindings) {
            if (binding.supportAndroid == "unsupported") continue
            assertTrue("${binding.id} has no provider", binding.id in DeviceState.provided || core.any { binding.id.startsWith(it) })
        }
        for (id in DeviceState.provided) assertNotNull("DeviceState fills unknown binding $id", Capabilities.binding(id))
    }

    @Test
    fun theExportedPromptAndSchemaListEveryId() {
        val prompt = app.assets.open("spec/ai/system_prompt.md").bufferedReader().readText()
        val schema = app.assets.open("spec/ai/schema.recreate.json").bufferedReader().readText()
        for (binding in Capabilities.bindings) if (binding.ai) assertTrue("prompt misses ${binding.id}", prompt.contains("{{${binding.id}}}"))
        for (action in Capabilities.actions) {
            if (!action.ai) continue
            assertTrue("prompt misses ${action.id}", prompt.contains("`${action.id}`"))
            assertTrue("schema misses ${action.id}", schema.contains("\"${action.id}\""))
        }
    }

    @Test
    fun previewsResolveEveryBinding() {
        val now = Instant.parse("2026-11-04T10:00:00Z")
        val zone = ZoneId.of("Africa/Cairo")
        val spec = TemplateLibrary(app.assets).all.first()
        val resolver = BindingResolver(spec, RenderContext(now = now, zone = zone, data = DataSnapshot.sample(now, zone)))
        for (binding in Capabilities.bindings) {
            if (binding.parametric || binding.type == "image" || binding.id == "counter.progress") continue
            assertNotNull("${binding.id} resolves to nothing", resolver.value(binding.id))
        }
    }

    /** The best eval run's recorded replies through this app's parser and post-pass (WiringGateTests.swift). */
    @Test
    fun replayedWiringHoldsTheBestRun() {
        val folder = File("../../docs/ai-eval")
        val bestFile = File(folder, "wiring-best.json")
        if (!bestFile.exists()) return
        val best = Json.parseToJsonElement(bestFile.readText()).jsonObject
        val perCase = best.getValue("cases").jsonObject
        val cases = Json.parseToJsonElement(File(folder, "cases.json").readText()).jsonArray
        val scores = mutableListOf<Double>()
        val rules = mutableListOf<Map<String, Double>>()
        for (entry in cases) {
            val case = entry.jsonObject
            val wiring = (case["wiring"] as? JsonArray)?.map { it.jsonPrimitive.content } ?: continue
            val name = case.getValue("file").jsonPrimitive.content.removeSuffix(".png")
            val reply = File(folder, "recorded/$name.json").takeIf { it.exists() }?.readText() ?: continue
            val size = case.getValue("size").jsonPrimitive.content
            val parsed = AIWidgetParser.parseWidget(reply, GenerationOptions(size = size), "gate", enforceLayout = false)
            val score = WiringScore.hits(parsed.spec, wiring).size.toDouble() / wiring.size
            val floor = perCase[name]?.jsonPrimitive?.content?.toDoubleOrNull() ?: 0.0
            assertTrue("$name dropped to $score; missing ${wiring - WiringScore.hits(parsed.spec, wiring).toSet()}", score + 0.0001 >= floor)
            scores += score
            rules += com.khaled.widgetstudio.design.DesignRules.check(parsed.spec).scores
        }
        assertTrue(scores.isNotEmpty())
        // Each rule's mean must hold its best run (ADR-028): a drop in any one of the four fails CI.
        val metrics = best["metrics"] as? kotlinx.serialization.json.JsonObject
        for ((rule, floor) in metrics ?: emptyMap()) {
            val mean = rules.map { it[rule] ?: 1.0 }.average()
            assertTrue("$rule dropped to $mean, best run $floor", mean + 0.0001 >= floor.jsonPrimitive.content.toDouble())
        }
    }

    @Test
    fun bulkImportSplitsAndReadsZips() {
        val folder = File("../../ios/WidgetKitCore/Tests/WidgetKitCoreTests/Fixtures/Bulk")
        val names = BulkImport.zipEntries(File(folder, "nested.zip").readBytes()).map { it.name }.sorted()
        assertEquals(listOf("a.json", "deep/er/c.json", "deep/stored.json"), names)
        try {
            BulkImport.zipEntries(File(folder, "traversal.zip").readBytes())
            fail("a traversal path must fail the zip")
        } catch (error: ExternalAI.ImportError) {
            assertTrue(error is ExternalAI.ImportError.Invalid)
        }
        assertEquals(2, BulkImport.split("[{\"a\":1},{\"b\":2}]").size)
        assertEquals(1, BulkImport.split("{\"a\":\"}{\"}").size)
        assertEquals(2, BulkImport.split("{\"widgets\":[{\"layers\":[]},{\"layers\":[]}]}").size)
        val reply = File("../../ios/WidgetKitCore/Tests/WidgetKitCoreTests/Fixtures/AI/spec-recreate.json").readText()
        val summary = BulkImport.run(listOf(BulkImport.Source("1", reply), BulkImport.Source("2", reply), BulkImport.Source("3", "nope")), emptyList(), "en")
        assertEquals(1, summary.added.size)
        assertEquals(listOf("2"), summary.duplicates)
        assertEquals(listOf("3"), summary.failed.map { it.name })
    }

    @Test
    fun sharedAutoWireVectorsPass() {
        val file = File("../../ios/WidgetKitCore/Tests/WidgetKitCoreTests/Fixtures/AutoWire/vectors.json")
        val vectors = Json.parseToJsonElement(file.readText()).jsonArray
        assertTrue(vectors.size >= 8)
        for (entry in vectors) {
            val vector = entry.jsonObject
            val name = vector.getValue("name").jsonPrimitive.content
            val spec = SpecParser.spec(vector.getValue("spec").jsonObject)
            val inventory = (vector["inventory"] as? JsonArray)?.map { it.jsonPrimitive.content } ?: emptyList()
            val wiring = (vector["wiring"] as? JsonArray)?.map { line ->
                val entry = line.jsonObject
                AutoWire.WiringEntry(entry.getValue("element").jsonPrimitive.content, entry["shows"]?.jsonPrimitive?.content)
            } ?: emptyList()
            val outcome = AutoWire.apply(spec, inventory, wiring)
            val ids = WiringScore.ids(outcome.spec)
            for (id in vector.getValue("wired").jsonArray) assertTrue("$name: ${id.jsonPrimitive.content} missing; got $ids; log ${outcome.changes}", id.jsonPrimitive.content in ids)
            for (id in (vector["notWired"] as? JsonArray) ?: emptyList()) assertTrue("$name: ${id.jsonPrimitive.content} must not be wired; log ${outcome.changes}", id.jsonPrimitive.content !in ids)
            assertEquals(name, emptyList<String>(), SpecValidator(ai = true, checksTextOverlaps = false).validate(outcome.spec))
            assertEquals("$name: not idempotent", outcome.spec, AutoWire.apply(outcome.spec, inventory, wiring).spec)
        }
    }
}

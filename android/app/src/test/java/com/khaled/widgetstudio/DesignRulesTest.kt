package com.khaled.widgetstudio

import android.app.Application
import androidx.test.core.app.ApplicationProvider
import com.khaled.widgetstudio.design.AutoWire
import com.khaled.widgetstudio.design.DesignRules
import com.khaled.widgetstudio.spec.Capabilities
import com.khaled.widgetstudio.spec.SpecParser
import com.khaled.widgetstudio.spec.TemplateLibrary
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/** The four product rules (ADR-028): the shared vectors, and every template. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DesignRulesTest {
    private lateinit var library: TemplateLibrary

    @Before
    fun setUp() {
        val app = ApplicationProvider.getApplicationContext<Application>()
        Capabilities.load(app.assets)
        library = TemplateLibrary(app.assets)
    }

    @Test
    fun sharedVectorsFindWhatTheySay() {
        val vectors = Json.parseToJsonElement(File("../../ios/WidgetKitCore/Tests/WidgetKitCoreTests/Fixtures/DesignRules/vectors.json").readText()).jsonArray
        assertTrue(vectors.size >= 6)
        for (entry in vectors) {
            val vector = entry.jsonObject
            val spec = SpecParser.spec(vector.getValue("spec").jsonObject)
            val found = DesignRules.check(spec).findings
            assertEquals(vector.getValue("name").jsonPrimitive.content + ": " + found.map { it.element }, vector.getValue("findings").jsonArray.map { it.jsonPrimitive.content }.sorted(), found.map { it.rule.name.lowercase() }.sorted())
        }
    }

    @Test
    fun thePostPassClearsTheYearWidget() {
        val vectors = Json.parseToJsonElement(File("../../ios/WidgetKitCore/Tests/WidgetKitCoreTests/Fixtures/DesignRules/vectors.json").readText()).jsonArray
        val wired = AutoWire.apply(SpecParser.spec(vectors[0].jsonObject.getValue("spec").jsonObject)).spec
        assertEquals(emptyList<DesignRules.Finding>(), DesignRules.check(wired).findings)
    }

    /** Every template meets the rules: the audit, kept forever. */
    @Test
    fun everyTemplatePasses() {
        val problems = library.all.flatMap { spec -> DesignRules.check(spec).findings.map { spec.id + ": " + it.rule.name + " " + it.element } }
        assertEquals(emptyList<String>(), problems)
    }
}

package com.khaled.widgetstudio

import com.khaled.widgetstudio.spec.BindingResolver
import com.khaled.widgetstudio.spec.DataSnapshot
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.RenderContext
import com.khaled.widgetstudio.spec.SpecParser
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.time.Instant
import java.time.ZoneId

/** Every shared template and test spec (the iOS files, ADR-025) parses with only known layer types. */
class SpecParsingTest {
    private val kit = File("../../ios/WidgetKitCore/Sources/WidgetKitCore/Resources")

    private fun specs(folder: String) = File(kit, folder).listFiles { f -> f.extension == "json" }.orEmpty().sortedBy { it.name }

    @Test
    fun everyTemplateAndTestSpecParses() {
        val templates = specs("Templates")
        assertEquals("the 37 Mono templates", 37, templates.size)
        for (file in templates + specs("TestSpecs")) {
            val spec = SpecParser.parse(file.readText())
            val unknown = spec.layers.flatMap { it.flattened }.filter { it.content is LayerContent.Unknown }
            assertTrue("${file.name}: unknown layer types ${unknown.map { (it.content as LayerContent.Unknown).type }}", unknown.isEmpty())
        }
    }

    @Test
    fun bindingsMatchTheIosSampleData() {
        val spec = SpecParser.parse(File(kit, "Templates/mono.weather.temp.json").readText())
        val zone = ZoneId.of("Africa/Cairo")
        val now = Instant.ofEpochSecond(1_792_580_700)
        val resolver = BindingResolver(spec, RenderContext(now = now, language = "en", zone = zone, data = DataSnapshot.sample(now, zone)))
        assertEquals("30°", resolver.render("{{weather.temp}}°"))
        assertEquals("5,543", resolver.render("{{steps.today}}"))
        assertEquals("87", resolver.render("{{battery.level}}"))
        assertEquals("--", resolver.render("{{nothing.here}}"))
        assertEquals("GMT+3", resolver.render("{{tz.offset}}"))
    }
}

package com.khaled.widgetstudio

import com.khaled.widgetstudio.design.SpecValidator
import com.khaled.widgetstudio.spec.Background
import com.khaled.widgetstudio.spec.BindingResolver
import com.khaled.widgetstudio.spec.Capabilities
import com.khaled.widgetstudio.spec.DataSnapshot
import com.khaled.widgetstudio.spec.Family
import com.khaled.widgetstudio.spec.Frame
import com.khaled.widgetstudio.spec.LText
import com.khaled.widgetstudio.spec.Layer
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.RenderContext
import com.khaled.widgetstudio.spec.SpecExpression
import com.khaled.widgetstudio.spec.SpecParser
import com.khaled.widgetstudio.spec.SpecWriter
import com.khaled.widgetstudio.spec.Theme
import com.khaled.widgetstudio.spec.WeatherKind
import com.khaled.widgetstudio.spec.WidgetSpec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File
import java.time.Instant
import java.time.ZoneId

/** State layers and the values they read (ADR-028), the twin of StatesTests.swift. */
class StatesTest {
    private val cairo = ZoneId.of("Africa/Cairo")

    @Before
    fun catalog() {
        val file = listOf("ios/WidgetKitCore/Sources/WidgetKitCore/Resources/Spec/capabilities.json", "../ios/WidgetKitCore/Sources/WidgetKitCore/Resources/Spec/capabilities.json", "../../ios/WidgetKitCore/Sources/WidgetKitCore/Resources/Spec/capabilities.json")
            .map(::File).first { it.exists() }
        Capabilities.install(file.readText())
    }

    private fun spec(layers: List<Layer> = emptyList()) = WidgetSpec(1, "t", LText.Localized("t", "t"), Family.SMALL, Theme.DARK, "none", Background("solid", "#000000", null, null, null, null), emptyList(), layers, null)

    private fun resolver(now: String = "2026-11-05T10:00:00Z", data: DataSnapshot = DataSnapshot(), overrides: Map<String, String> = emptyMap()) =
        BindingResolver(spec(), RenderContext(now = Instant.parse(now), language = "en", zone = cairo, data = data, overrides = overrides))

    @Test
    fun conditionsCompareRealNumbers() {
        val low = resolver(overrides = mapOf("battery.level" to "0.2", "battery.charging" to "0"))
        assertTrue(low.isSatisfied("{{battery.level}} <= 0.2"))
        assertFalse(low.isSatisfied("{{battery.level}} > 0.2"))
        assertTrue(low.isSatisfied("{{battery.level}} in 0.1..0.3"))
        assertTrue(low.isSatisfied("!{{battery.charging}} && {{battery.level}} < 0.5"))
        assertTrue(low.isSatisfied("{{battery.charging}} || {{battery.level}} < 0.5"))
        assertFalse(resolver().isSatisfied("{{battery.level}} <= 0.2"))
        assertFalse(resolver().isSatisfied("{{weather.kind}} != rain"))
        assertNull(SpecExpression.parse("{{a}} && nothing"))
        assertEquals(listOf(2, 1), SpecExpression.parse("{{a}} && {{b}} || {{c}}")?.groups?.map { it.size })
    }

    @Test
    fun yearProgressOnTheOwnersDate() {
        val resolver = resolver()
        val value = resolver.value("year.progress") as BindingResolver.Value.Number
        assertEquals(0.846, value.value, 0.002)
        assertEquals("85%", resolver.render("{{year.progress}}%"))
        assertEquals("309", resolver.render("{{year.day}}"))
        assertEquals("56", resolver.render("{{year.daysLeft}}"))
        assertEquals("25", resolver.render("{{month.daysLeft}}"))
        assertEquals("15", resolver.render("{{month.progress}}"))
        assertEquals("50", resolver.render("{{day.progress}}"))
    }

    @Test
    fun leapYearAndEdges() {
        assertEquals("366", resolver("2028-12-31T12:00:00Z").render("{{year.day}}"))
        assertEquals("0", resolver("2026-12-31T12:00:00Z").render("{{year.daysLeft}}"))
    }

    /** The bug the owner reported: 15 of 48 dots on Nov 5. The lit count must be the bound share. */
    @Test
    fun dotsMatchTheBoundValue() {
        assertEquals(41, resolver().gridLevels("{{year.progress}}", 48).count { it > 0 })
        assertEquals(338, resolver().gridLevels("{{year.progress}}", 400).count { it > 0 })
    }

    @Test
    fun batteryMoodThresholds() {
        val states = LayerContent.States("battery.mood", null, "@fg", "@accent", "@dim", null, null)
        fun mood(level: String, charging: String = "0") = resolver(overrides = mapOf("battery.level" to level, "battery.charging" to charging)).variant(states)?.id
        assertEquals("charging", mood("0.05", "1"))
        assertEquals("full", mood("0.9"))
        assertEquals("normal", mood("0.89"))
        assertEquals("normal", mood("0.5"))
        assertEquals("worried", mood("0.49"))
        assertEquals("worried", mood("0.21"))
        assertEquals("sad", mood("0.2"))
    }

    @Test
    fun everySetIsDrawableAndItsSamplesSelectIt() {
        assertTrue(Capabilities.stateSets.size >= 8)
        for (set in Capabilities.stateSets) {
            val states = LayerContent.States(set.id, set.value, "@fg", "@accent", "@dim", null, null)
            assertEquals(set.id, set.variants.size, states.expanded.size)
            for (variant in states.expanded) {
                assertTrue("${set.id}.${variant.id} draws nothing", variant.layers.isNotEmpty())
                val overrides = resolver().overrides(variant)
                assertEquals(set.id, variant.id, resolver(overrides = overrides).variant(states)?.id)
            }
            val layer = Layer(Frame(0.0, 0.0, 100.0, 100.0), null, null, null, null, states)
            val issues = SpecValidator(ai = false).validate(spec(listOf(layer)))
            assertTrue("${set.id}: $issues", issues.isEmpty())
        }
    }

    @Test
    fun roundTrip() {
        val text = """{"schemaVersion":1,"id":"t","name":{"en":"t","ar":"t"},"family":"small","background":{"type":"solid","color":"#000000"},"layers":[{"type":"states","frame":{"x":0,"y":0,"w":50,"h":50},"set":"weather.art"}]}"""
        val spec = SpecParser.parse(text)
        assertEquals(spec, SpecParser.spec(SpecWriter.write(spec)))
        assertNotNull(spec.layers[0].content as? LayerContent.States)
    }

    @Test
    fun weatherKinds() {
        assertEquals("clear", WeatherKind.of("moon.stars.fill"))
        assertEquals("partlyCloudy", WeatherKind.of("cloud.moon.fill"))
        assertEquals("storm", WeatherKind.of("cloud.bolt.rain.fill"))
    }
}

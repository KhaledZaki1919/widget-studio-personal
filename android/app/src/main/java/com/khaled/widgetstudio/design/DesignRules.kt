package com.khaled.widgetstudio.design

import com.khaled.widgetstudio.spec.Bindings
import com.khaled.widgetstudio.spec.Capabilities
import com.khaled.widgetstudio.spec.Frame
import com.khaled.widgetstudio.spec.LText
import com.khaled.widgetstudio.spec.Layer
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.WidgetSpec
import kotlin.math.abs

/**
 * The four product rules as generic detectors (DesignRules.swift, ADR-028): they know shapes of
 * problems, never a widget. What they still find after the post-pass goes in the Interactive
 * summary, and the eval scores each rule from the same counts. Templates must come out clean.
 * Both ports run Fixtures/DesignRules/vectors.json.
 */
object DesignRules {
    enum class Rule { LIVE, INTERACTIVE, ALIVE, CORRECT }

    data class Finding(val rule: Rule, val path: List<Int>, val element: String, val message: LText)

    data class Report(val findings: List<Finding>, val checked: Map<Rule, Int>) {
        /** The share of checked elements that passed, 0…1; 1 when nothing applies. */
        fun score(rule: Rule): Double {
            val total = checked[rule] ?: 0
            if (total == 0) return 1.0
            return (1 - findings.count { it.rule == rule }.toDouble() / total).coerceAtLeast(0.0)
        }

        val scores: Map<String, Double> get() = Rule.entries.associate { it.name.lowercase() to score(it) }
    }

    private val frozen = LText.Localized("A fixed value that should change. Nothing near it says what it shows.", "قيمة ثابتة يفترض أن تتغير، ولا شيء بجوارها يوضح ما تعرضه.")
    private val frozenLevel = LText.Localized("A level drawn at a fixed value.", "مستوى مرسوم بقيمة ثابتة.")
    private val noAction = LText.Localized("Looks like a control but does nothing.", "يبدو كزر لكنه لا يفعل شيئًا.")
    private val oneLook = LText.Localized("Shows one look only, though it should change with the state.", "يعرض شكلًا واحدًا رغم أنه يجب أن يتغير مع الحالة.")
    private val mismatch = LText.Localized("The picture and the value disagree.", "الرسم لا يطابق القيمة.")
    private val labelSays = LText.Localized("The label beside it names something else.", "العنوان بجواره يدل على شيء آخر.")
    private val batteryUnsaid = LText.Localized("Shows the battery, but nothing on the card says so.", "يعرض البطارية، لكن لا شيء في البطاقة يدل على ذلك.")

    private class Tally {
        val findings = mutableListOf<Finding>()
        val checked = mutableMapOf<Rule, Int>()

        fun pass(rule: Rule) {
            checked[rule] = (checked[rule] ?: 0) + 1
        }

        fun fail(rule: Rule, item: AutoWire.Found, element: String, message: LText) {
            pass(rule)
            findings += Finding(rule, item.path, element, message)
        }
    }

    fun check(spec: WidgetSpec): Report {
        val run = AutoWire.Run(spec, emptyList())
        val tally = Tally()
        val items = AutoWire.walk(spec.layers)
        val buttons = items.mapNotNull { item -> (item.layer.content as? LayerContent.Button)?.let { item.frame to it.action } }
        fun hasAction(frame: Frame) = buttons.any { it.second != "open.app" && AutoWire.inside(frame, it.first) }
        if (run.topics.has("battery")) {
            spec.layers.forEachIndexed { index, layer ->
                if (run.faceParts(index, spec.layers) != null) tally.fail(Rule.ALIVE, AutoWire.Found(listOf(index), layer, layer.frame, null), "face", oneLook)
            }
        }
        for (item in items) {
            when (val c = item.layer.content) {
                is LayerContent.Text -> checkText(c, item, run, tally, ::hasAction)
                is LayerContent.Ring -> checkLevel(c.progress, item, run, tally, "ring")
                is LayerContent.ProgressBar -> checkLevel(c.progress, item, run, tally, "progressBar")
                is LayerContent.DotGrid -> checkDots(c, item, run, tally)
                is LayerContent.Icon -> checkIcon(c, item, run, tally, ::hasAction)
                is LayerContent.Shape -> checkSwitch(item, run, tally, ::hasAction)
                is LayerContent.ListL -> checkList(c, item, tally, ::hasAction)
                is LayerContent.States -> tally.pass(Rule.ALIVE)
                is LayerContent.ForecastRow, is LayerContent.AnalogClock, is LayerContent.CalendarMonth -> tally.pass(Rule.LIVE)
                else -> Unit
            }
        }
        return Report(tally.findings, tally.checked)
    }

    /** What text looks like when it is really a value: the shapes the post-pass binds. */
    fun looksChanging(text: String): Boolean = AutoWire.TextShape.run {
        isClock(text) || isPercent(text) || isTemperature(text) || isStepCount(text) || percentLabel(text) != null || dateTemplate(text) != null
    }

    private fun checkText(text: LayerContent.Text, item: AutoWire.Found, run: AutoWire.Run, tally: Tally, hasAction: (Frame) -> Boolean) {
        val english = text.value.resolved("en").trim()
        val glyph = english.replace("︎", "").replace("️", "")
        val set = Capabilities.stateSets.firstOrNull { glyph in it.glyphs }
        if (set?.topic != null && run.topics.has(set.topic)) tally.fail(Rule.ALIVE, item, english, oneLook)
        if (Capabilities.actions.any { glyph in it.glyphs }) {
            if (hasAction(item.frame)) tally.pass(Rule.INTERACTIVE) else tally.fail(Rule.INTERACTIVE, item, english, noAction)
        }
        if (text.liveKind != null) {
            tally.pass(Rule.LIVE)
            return
        }
        val names = AutoWire.names(english)
        if (names.isEmpty()) {
            if (looksChanging(english)) tally.fail(Rule.LIVE, item, english, frozen)
            return
        }
        if (names.any { !it.startsWith("field.") }) tally.pass(Rule.LIVE)
        checkBound(item, run, tally, english)
    }

    /** A share beside a label that names another, or the battery with nothing to say so. */
    private fun checkBound(item: AutoWire.Found, run: AutoWire.Run, tally: Tally, element: String) {
        val (current, kind) = run.boundShare(item.layer) ?: return
        val own = run.words(item.layer)
        val named = run.namedShare(item, kind, own)
        when {
            named != null && named != current.id && !run.isNamed(current, item, own) -> tally.fail(Rule.CORRECT, item, element, labelSays)
            current.id == "battery.level" && !run.isNamed(current, item, own) && !run.topics.has("battery") && !run.uses("battery.symbol") -> tally.fail(Rule.CORRECT, item, element, batteryUnsaid)
            else -> tally.pass(Rule.CORRECT)
        }
    }

    /** The nearest percent a text states or shows: the share as text says it, and whether it is live. */
    private fun statedPercent(item: AutoWire.Found, run: AutoWire.Run): Pair<Double?, Boolean>? {
        for (other in run.neighbors(item)) {
            val text = other.layer.content as? LayerContent.Text ?: continue
            val english = text.value.resolved("en").trim()
            if (AutoWire.names(english).any { Capabilities.binding(it)?.isShare == true }) return null to true
            if (!AutoWire.TextShape.isPercent(english) && AutoWire.TextShape.percentLabel(english) == null) continue
            val number = Regex("[0-9]{1,3}(?=\\s*[%٪]$)").find(english)?.value?.toDoubleOrNull() ?: continue
            return number / 100 to false
        }
        return null
    }

    private fun checkLevel(value: String, item: AutoWire.Found, run: AutoWire.Run, tally: Tally, kind: String) {
        if (Bindings.soleBinding(value) != null) {
            tally.pass(Rule.LIVE)
            checkBound(item, run, tally, kind)
            return
        }
        // A bar that never moves (a full track, an empty one) is drawing, not data.
        val number = value.toDoubleOrNull() ?: return
        if (number <= 0 || number >= 1) return
        tally.fail(Rule.LIVE, item, kind, frozenLevel)
        checkVisual(number, item, run, tally, kind)
    }

    private fun checkVisual(share: Double, item: AutoWire.Found, run: AutoWire.Run, tally: Tally, element: String) {
        val (stated, live) = statedPercent(item, run) ?: return
        if (live || abs((stated ?: share) - share) > 0.05) tally.fail(Rule.CORRECT, item, element, mismatch) else tally.pass(Rule.CORRECT)
    }

    private fun checkDots(grid: LayerContent.DotGrid, item: AutoWire.Found, run: AutoWire.Run, tally: Tally) {
        if (Bindings.soleBinding(grid.values) != null) {
            tally.pass(Rule.LIVE)
            checkBound(item, run, tally, "dots")
            return
        }
        val digits = grid.values.filter { it == '0' || it == '1' }
        if ('0' !in digits || '1' !in digits) return
        if (run.isFillPattern(grid)) {
            tally.fail(Rule.LIVE, item, "dots", frozenLevel)
            checkVisual(digits.count { it == '1' }.toDouble() / digits.length, item, run, tally, "dots")
        } else if (grid.rows >= 8 && grid.cols >= 8 && run.artSet(item) != null) {
            tally.fail(Rule.ALIVE, item, "dots", oneLook)
        }
    }

    private fun checkIcon(icon: LayerContent.Icon, item: AutoWire.Found, run: AutoWire.Run, tally: Tally, hasAction: (Frame) -> Boolean) {
        val bound = Bindings.soleBinding(icon.symbol)
        if (bound != null) {
            tally.pass(Rule.ALIVE)
        } else {
            // Only on a card that shows that topic: a sun beside a prayer time isn't the weather.
            val state = Capabilities.bindings.firstOrNull { it.type == "symbol" && !it.id.startsWith("forecast.") && icon.symbol in it.icons && run.showsTopic(it.prefix) }
            if (state != null && !(state.id == "volume.symbol" && run.topics.value("media") >= run.topics.value("volume")) && item.frame.w >= 16) {
                tally.fail(Rule.ALIVE, item, icon.symbol, oneLook)
                if (state.id == "weather.symbol" && run.uses("weather.cond")) tally.fail(Rule.CORRECT, item, icon.symbol, mismatch)
            }
        }
        val symbol = bound?.let { raw -> Capabilities.binding(raw)?.icons?.firstOrNull { candidate -> Capabilities.actions.any { candidate in it.icons } } } ?: icon.symbol
        val tile = run.tile(item.frame)
        val area = tile ?: Frame(item.frame.x - 20, item.frame.y - 20, item.frame.w + 40, item.frame.h + 40)
        val action = run.actionFor(listOf(symbol), run.labels(area), tile != null) ?: return
        if (action.id in setOf("media.open", "calendar.open", "weather.open", "compass.open", "reminders.open")) return
        if (tile == null && (action.group == "open" || action.id in setOf("volume.up", "volume.down", "brightness.up", "brightness.down"))) return
        // The icon's own button, or one over the tile it sits on.
        if (hasAction(item.frame) || (tile != null && hasAction(tile))) tally.pass(Rule.INTERACTIVE) else tally.fail(Rule.INTERACTIVE, item, icon.symbol, noAction)
    }

    /** A pill with a round knob is a switch: it needs a tap, and a look for each state. */
    private fun checkSwitch(item: AutoWire.Found, run: AutoWire.Run, tally: Tally, hasAction: (Frame) -> Boolean) {
        val track = item.layer.content as? LayerContent.Shape ?: return
        val f = item.frame
        if (item.path.size != 1 || (track.kind != "capsule" && track.kind != "roundedRect") || item.layer.condition != null) return
        if (f.w < 1.4 * f.h || f.h > 70 || f.h < 14) return
        val knobs = run.spec.layers.filter { layer ->
            (layer.content as? LayerContent.Shape)?.kind == "circle" && AutoWire.inside(layer.frame, f) && layer.frame.h >= 0.5 * f.h
        }
        if (knobs.isEmpty()) return
        if (hasAction(f)) tally.pass(Rule.INTERACTIVE) else tally.fail(Rule.INTERACTIVE, item, "switch", noAction)
        // A Shortcut has no state to read, so it has only one look to show.
        val action = run.spec.layers.firstNotNullOfOrNull { layer ->
            (layer.content as? LayerContent.Button)?.takeIf { AutoWire.inside(f, layer.frame) }?.let { Capabilities.action(it.action) }
        }
        if (knobs.any { it.condition != null } || (action != null && action.state == null)) tally.pass(Rule.ALIVE) else tally.fail(Rule.ALIVE, item, "switch", oneLook)
    }

    private fun checkList(list: LayerContent.ListL, item: AutoWire.Found, tally: Tally, hasAction: (Frame) -> Boolean) {
        val height = item.frame.h / maxOf(list.items.size, 1)
        for ((index, row) in list.items.withIndex()) {
            val detail = row.detail?.resolved("en")?.trim() ?: ""
            if (row.done != null) {
                val frame = Frame(item.frame.x, item.frame.y + index * height, item.frame.w, height)
                if (hasAction(frame)) tally.pass(Rule.INTERACTIVE) else tally.fail(Rule.INTERACTIVE, item, "checkbox", noAction)
                tally.pass(Rule.ALIVE)
            }
            if (AutoWire.names(row.title.resolved("en")).isNotEmpty() || AutoWire.names(detail).isNotEmpty()) tally.pass(Rule.LIVE)
            else if (AutoWire.TextShape.isClock(detail)) tally.fail(Rule.LIVE, item, detail, frozen)
        }
    }
}

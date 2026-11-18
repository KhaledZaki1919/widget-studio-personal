package com.khaled.widgetstudio.design

import com.khaled.widgetstudio.spec.Bindings
import com.khaled.widgetstudio.spec.BindingNames
import com.khaled.widgetstudio.spec.Capabilities
import com.khaled.widgetstudio.spec.Capability
import com.khaled.widgetstudio.spec.FieldSpec
import com.khaled.widgetstudio.spec.Frame
import com.khaled.widgetstudio.spec.LText
import com.khaled.widgetstudio.spec.Layer
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.WidgetSpec
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * The post-pass after AI output and imports (AutoWire.swift, ADR-027): static text that looks live
 * gets a binding, control-like layers get a button by icon and nearby text using the catalog's
 * keywords, static progress gets the matching binding, drawn sliders become a level bar with up/down
 * zones. Both ports run the vectors in Tests/WidgetKitCoreTests/Fixtures/AutoWire.
 */
object AutoWire {
    data class Outcome(val spec: WidgetSpec, val changes: List<String>)

    /** One line of the model's wiring list: what it said an element shows. */
    data class WiringEntry(val element: String, val shows: String?)

    fun apply(spec: WidgetSpec, inventory: List<String> = emptyList(), wiring: List<WiringEntry> = emptyList()): Outcome {
        val run = Run(spec, inventory)
        run.sliders()
        run.modelWiring(wiring)
        run.forecastRows()
        run.texts()
        run.listRows()
        run.mediaTitles()
        run.symbols()
        run.stateSets()
        run.progress()
        run.correctShares()
        run.toggles()
        run.controls()
        run.sliderZones()
        run.stateLooks()
        run.card()
        run.dropUnusedFields()
        return Outcome(run.spec, run.changes.toList())
    }

    /** The binding names in a text. */
    fun names(text: String): List<String> = Bindings.tokenize(text).filterIsInstance<Bindings.Token.Binding>().map { it.name.trim() }

    /** Whole-word match for Latin keywords, substring for Arabic. [corpus] is lowercased. */
    fun occurs(keyword: String, corpus: String): Boolean {
        val word = keyword.lowercase()
        if (!word.all { it.code < 128 }) return corpus.contains(word)
        var from = 0
        while (true) {
            val found = corpus.indexOf(word, from)
            if (found < 0) return false
            val before = if (found > 0) corpus[found - 1] else ' '
            val end = found + word.length
            val after = if (end < corpus.length) corpus[end] else ' '
            if (!before.isLetter() && !after.isLetter()) return true
            from = end
        }
    }

    class Topics(corpus: String, icons: Set<String>) {
        val score = mutableMapOf<String, Int>()

        init {
            for (capability in Capabilities.bindings + Capabilities.actions) {
                val hits = capability.keywords.count { occurs(it, corpus) } + 2 * capability.icons.count { it in icons }
                if (hits > 0) score[capability.prefix] = (score[capability.prefix] ?: 0) + hits
            }
        }

        fun has(prefix: String) = value(prefix) > 0
        fun value(prefix: String) = score[prefix] ?: 0

        fun best(vararg prefixes: String): String? {
            var result: String? = null
            for (prefix in prefixes) if (has(prefix) && value(prefix) > (result?.let(::value) ?: 0)) result = prefix
            return result
        }
    }

    /** Pure recognizers for a single text; the tests pin them. */
    object TextShape {
        private val weekdays = listOf("sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "الأحد", "الاثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت")
        private val shortDays = listOf("sun", "mon", "tue", "wed", "thu", "fri", "sat")
        private val months = listOf("january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december")
        private val shortMonths = listOf("jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec")
        private val clock = Regex("^[0-2]?[0-9]:[0-5][0-9](:[0-5][0-9])?\\s*([AaPp]\\.?[Mm]\\.?|ص|م)?$")
        private val meridiem = Regex("([AaPp]\\.?[Mm]\\.?|ص|م)$")
        private val percent = Regex("^[0-9]{1,3}\\s*[%٪]$")
        private val temperature = Regex("^-?[0-9]{1,3}\\s*°\\s*[CFcfمف]?$")
        private val hours = Regex("^[0-9]{1,3}\\s*([hH]|hr|hrs|س)\\s*([0-9]{1,2}\\s*([mM]|min|mins|د))?$")
        private val minutes = Regex("^[0-9]{1,3}\\s*(min|mins|m|د)$")
        private val stepCount = Regex("^[0-9]{1,3}(,[0-9]{3})+$")

        private val labelled = Regex("^.*[^0-9٠-٩\\s]\\s*[0-9٠-٩]{1,3}\\s*[%٪]$")
        private val tail = Regex("\\s*[0-9٠-٩]{1,3}\\s*[%٪]$")
        private val tailNumber = Regex("[0-9٠-٩]{1,3}(?=\\s*[%٪]$)")

        /** `Year 53%` → `Year`; null unless a label comes before the percent. */
        fun percentLabel(text: String): String? = if (labelled.containsMatchIn(text)) text.replace(tail, "") else null

        /** The number of a percent replaced by a binding, in either language's digits. */
        fun replacingPercent(text: String, id: String) = text.replace(tailNumber) { "{{$id}}" }

        fun isDayName(text: String) = text.lowercase().let { it in shortDays || it in weekdays }
        fun isToday(text: String) = text.lowercase() in listOf("today", "now", "اليوم", "الآن")

        fun isClock(text: String) = clock.containsMatchIn(text)
        fun hasMeridiem(text: String) = meridiem.containsMatchIn(text)
        fun isPercent(text: String) = percent.containsMatchIn(text)
        fun isTemperature(text: String) = temperature.containsMatchIn(text)
        fun isDuration(text: String) = hours.containsMatchIn(text) || minutes.containsMatchIn(text)
        fun isStepCount(text: String) = stepCount.containsMatchIn(text)

        fun dateTemplate(text: String): String? {
            val words = text.split(" ", ",").filter { it.isNotEmpty() }.map { it.lowercase() }
            if (words.isEmpty() || words.size > 4) return null
            var named = false
            val parts = mutableListOf<String>()
            for (word in words) {
                val number = word.toIntOrNull()
                when {
                    word in weekdays -> { parts += "{{date.EEEE}}"; named = true }
                    word in shortDays -> { parts += "{{date.EEE}}"; named = true }
                    word in months -> { parts += "{{date.MMMM}}"; named = true }
                    word in shortMonths -> { parts += "{{date.MMM}}"; named = true }
                    number != null && number in 1..31 -> parts += "{{date.d}}"
                    number != null && number in 1900..2100 -> parts += "{{date.yyyy}}"
                    else -> return null
                }
            }
            return if (named) parts.joinToString(" ") else null
        }
    }

    /** Where a stack's child sits, estimated: natural sizes along the axis, spacers take the rest. */
    fun childFrames(stack: LayerContent.Stack, frame: Frame): List<Frame> {
        if (stack.axis == "grid") {
            val columns = max(stack.columns ?: 2, 1)
            val rows = max(ceil(stack.children.size.toDouble() / columns).toInt(), 1)
            val width = frame.w / columns
            val height = frame.h / rows
            return stack.children.indices.map { Frame(frame.x + (it % columns) * width, frame.y + (it / columns) * height, width, height) }
        }
        val horizontal = stack.axis == "horizontal"
        val padding = stack.padding ?: 0.0
        val spacing = stack.spacing ?: 4.0
        val length = (if (horizontal) frame.w else frame.h) - 2 * padding
        fun natural(child: Layer): Double {
            val given = if (horizontal) child.frame.w else child.frame.h
            if (given > 0) return given
            return when (val c = child.content) {
                is LayerContent.Icon -> c.size
                is LayerContent.Text -> if (horizontal) c.value.resolved("en").length * c.font.size * 0.6 else c.font.size * 1.25
                is LayerContent.Spacer -> 0.0
                else -> 20.0
            }
        }
        val sizes = stack.children.map(::natural)
        val spacers = stack.children.count { it.content is LayerContent.Spacer }
        val used = sizes.sum() + spacing * max(stack.children.size - 1, 0)
        val free = max(length - used, 0.0)
        var cursor = padding
        if (spacers == 0) {
            when (stack.justify) {
                "center" -> cursor += free / 2
                "end" -> cursor += free
            }
        }
        return stack.children.mapIndexed { index, child ->
            val size = if (child.content is LayerContent.Spacer) free / max(spacers, 1) else sizes[index]
            val result = if (horizontal) Frame(frame.x + cursor, frame.y, size, frame.h) else Frame(frame.x, frame.y + cursor, frame.w, size)
            cursor += size + spacing
            result
        }
    }

    /** One layer found while walking the spec, with its path and estimated frame. */
    data class Found(val path: List<Int>, val layer: Layer, val frame: Frame, val mirror: Boolean?)

    fun walk(layers: List<Layer>, base: List<Int> = emptyList(), inherited: List<Frame>? = null, mirror: Boolean? = null): List<Found> {
        val found = mutableListOf<Found>()
        layers.forEachIndexed { index, layer ->
            val frame = inherited?.getOrNull(index) ?: layer.frame
            val path = base + index
            val mirrored = if (base.isEmpty()) layer.mirror else mirror
            found += Found(path, layer, frame, mirrored)
            (layer.content as? LayerContent.Stack)?.let { stack ->
                found += walk(stack.children, path, childFrames(stack, frame), mirrored)
            }
        }
        return found
    }

    fun inside(inner: Frame, outer: Frame): Boolean {
        val x = inner.x + inner.w / 2
        val y = inner.y + inner.h / 2
        return x >= outer.x && x <= outer.x + outer.w && y >= outer.y && y <= outer.y + outer.h
    }

    internal data class Planned(val frame: Frame, val action: Capability, val mirror: Boolean?, val element: String)

    internal class Run(var spec: WidgetSpec, inventory: List<String>) {
        val changes = mutableListOf<String>()
        val replacedFields = mutableSetOf<String>()
        val width = spec.family.width
        val height = spec.family.height
        val topics: Topics

        init {
            val words = mutableListOf<String>()
            words += spec.name.allValues
            words += inventory
            val icons = mutableSetOf<String>()
            for (layer in spec.layers.flatMap { it.flattened }) {
                when (val c = layer.content) {
                    is LayerContent.Text -> words += c.value.allValues.filter { !it.contains("{{") }
                    is LayerContent.Icon -> icons += c.symbol
                    is LayerContent.ListL -> words += c.items.flatMap { it.title.allValues }
                    else -> Unit
                }
            }
            for (field in spec.fields) {
                words += field.key
                words += field.label.allValues
                words += field.default?.allValues ?: emptyList()
            }
            topics = Topics(words.joinToString("\n").lowercase(), icons)
        }

        val systemIcons: Int
            get() = spec.layers.flatMap { it.flattened }.count { layer ->
                val icon = layer.content as? LayerContent.Icon ?: return@count false
                Capabilities.actions.any { it.id.startsWith("system.toggle") && icon.symbol in it.icons }
            }

        val hasControls: Boolean
            get() = spec.layers.flatMap { it.flattened }.any { layer ->
                val icon = layer.content as? LayerContent.Icon ?: return@any false
                Capabilities.actions.any { it.group == "media" && icon.symbol in it.icons }
            }

        fun uses(binding: String) = binding in BindingNames.names(spec)

        fun text(item: Found) = (item.layer.content as? LayerContent.Text)?.value?.resolved("en") ?: ""

        fun log(what: String, id: String) {
            changes += "$what → $id"
        }

        fun update(path: List<Int>, change: (Layer) -> Layer) {
            val layer = LayerEditing.layer(path, spec.layers) ?: return
            spec = spec.copy(layers = LayerEditing.replace(path, spec.layers, change(layer)))
        }

        fun setText(path: List<Int>, en: String, ar: String, was: String, id: String) {
            update(path) { layer ->
                val text = layer.content as? LayerContent.Text ?: return@update layer
                layer.copy(content = text.copy(value = LText.Localized(en, ar)))
            }
            log("text \"$was\"", id)
        }

        // The model's own list

        /** The model said what an element shows but left the layer static. */
        fun modelWiring(wiring: List<WiringEntry>) {
            for (entry in wiring) {
                val shows = entry.shows?.takeIf { it.isNotEmpty() } ?: continue
                val names = Bindings.tokenize(shows).filterIsInstance<Bindings.Token.Binding>().map { it.name.trim() }
                if (names.isEmpty() || names.any { Capabilities.binding(it) == null }) continue
                val element = entry.element.lowercase()
                for (item in walk(spec.layers)) {
                    val text = item.layer.content as? LayerContent.Text ?: continue
                    if (text.liveKind != null) continue
                    val english = text.value.resolved("en").trim()
                    if (english.length < 2 || english.contains("{{") || !element.contains(english.lowercase())) continue
                    setText(item.path, shows, shows, english, names.first())
                    break
                }
            }
        }

        // Texts

        fun texts() {
            var clocks = 0
            for (item in walk(spec.layers)) {
                val text = item.layer.content as? LayerContent.Text ?: continue
                val target = text.liveTarget?.let(Bindings::soleBinding)?.trim()
                if (text.liveKind == "timer" && target != null && target.startsWith("field.") && topics.has("timer")) {
                    val key = target.removePrefix("field.")
                    update(item.path) { it.copy(content = text.copy(value = LText.Plain("{{timer.remaining}}"), liveKind = null, liveTarget = null)) }
                    replacedFields += key
                    log("countdown {{field.$key}}", "timer.remaining")
                    continue
                }
                if (text.liveKind != null) continue
                val english = text.value.resolved("en").trim()
                val sole = Bindings.soleBinding(english)
                if (sole != null && sole.trim().startsWith("field.")) {
                    val key = sole.trim().removePrefix("field.")
                    fieldBinding(key)?.let { id ->
                        replacedFields += key
                        setText(item.path, "{{$id}}", "{{$id}}", "{{field.$key}}", id)
                    }
                    continue
                }
                if (english.isEmpty() || english.contains("{{")) continue
                when {
                    TextShape.isClock(english) -> {
                        clocks += 1
                        val id = clockBinding(clocks)
                        val template = if (id == "time.hh") "{{time.hh}}:{{time.mm}}" + (if (TextShape.hasMeridiem(english)) " {{time.ampm}}" else "") else "{{$id}}"
                        setText(item.path, template, template, english, id)
                    }
                    // Only what a label names (ADR-028); unsure stays static, and DesignRules lists it.
                    TextShape.isPercent(english) -> shareBinding(item, "text")?.let { id -> setText(item.path, "{{$id}}%", "{{$id}}%", english, id) }
                    TextShape.percentLabel(english) != null -> namedShare(item, "text", TextShape.percentLabel(english) ?: "")?.let { id ->
                        setText(item.path, TextShape.replacingPercent(english, id), TextShape.replacingPercent(text.value.resolved("ar"), id), english, id)
                    }
                    TextShape.isTemperature(english) -> {
                        val unit = if (english.endsWith("C")) "C" else if (english.endsWith("F")) "F" else ""
                        setText(item.path, "{{weather.temp}}°$unit", "{{weather.temp}}°" + (if (unit == "C") "م" else if (unit == "F") "ف" else ""), english, "weather.temp")
                    }
                    TextShape.isStepCount(english) && topics.has("steps") -> setText(item.path, "{{steps.today}}", "{{steps.today}}", english, "steps.today")
                    TextShape.isDuration(english) -> durationBinding()?.let { id -> setText(item.path, "{{$id}}", "{{$id}}", english, id) }
                    else -> TextShape.dateTemplate(english)?.let { setText(item.path, it, it, english, "date") }
                }
            }
        }

        /** Rows of a list: an agenda's events, open reminders, prayer times. Row N takes item N. */
        /** A label that names another share wins: a "Year" percent never shows the battery. */
        fun correctShares() {
            for (item in walk(spec.layers)) {
                val (current, kind) = boundShare(item.layer) ?: continue
                val own = words(item.layer)
                val better = namedShare(item, kind, own) ?: continue
                if (better == current.id || isNamed(current, item, own)) continue
                val from = "{{${current.id}}}"
                val to = "{{$better}}"
                update(item.path) { layer ->
                    when (val c = layer.content) {
                        is LayerContent.Text -> {
                            val values = c.value.allValues.map { it.replace(from, to) }
                            layer.copy(content = c.copy(value = LText.Localized(values.first(), values.last())))
                        }
                        is LayerContent.Ring -> layer.copy(content = c.copy(progress = to))
                        is LayerContent.ProgressBar -> layer.copy(content = c.copy(progress = to))
                        is LayerContent.DotGrid -> layer.copy(content = c.copy(values = to))
                        else -> layer
                    }
                }
                log("${current.id} beside another label", better)
            }
        }

        /**
         * Three or more weather icons in a row are days: each follows its own day, and the labels and
         * temperatures under it follow too. A first column called Today shows today.
         */
        fun forecastRows() {
            val weather = ((Capabilities.binding("weather.symbol")?.icons ?: emptyList()) + listOf("cloud.drizzle.fill", "cloud.heavyrain.fill", "cloud.bolt.rain.fill", "cloud.snow.fill", "cloud.fog.fill", "moon.fill", "moon.stars.fill")).toSet()
            val items = walk(spec.layers).filter { (it.layer.content as? LayerContent.Icon)?.symbol in weather }
            val rows = mutableListOf<MutableList<Found>>()
            for (item in items) {
                val row = rows.firstOrNull { abs(it[0].frame.y + it[0].frame.h / 2 - item.frame.y - item.frame.h / 2) <= 12 }
                if (row != null) row += item else rows += mutableListOf(item)
            }
            for (row in rows) {
                if (row.size < 3) continue
                val days = row.sortedBy { it.frame.x }.take(7)
                val step = days[1].frame.x - days[0].frame.x
                val rowY = days[0].frame.y + days[0].frame.h / 2
                val texts = walk(spec.layers).filter { item ->
                    val text = item.layer.content as? LayerContent.Text
                    text != null && text.liveKind == null && !text.value.resolved("en").contains("{{") && abs(item.frame.y + item.frame.h / 2 - rowY) <= 70
                }
                fun column(icon: Found): List<Found> {
                    val middle = icon.frame.x + icon.frame.w / 2
                    return texts.filter { abs(it.frame.x + it.frame.w / 2 - middle) < step / 2 }.sortedBy { it.frame.y }
                }
                val startsToday = column(days[0]).any { TextShape.isToday(text(it).trim()) }
                for ((index, icon) in days.withIndex()) {
                    val day = if (startsToday) index else index + 1
                    if (day > 6) break
                    val symbol = if (day == 0) "weather.symbol" else "forecast.$day.symbol"
                    update(icon.path) { layer -> (layer.content as? LayerContent.Icon)?.let { layer.copy(content = it.copy(symbol = "{{$symbol}}")) } ?: layer }
                    log("forecast icon", symbol)
                    var temperatures = 0
                    for (item in column(icon)) {
                        val value = text(item).trim()
                        if (TextShape.isDayName(value) && day > 0) {
                            setText(item.path, "{{forecast.$day.day}}", "{{forecast.$day.day}}", value, "forecast.$day.day")
                        } else if (TextShape.isTemperature(value)) {
                            val part = if (temperatures == 0) "hi" else "lo"
                            temperatures += 1
                            val id = if (day == 0) "weather.$part" else "forecast.$day.$part"
                            setText(item.path, "{{$id}}°", "{{$id}}°", value, id)
                        }
                    }
                }
            }
        }

        /** A frozen face or dot drawing on a card about something that changes becomes a state layer. */
        fun stateSets() {
            faces()
            for (item in walk(spec.layers)) {
                when (val c = item.layer.content) {
                    is LayerContent.Text -> {
                        val value = c.value.resolved("en").replace("\uFE0E", "").replace("\uFE0F", "").trim()
                        val set = Capabilities.stateSets.firstOrNull { value in it.glyphs } ?: continue
                        if (value.isEmpty() || set.topic == null || !topics.has(set.topic)) continue
                        swap(item, set.id, set.topic, c.color)
                    }
                    is LayerContent.DotGrid -> {
                        if (c.rows < 8 || c.cols < 8 || Bindings.soleBinding(c.values) != null || isFillPattern(c)) continue
                        val set = artSet(item) ?: continue
                        swap(item, set.id, set.topic ?: "", c.onColor)
                    }
                    else -> Unit
                }
            }
        }

        private fun swap(item: Found, id: String, topic: String, color: String) {
            val states = LayerContent.States(id, null, color, "@accent", "@dim", null, null)
            if (item.path.size == 1) {
                update(item.path) { it.copy(content = states) }
            } else {
                // A stack child: keep its space, and draw the set at the top level over it.
                update(item.path) { it.copy(content = LayerContent.Spacer(null)) }
                insertDrawn(listOf(Layer(item.frame, null, item.mirror, null, null, states)))
            }
            log("frozen $topic", id)
        }

        /** A round head with small round eyes, drawn from shapes, on a battery card. */
        private fun faces() {
            if (!topics.has("battery") || Capabilities.stateSet("battery.mood") == null) return
            for ((index, layer) in spec.layers.withIndex()) {
                val parts = faceParts(index, spec.layers) ?: continue
                val shape = layer.content as? LayerContent.Shape
                val color = shape?.stroke?.color ?: shape?.fill ?: "@fg"
                val head = layer.copy(content = LayerContent.States("battery.mood", null, color, "@accent", "@dim", null, null))
                spec = spec.copy(layers = spec.layers.mapIndexed { position, other -> if (position == index) head else other }.filterIndexed { position, _ -> position !in parts })
                log("frozen face", "battery.mood")
                return
            }
        }

        fun listRows() {
            val rowButtons = mutableListOf<Layer>()
            listRows(rowButtons)
            spec = spec.copy(layers = spec.layers + rowButtons)
        }

        private fun listRows(rowButtons: MutableList<Layer>) {
            for (item in walk(spec.layers)) {
                val list = item.layer.content as? LayerContent.ListL ?: continue
                val prefix = topics.best("calendar", "tasks", "reminders")
                val rows = list.items.toMutableList()
                var changed = false
                for ((index, row) in rows.toList().withIndex()) {
                    val title = row.title.resolved("en")
                    val detail = row.detail?.resolved("en")?.trim() ?: ""
                    val lower = (title + " " + row.title.resolved("ar")).lowercase()
                    val prayer = if (TextShape.isClock(detail)) Capabilities.bindings.firstOrNull { c -> c.type == "date" && c.id.startsWith("prayer.") && c.keywords.any { occurs(it, lower) } } else null
                    if (prayer != null) {
                        rows[index] = row.copy(detail = LText.Plain("{{${prayer.id}}}"))
                        changed = true
                        log("row $title", prayer.id)
                        continue
                    }
                    if (index >= 4 || prefix == null) continue
                    val number = index + 1
                    if (!title.contains("{{")) {
                        rows[index] = rows[index].copy(title = LText.Plain("{{$prefix.$number.title}}"))
                        changed = true
                        log("row $title", "$prefix.$number.title")
                    }
                    // A task row is a checkbox: its tick follows the task, and a tap completes it.
                    if (prefix == "tasks" && rows[index].done == null) {
                        rows[index] = rows[index].copy(done = "{{tasks.$number.done}}")
                        changed = true
                        val height = item.frame.h / max(rows.size, 1)
                        rowButtons += Layer(Frame(item.frame.x, item.frame.y + index * height, item.frame.w, height), null, null, "{{tasks.$number.title}}", null, LayerContent.Button("task.toggle", "{{tasks.$number.id}}"))
                        log("row $title", "task.toggle")
                    }
                    if (prefix == "calendar" && TextShape.isClock(detail)) {
                        rows[index] = rows[index].copy(detail = LText.Plain("{{calendar.$number.time}}"))
                        changed = true
                        log("row $detail", "calendar.$number.time")
                    }
                }
                if (changed) update(item.path) { it.copy(content = list.copy(items = rows)) }
            }
        }

        fun clockBinding(index: Int): String = when {
            hasControls -> if (index == 1 && !uses("media.duration")) "media.elapsed" else "media.duration"
            topics.has("timer") -> "timer.remaining"
            else -> "time.hh"
        }

        fun durationBinding(): String? = when (topics.best("sleep", "focus", "timer")) {
            "sleep" -> "sleep.lastNight"
            "focus" -> "focus.today"
            "timer" -> "timer.remaining"
            else -> null
        }

        fun fieldBinding(key: String): String? {
            val field = spec.field(key)?.takeIf { it.type == "text" } ?: return null
            val words = (listOf(key) + field.label.allValues).joinToString(" ").lowercase()
            return Capabilities.bindings.firstOrNull { c ->
                !c.parametric && "text" in c.layers && c.ai && topics.has(c.prefix) && c.keywords.any { occurs(it, words) }
            }?.id
        }

        fun mediaTitles() {
            if (!(hasControls || uses("media.progress")) || uses("media.title")) return
            val generic = listOf("music", "player", "now playing", "playing", "موسيقى", "مشغل", "مشغّل")
            val texts = walk(spec.layers).filter { item ->
                val text = item.layer.content as? LayerContent.Text ?: return@filter false
                val value = text.value.resolved("en").lowercase()
                value.isNotEmpty() && generic.none { value.contains(it) } && (!value.contains("{{") || value.startsWith("{{field.")) && value.none { it.isDigit() }
            }.sortedByDescending { (it.layer.content as LayerContent.Text).font.size }
            for ((item, id) in texts.zip(listOf("media.title", "media.artist"))) {
                if (uses(id)) continue
                val value = (item.layer.content as LayerContent.Text).value.resolved("en")
                Bindings.soleBinding(value)?.trim()?.takeIf { it.startsWith("field.") }?.let { replacedFields += it.removePrefix("field.") }
                setText(item.path, "{{$id}}", "{{$id}}", value, id)
            }
        }

        fun symbols() {
            for (item in walk(spec.layers)) {
                val icon = item.layer.content as? LayerContent.Icon ?: continue
                if (Bindings.soleBinding(icon.symbol) != null) continue
                val binding = Capabilities.bindings.firstOrNull { it.type == "symbol" && icon.symbol in it.icons && topics.has(it.prefix) } ?: continue
                if (binding.id == "volume.symbol" && topics.value("media") >= topics.value("volume")) continue
                update(item.path) { it.copy(content = icon.copy(symbol = "{{${binding.id}}}")) }
                log("icon ${icon.symbol}", binding.id)
            }
            for (item in walk(spec.layers)) {
                if (item.layer.rotation != null) continue
                val icon = item.layer.content as? LayerContent.Icon ?: continue
                if (icon.symbol != "location.north.fill" && icon.symbol != "safari.fill") continue
                val prefix = topics.best("compass", "qibla") ?: continue
                val id = if (prefix == "qibla") "qibla.bearing" else "compass.north"
                update(item.path) { it.copy(rotation = "{{$id}}") }
                log("arrow ${icon.symbol}", id)
            }
        }

        // Progress

        fun progress() {
            for (item in walk(spec.layers)) {
                when (val c = item.layer.content) {
                    is LayerContent.ProgressBar -> if (Bindings.soleBinding(c.progress) == null) {
                        val id = shareBinding(item, "progressBar") ?: continue
                        update(item.path) { it.copy(content = c.copy(progress = "{{$id}}")) }
                        log("progress bar ${c.progress}", id)
                    }
                    is LayerContent.Ring -> if (Bindings.soleBinding(c.progress) == null) {
                        val id = shareBinding(item, "ring") ?: continue
                        update(item.path) { it.copy(content = c.copy(progress = "{{$id}}")) }
                        log("ring ${c.progress}", id)
                    }
                    is LayerContent.DotGrid -> if (Bindings.soleBinding(c.values) == null) {
                        // A label that names a share binds dots of any pattern: 15 of 48 lit is still a level.
                        val named = namedShare(item, "dotGrid")
                        if (named == null && !isFillPattern(c)) continue
                        val id = named ?: shareBinding(item, "dotGrid") ?: continue
                        update(item.path) { it.copy(content = c.copy(values = "{{$id}}")) }
                        log("dots ${c.values}", id)
                    }
                    else -> Unit
                }
            }
        }

        fun isFillPattern(grid: LayerContent.DotGrid): Boolean {
            val digits = grid.values.filter { it == '0' || it == '1' }
            if ('0' !in digits || '1' !in digits || grid.cols <= 0) return false
            return digits.chunked(grid.cols).all { row -> val off = row.indexOf('0'); off < 0 || '1' !in row.substring(off) }
        }

        // Sliders

        fun sliders() {
            if (!topics.has("volume") && !topics.has("brightness")) return
            val layers = spec.layers
            val taken = mutableSetOf<Int>()
            val bars = mutableMapOf<Int, Layer>()
            var level = 0
            for ((index, layer) in layers.withIndex()) {
                // A badge holds a text; a slider holds none.
                if (index in taken || !isSliderPiece(layer) || labels(layer.frame).isNotEmpty()) continue
                val vertical = layer.frame.h > layer.frame.w
                val parts = mutableListOf(index)
                var union = layer.frame
                for ((other, candidate) in layers.withIndex()) {
                    if (other == index || other in taken) continue
                    if ((isSliderPiece(candidate) || isDotTrack(candidate)) && vertical == (candidate.frame.h > candidate.frame.w) && aligned(layer.frame, candidate.frame, vertical)) {
                        parts += other
                        union = union(union, candidate.frame)
                    }
                }
                val id = sliderBinding(union, level)
                level += 1
                taken += parts
                val color = (layer.content as? LayerContent.Shape)?.fill ?: "@fg"
                val track = parts.firstNotNullOfOrNull { (layers[it].content as? LayerContent.DotGrid)?.offColor } ?: "@dim"
                val frame = if (vertical) union.copy(w = max(union.w, 12.0)) else union.copy(h = max(union.h, 8.0))
                bars[index] = Layer(frame, null, layer.mirror, null, null, LayerContent.ProgressBar("{{$id}}", color, track, null, null, if (vertical) true else null))
                log("drawn slider", id)
            }
            if (bars.isEmpty()) return
            val result = layers.mapIndexedNotNull { index, layer -> bars[index] ?: layer.takeIf { index !in taken } }
            spec = spec.copy(layers = result)
        }

        fun isSliderPiece(layer: Layer): Boolean {
            val shape = layer.content as? LayerContent.Shape ?: return false
            if (shape.kind !in listOf("capsule", "roundedRect", "rect") || shape.fill == null) return false
            val long = max(layer.frame.w, layer.frame.h)
            val short = min(layer.frame.w, layer.frame.h)
            return short > 1.5 && short <= 44 && long >= 4 * short && long >= 60
        }

        fun isDotTrack(layer: Layer): Boolean {
            val grid = layer.content as? LayerContent.DotGrid ?: return false
            return grid.rows == 1 || grid.cols == 1
        }

        fun aligned(a: Frame, b: Frame, vertical: Boolean): Boolean {
            val first = if (vertical) a.x + a.w / 2 else a.y + a.h / 2
            val second = if (vertical) b.x + b.w / 2 else b.y + b.h / 2
            return abs(first - second) <= max(if (vertical) max(a.w, b.w) else max(a.h, b.h), 8.0) / 2 + 2
        }

        fun union(a: Frame, b: Frame): Frame {
            val x = min(a.x, b.x)
            val y = min(a.y, b.y)
            return Frame(x, y, max(a.x + a.w, b.x + b.w) - x, max(a.y + a.h, b.y + b.h) - y)
        }

        fun sliderBinding(frame: Frame, position: Int): String {
            var bestIcon: String? = null
            var bestDistance = Double.POSITIVE_INFINITY
            for (item in walk(spec.layers)) {
                val icon = item.layer.content as? LayerContent.Icon ?: continue
                val distance = hypot(item.frame.x + item.frame.w / 2 - (frame.x + frame.w / 2), item.frame.y + item.frame.h / 2 - (frame.y + frame.h / 2))
                val reach = max(frame.w, frame.h) / 2 + 60
                if (distance < min(bestDistance, reach)) {
                    bestDistance = distance
                    bestIcon = icon.symbol
                }
            }
            val match = bestIcon?.let { symbol ->
                Capabilities.bindings.firstOrNull { it.type == "number" && "progressBar" in it.layers && symbol in it.icons && it.prefix in listOf("volume", "brightness") }
            }
            if (match != null && !uses(match.id)) return match.id
            val order = if (topics.has("volume")) listOf("volume.level", "volume.ring", "brightness.level") else listOf("brightness.level", "volume.level")
            return order[min(position, order.size - 1)]
        }

        fun sliderZones() {
            val pairs = mapOf(
                "volume.level" to ("volume.up" to "volume.down"), "volume.ring" to ("volume.ringUp" to "volume.ringDown"),
                "brightness.level" to ("brightness.up" to "brightness.down"),
            )
            val planned = mutableListOf<Planned>()
            for (layer in spec.layers) {
                val bar = layer.content as? LayerContent.ProgressBar ?: continue
                val raw = Bindings.soleBinding(bar.progress)?.trim() ?: continue
                val pair = pairs[raw] ?: continue
                val up = Capabilities.action(pair.first) ?: continue
                val down = Capabilities.action(pair.second) ?: continue
                if (buttons.any { it.second == up.id || it.second == down.id }) continue
                val f = layer.frame
                if (bar.vertical == true) {
                    planned += Planned(Frame(f.x - 10, f.y, f.w + 20, f.h / 2), up, null, raw)
                    planned += Planned(Frame(f.x - 10, f.y + f.h / 2, f.w + 20, f.h / 2), down, null, raw)
                } else {
                    planned += Planned(Frame(f.x, f.y - 10, f.w / 2, f.h + 20), down, layer.mirror, raw)
                    planned += Planned(Frame(f.x + f.w / 2, f.y - 10, f.w / 2, f.h + 20), up, layer.mirror, raw)
                }
            }
            add(planned)
        }

        // Toggles

        fun toggles() {
            val layers = spec.layers
            val extra = mutableListOf<Layer>()
            val planned = mutableListOf<Planned>()
            for ((index, layer) in layers.withIndex()) {
                val track = layer.content as? LayerContent.Shape ?: continue
                if ((track.kind != "capsule" && track.kind != "roundedRect") || layer.frame.w < 1.4 * layer.frame.h || layer.frame.h > 70) continue
                val knobIndex = layers.indices.firstOrNull { other ->
                    val shape = layers[other].content as? LayerContent.Shape
                    other != index && shape?.kind == "circle" && inside(layers[other].frame, layer.frame) && layers[other].frame.h >= 0.5 * layer.frame.h
                } ?: continue
                if (layers[knobIndex].condition != null) continue
                val action = actionFor(iconSymbols(layer.frame), labels(layer.frame, wide = true), isTile = true, requireSystem = true) ?: continue
                planned += Planned(layer.frame, action, layer.mirror, "switch")
                log("switch", action.id)
                val state = action.state ?: continue
                val knob = layers[knobIndex]
                val isOffLook = knob.frame.x + knob.frame.w / 2 < layer.frame.x + layer.frame.w / 2
                // The knob's other end, the same distance from the track's edge.
                val right = layer.frame.x + layer.frame.w - (knob.frame.x + knob.frame.w)
                val shift = if (isOffLook) right - (knob.frame.x - layer.frame.x) else (layer.frame.x - knob.frame.x) + right
                val pieces = listOf(knobIndex) + layers.indices.filter { layers[it].content is LayerContent.Icon && inside(layers[it].frame, knob.frame) }
                for (piece in pieces) {
                    val moved = layers[piece]
                    extra += moved.copy(
                        frame = moved.frame.copy(x = moved.frame.x + shift),
                        condition = if (isOffLook) "{{$state}}" else "!{{$state}}",
                    )
                    update(listOf(piece)) { it.copy(condition = if (isOffLook) "!{{$state}}" else "{{$state}}") }
                }
            }
            insertDrawn(extra)
            add(planned)
        }

        /** Drawn layers go under the tap areas: anything on top of a button takes its taps. */
        fun insertDrawn(layers: List<Layer>) {
            val index = spec.layers.indexOfFirst { it.content is LayerContent.Button }.let { if (it < 0) spec.layers.size else it }
            spec = spec.copy(layers = spec.layers.take(index) + layers + spec.layers.drop(index))
        }

        /** A switch drawn inside a stack can't be moved, so its on look is laid over it while the state is on. */
        fun stateLooks() {
            val looks = mutableListOf<Layer>()
            for ((frame, action) in buttons) {
                val state = Capabilities.action(action)?.state ?: continue
                if (uses(state)) continue
                val track = walk(spec.layers).firstOrNull { item ->
                    val shape = item.layer.content as? LayerContent.Shape
                    (shape?.kind == "capsule" || shape?.kind == "roundedRect") && inside(item.frame, frame) && item.frame.w >= 1.4 * item.frame.h && item.frame.h > 8
                } ?: continue
                val f = track.frame
                val inset = f.h * 0.1
                val knob = Frame(f.x + f.w - f.h + inset, f.y + inset, f.h - 2 * inset, f.h - 2 * inset)
                looks += Layer(f, null, track.mirror, "{{$state}}", null, LayerContent.Shape("capsule", "@accent", null, null, null))
                looks += Layer(knob, null, track.mirror, "{{$state}}", null, LayerContent.Shape("circle", "#FFFFFF", null, null, null))
                log("switch look", state)
            }
            insertDrawn(looks)
        }

        fun labels(frame: Frame, wide: Boolean = false): String {
            val area = if (wide) Frame(0.0, frame.y - 24, width, frame.h + 48) else frame
            return walk(spec.layers).mapNotNull { item ->
                val text = item.layer.content as? LayerContent.Text ?: return@mapNotNull null
                if (inside(item.frame, area)) text.value.allValues.joinToString(" ") else null
            }.joinToString(" ").lowercase()
        }

        fun iconSymbols(frame: Frame): List<String> = walk(spec.layers).mapNotNull { item ->
            val icon = item.layer.content as? LayerContent.Icon ?: return@mapNotNull null
            if (inside(item.frame, frame)) icon.symbol else null
        }

        // Controls

        fun actionFor(icons: List<String>, label: String, isTile: Boolean, requireSystem: Boolean = false): Capability? {
            var best: Capability? = null
            var bestScore = 0
            for (capability in Capabilities.actions) {
                if (!capability.ai) continue
                val prefix = if (capability.id.startsWith("system.toggle")) "system" else capability.prefix
                if (requireSystem && prefix != "system" && prefix != "volume") continue
                val iconHit = capability.icons.any { it in icons }
                val wordHit = label.isNotEmpty() && capability.keywords.any { occurs(it, label) }
                if (!iconHit && !(wordHit && isTile)) continue
                val topic = topics.value(prefix)
                if (!isTile && !(if (prefix == "system") systemIcons >= 3 else topic > 0)) continue
                val score = (if (wordHit) 100 else 0) + (if (iconHit) 10 else 0) + min(topic, 9)
                if (score > bestScore) {
                    best = capability
                    bestScore = score
                }
            }
            return best
        }

        fun tile(frame: Frame): Frame? {
            val limit = width * height * 0.5
            return spec.layers.flatMap { it.flattened }.mapNotNull { layer ->
                val shape = layer.content as? LayerContent.Shape ?: return@mapNotNull null
                val usable = (shape.fill != null || shape.stroke != null) && layer.condition == null && layer.frame.w * layer.frame.h <= limit &&
                    layer.frame.w >= frame.w && layer.frame.h >= frame.h && inside(frame, layer.frame)
                if (usable) layer.frame else null
            }.minByOrNull { it.w * it.h }
        }

        /** Frame and action of every top-level button. */
        val buttons: List<Pair<Frame, String>>
            get() = spec.layers.mapNotNull { layer -> (layer.content as? LayerContent.Button)?.let { layer.frame to it.action } }

        fun controls() {
            val planned = mutableListOf<Planned>()
            val seen = mutableListOf<Frame>()
            fun covered(frame: Frame) = buttons.any { it.second != "open.app" && inside(frame, it.first) }
            fun repeated(frame: Frame) = seen.any { inside(frame, it) && inside(it, frame) }
            for (item in walk(spec.layers)) {
                var symbol: String? = null
                var glyphAction: Capability? = null
                when (val c = item.layer.content) {
                    is LayerContent.Icon -> {
                        val raw = Bindings.soleBinding(c.symbol)
                        symbol = raw?.let { name -> Capabilities.binding(name)?.icons?.firstOrNull { icon -> Capabilities.actions.any { icon in it.icons } } } ?: c.symbol
                    }
                    is LayerContent.Text -> {
                        val value = c.value.resolved("en").filter { it != '︎' && it != '️' }.trim()
                        glyphAction = Capabilities.actions.firstOrNull { value in it.glyphs }
                        val area = tile(item.frame)
                        if (glyphAction == null && area != null && !value.contains("{{") && value.isNotEmpty() && !repeated(area)) {
                            val action = actionFor(iconSymbols(area), value.lowercase(), isTile = true)
                            if (action != null && action.group != "app" && !covered(area)) {
                                seen += area
                                planned += Planned(area, action, item.mirror, value)
                                continue
                            }
                        }
                    }
                    else -> continue
                }
                if (symbol == null && glyphAction == null) continue
                val area = tile(item.frame)
                val f = item.frame
                val label = labels(area ?: Frame(f.x - 20, f.y - 20, f.w + 40, f.h + 40))
                val action = glyphAction ?: actionFor(listOfNotNull(symbol), label, isTile = area != null) ?: continue
                if (action.id in listOf("volume.up", "volume.down", "brightness.up", "brightness.down") && area == null) continue
                if (action.id in listOf("media.open", "calendar.open", "weather.open", "compass.open", "reminders.open")) continue
                val frame = clamped(area ?: padded(f))
                if (covered(frame) || repeated(frame)) continue
                seen += frame
                planned += Planned(frame, action, item.mirror, symbol ?: "glyph")
            }
            add(planned)
        }

        fun padded(frame: Frame): Frame {
            val w = max(frame.w, 36.0)
            val h = max(frame.h, 36.0)
            return Frame(frame.x + frame.w / 2 - w / 2, frame.y + frame.h / 2 - h / 2, w, h)
        }

        fun clamped(frame: Frame): Frame {
            val w = min(frame.w, width)
            val h = min(frame.h, height)
            return Frame(min(max(frame.x, 0.0), width - w), min(max(frame.y, 0.0), height - h), w, h)
        }

        fun add(planned: List<Planned>) {
            if (planned.isEmpty()) return
            spec = spec.copy(layers = spec.layers.filter { layer ->
                val replaced = (layer.content as? LayerContent.Button)?.action == "open.app" && planned.any { inside(it.frame, layer.frame) }
                !replaced
            })
            for (item in planned) {
                val arg = arg(item)
                spec = spec.copy(layers = spec.layers + Layer(item.frame, null, item.mirror, null, null, LayerContent.Button(item.action.id, arg)))
                if (changes.none { it.endsWith("→ ${item.action.id}") && it.startsWith("switch") }) log("control ${item.element}", item.action.id)
            }
        }

        fun arg(item: Planned): String? {
            val kind = item.action.argFieldType ?: return null
            val base = when (kind) {
                "shortcut" -> "shortcut"
                "url" -> "link"
                else -> "value"
            }
            var index = 1
            while (spec.field("$base$index") != null) index += 1
            val key = "$base$index"
            val value = when (kind) {
                "shortcut" -> LText.Plain(item.element)
                "text" -> LText.Plain("")
                else -> null
            }
            spec = spec.copy(fields = spec.fields + FieldSpec(key, kind, item.action.title, value))
            return "{{field.$key}}"
        }

        fun card() {
            val map = mapOf(
                "compass" to "compass.open", "qibla" to "compass.open", "media" to "media.open", "weather" to "weather.open",
                "calendar" to "calendar.open", "reminders" to "reminders.open", "timer" to "timer.toggle", "stopwatch" to "stopwatch.toggle",
            )
            if (buttons.any { it.second != "open.app" }) return
            // The card is about what it shows most: a sleep card's temperature doesn't open the weather.
            val prefix = topics.best("compass", "qibla", "timer", "stopwatch", "media", "calendar", "reminders", "sleep", "steps", "focus", "weather") ?: return
            val action = map[prefix]?.let(Capabilities::action) ?: return
            val kept = spec.layers.filter { (it.content as? LayerContent.Button)?.action != "open.app" }
            spec = spec.copy(layers = kept + Layer(Frame(0.0, 0.0, width, height), null, null, null, null, LayerContent.Button(action.id, null)))
            log("whole card", action.id)
        }

        fun dropUnusedFields() {
            val used = BindingNames.names(spec).toSet()
            spec = spec.copy(fields = spec.fields.filter { it.key !in replacedFields || "field.${it.key}" in used })
        }
    }
}

/** What the layer editor changes (Wiring.swift, ADR-027): a layer's live value and what a tap on it does. */
object Wiring {
    fun bindableKind(layer: Layer): String? = when (layer.content) {
        is LayerContent.Text -> "text"
        is LayerContent.Ring -> "ring"
        is LayerContent.ProgressBar -> "progressBar"
        is LayerContent.DotGrid -> "dotGrid"
        is LayerContent.Icon -> "icon"
        else -> null
    }

    fun bindings(kind: String): List<Capability> = Capabilities.bindings.filter { !it.parametric && kind in it.layers && it.ai }

    fun binding(layer: Layer): String? = when (val c = layer.content) {
        is LayerContent.Text -> c.value.resolved("en")
        is LayerContent.Ring -> c.progress
        is LayerContent.ProgressBar -> c.progress
        is LayerContent.DotGrid -> c.values
        is LayerContent.Icon -> c.symbol
        else -> null
    }?.let(Bindings::soleBinding)?.trim()

    fun withBinding(id: String?, layer: Layer): Layer {
        val template = id?.let { "{{$it}}" }
        return when (val c = layer.content) {
            is LayerContent.Text -> layer.copy(content = c.copy(value = template?.let { LText.Localized(it, it) } ?: c.value))
            is LayerContent.Ring -> layer.copy(content = c.copy(progress = template ?: "0"))
            is LayerContent.ProgressBar -> layer.copy(content = c.copy(progress = template ?: "0"))
            is LayerContent.DotGrid -> layer.copy(content = c.copy(values = template ?: "0".repeat(max(c.rows * c.cols, 1))))
            is LayerContent.Icon -> layer.copy(content = c.copy(symbol = template ?: c.symbol))
            else -> layer
        }
    }

    fun frame(path: List<Int>, spec: WidgetSpec): Frame? = AutoWire.walk(spec.layers).firstOrNull { it.path == path }?.frame

    /** The top-level button over a layer (its own, when the layer is a button): index and button. */
    fun button(path: List<Int>, spec: WidgetSpec): Pair<Int, LayerContent.Button>? {
        if (path.size == 1) (spec.layers.getOrNull(path[0])?.content as? LayerContent.Button)?.let { return path[0] to it }
        val frame = frame(path, spec) ?: return null
        for (index in spec.layers.indices.reversed()) {
            val layer = spec.layers[index]
            val button = layer.content as? LayerContent.Button ?: continue
            if (AutoWire.inside(frame, layer.frame)) return index to button
        }
        return null
    }

    /** What a tap on the layer does; null removes it. A value-taking action gets a field for its value. */
    fun withAction(id: String?, arg: String?, path: List<Int>, spec: WidgetSpec): WidgetSpec {
        val existing = button(path, spec)
        val capability = id?.let(Capabilities::action)
        if (capability == null) return if (existing != null) spec.copy(layers = spec.layers.filterIndexed { index, _ -> index != existing.first }) else spec
        var fields = spec.fields
        var value = arg
        capability.argFieldType?.let { kind ->
            val base = when (kind) {
                "shortcut" -> "shortcut"
                "url" -> "link"
                else -> "value"
            }
            var number = 1
            while (fields.any { it.key == "$base$number" }) number += 1
            val key = "$base$number"
            fields = fields + FieldSpec(key, kind, capability.title, if (kind == "url") null else LText.Plain(""))
            value = "{{field.$key}}"
        }
        val button = LayerContent.Button(capability.id, value)
        if (existing != null) return spec.copy(fields = fields, layers = spec.layers.mapIndexed { index, layer -> if (index == existing.first) layer.copy(content = button) else layer })
        val frame = frame(path, spec) ?: return spec
        val w = max(frame.w, 36.0)
        val h = max(frame.h, 36.0)
        val padded = Frame(frame.x + frame.w / 2 - w / 2, frame.y + frame.h / 2 - h / 2, w, h)
        return spec.copy(fields = fields, layers = spec.layers + Layer(padded, null, null, null, null, button))
    }
}

/** What a design does (InteractiveSummary.swift): which elements are live, tappable or only look like controls. */
data class InteractiveSummary(val live: List<Item>, val tappable: List<Item>, val decorative: List<Item>) {
    data class Item(val path: List<Int>, val title: String, val capability: String?, val detail: String?)

    val isEmpty get() = live.isEmpty() && tappable.isEmpty() && decorative.isEmpty()

    companion object {
        fun build(spec: WidgetSpec, language: String): InteractiveSummary {
            val live = mutableListOf<Item>()
            val tappable = mutableListOf<Item>()
            val decorative = mutableListOf<Item>()
            val ar = language.startsWith("ar")
            fun note(capability: Capability) = when (capability.supportAndroid) {
                "panel" -> if (ar) "يفتح لوحة النظام" else "opens the system panel"
                "unsupported" -> if (ar) "غير متاح على هذا النظام" else "not available on this system"
                else -> null
            }
            fun names(text: String) = Bindings.tokenize(text).filterIsInstance<Bindings.Token.Binding>().map { it.name.trim() }
            val found = AutoWire.walk(spec.layers)
            val buttons = found.filter { it.layer.content is LayerContent.Button }.map { it.frame }
            for (item in found) {
                val bound: List<String> = when (val c = item.layer.content) {
                    is LayerContent.Text -> names(c.value.resolved("en")) + (c.liveTarget?.let(::names) ?: emptyList())
                    is LayerContent.Icon -> names(c.symbol)
                    is LayerContent.Ring -> names(c.progress)
                    is LayerContent.ProgressBar -> names(c.progress)
                    is LayerContent.DotGrid -> names(c.values)
                    is LayerContent.DotBars -> names(c.values)
                    is LayerContent.Image -> names(c.source)
                    is LayerContent.ListL -> c.items.flatMap { names(it.title.resolved("en")) }
                    is LayerContent.AnalogClock -> listOf("time.hh")
                    is LayerContent.ForecastRow -> listOf("weather.temp")
                    is LayerContent.States -> c.expanded.mapNotNull { it.condition }.flatMap(::names) + (c.value?.let(::names) ?: emptyList())
                    is LayerContent.Button -> {
                        Capabilities.action(c.action)?.let { tappable += Item(item.path, it.title.resolved(language), it.id, note(it)) }
                        continue
                    }
                    else -> emptyList()
                } + (item.layer.rotation?.let(::names) ?: emptyList())
                val capabilities = bound.mapNotNull(Capabilities::binding).distinctBy { it.id }
                capabilities.forEach { live += Item(item.path, it.title.resolved(language), it.id, note(it)) }
                val icon = item.layer.content as? LayerContent.Icon
                if (icon != null && capabilities.isEmpty() && buttons.none { AutoWire.inside(item.frame, it) } &&
                    Capabilities.actions.any { it.group != "open" && icon.symbol in it.icons }
                ) {
                    decorative += Item(item.path, icon.symbol, null, null)
                }
            }
            for (entry in spec.decorative) decorative += Item(emptyList(), entry.element, null, entry.reason)
            // What the product rules still find after the post-pass (ADR-028): static when unsure, marked here.
            for (finding in DesignRules.check(spec).findings) {
                if (decorative.none { it.path == finding.path && finding.path.isNotEmpty() }) decorative += Item(finding.path, finding.element, null, finding.message.resolved(language))
            }
            return InteractiveSummary(live, tappable, decorative)
        }
    }
}

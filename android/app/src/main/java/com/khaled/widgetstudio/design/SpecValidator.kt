package com.khaled.widgetstudio.design

import com.khaled.widgetstudio.render.Drawing
import com.khaled.widgetstudio.spec.Bindings
import com.khaled.widgetstudio.spec.Capabilities
import com.khaled.widgetstudio.spec.Family
import com.khaled.widgetstudio.spec.Frame
import com.khaled.widgetstudio.spec.Layer
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.LText
import com.khaled.widgetstudio.spec.SpecCondition
import com.khaled.widgetstudio.spec.SpecTokens
import com.khaled.widgetstudio.spec.WidgetSpec
import java.time.ZoneId

/** The icon whitelist from Icons.swift (assets/spec/icons.json), loaded once at startup. */
object IconWhitelist {
    @Volatile var names: Map<String, String> = emptyMap()
    fun isAllowed(symbol: String) = names.containsKey(symbol)

    /** ADR-029: any SF Symbol name (lower-case words and digits joined by dots, at most 60 characters). */
    fun isSymbolName(symbol: String) = symbol.isNotEmpty() && symbol.length <= 60 && !symbol.startsWith(".") && !symbol.endsWith(".") &&
        !symbol.contains("..") && symbol.all { it in 'a'..'z' || it in '0'..'9' || it == '.' }
}

/** Binding names and what they yield (Bindings.swift catalog). */
object BindingCatalog {
    enum class Kind { TEXT, NUMBER, LEVELS, DATE, SYMBOL, IMAGE }

    /** Built from `capabilities.json` (ADR-027); never list bindings by hand. */
    val catalog: Map<String, Pair<Kind, String>>
        get() = Capabilities.bindings.filter { !it.parametric }.associate { it.id to (kind(it.type) to it.group) }

    fun kind(type: String?) = when (type) {
        "number" -> Kind.NUMBER
        "levels", "series" -> Kind.LEVELS
        "date" -> Kind.DATE
        "symbol" -> Kind.SYMBOL
        "image" -> Kind.IMAGE
        else -> Kind.TEXT
    }

    fun isValidKey(key: String) = key.isNotEmpty() && key[0].isLetter() && key.all { it.code < 128 && (it.isLetterOrDigit() || it == '_') }

    sealed class Name {
        data class Builtin(val name: String) : Name()
        data class Field(val key: String) : Name()
        data class TimezoneTime(val key: String) : Name()
        data class DaysUntil(val key: String) : Name()
        /** app.<appFieldKey>.icon (ADR-029). */
        data class AppIcon(val key: String) : Name()
        /** stock.<tickerFieldKey>.<price|change|changePct|series> (ADR-029). */
        data class Stock(val key: String, val part: String) : Name()
    }

    val stockParts = listOf("price", "change", "changePct", "series")

    fun parse(raw: String): Name? {
        val name = raw.trim()
        return when {
            name.startsWith("field.") -> name.removePrefix("field.").takeIf(::isValidKey)?.let { Name.Field(it) }
            name.startsWith("days.") -> name.removePrefix("days.").takeIf(::isValidKey)?.let { Name.DaysUntil(it) }
            name.startsWith("tz.") && name.endsWith(".time") && name.length > "tz..time".length ->
                name.drop(3).dropLast(5).takeIf(::isValidKey)?.let { Name.TimezoneTime(it) }
            name.startsWith("app.") && name.endsWith(".icon") && name.length > "app..icon".length ->
                name.drop(4).dropLast(5).takeIf(::isValidKey)?.let { Name.AppIcon(it) }
            name.startsWith("stock.") -> name.split(".").takeIf { it.size == 3 && isValidKey(it[1]) && it[2] in stockParts }?.let { Name.Stock(it[1], it[2]) }
            catalog.containsKey(name) -> Name.Builtin(name)
            else -> null
        }
    }

    /** Bindings AI output may use: the catalog's, plus fields, days left and world clocks. */
    fun allowedInAI(name: Name): Boolean = when (name) {
        is Name.Builtin -> Capabilities.binding(name.name)?.ai ?: false
        is Name.Field, is Name.DaysUntil, is Name.TimezoneTime -> true
        is Name.AppIcon -> Capabilities.binding("app.<appField>.icon")?.ai ?: false
        is Name.Stock -> Capabilities.binding("stock.<tickerField>.price")?.ai ?: false
    }
}

/** The overlap rules shared by the AI validator, the layout fix and the layer editor (SpecLayout.swift). */
object SpecLayout {
    private const val OVERLAP_SHARE = 0.2

    fun collide(a: Frame, b: Frame): Boolean {
        val width = minOf(a.x + a.w, b.x + b.w) - maxOf(a.x, b.x)
        val height = minOf(a.y + a.h, b.y + b.h) - maxOf(a.y, b.y)
        if (width <= 0 || height <= 0) return false
        return width * height > OVERLAP_SHARE * minOf(a.w * a.h, b.w * b.h)
    }

    fun showsText(layer: Layer): Boolean = layer.flattened.any {
        it.content is LayerContent.Text || it.content is LayerContent.ListL || it.content is LayerContent.CalendarMonth || it.content is LayerContent.ForecastRow
    }

    private fun texts(layers: List<Layer>) = layers.indices.filter { showsText(layers[it]) && layers[it].condition == null }

    fun textOverlaps(layers: List<Layer>): List<Pair<Int, Int>> {
        val texts = texts(layers)
        return texts.flatMapIndexed { position, first -> texts.drop(position + 1).filter { collide(layers[first].frame, layers[it].frame) }.map { first to it } }
    }

    fun iconOverlaps(layers: List<Layer>): List<Pair<Int, Int>> {
        val icons = layers.indices.filter { layers[it].content is LayerContent.Icon && layers[it].condition == null }
        val texts = texts(layers)
        return icons.flatMap { icon -> texts.filter { collide(layers[icon].frame, layers[it].frame) }.map { icon to it } }
    }

    fun hidesWhatIsUnder(layer: Layer): Boolean = when (val c = layer.content) {
        is LayerContent.Shape -> c.fill?.let { fill -> Drawing.parseHex(fill)?.let { (it ushr 24) >= 128 } ?: true } ?: false
        is LayerContent.Image, is LayerContent.AnalogClock, is LayerContent.ProgressBar -> true
        else -> false
    }

    fun share(inner: Frame, outer: Frame): Double {
        val width = minOf(inner.x + inner.w, outer.x + outer.w) - maxOf(inner.x, outer.x)
        val height = minOf(inner.y + inner.h, outer.y + outer.h) - maxOf(inner.y, outer.y)
        if (width <= 0 || height <= 0 || inner.w <= 0 || inner.h <= 0) return 0.0
        return width * height / (inner.w * inner.h)
    }

    /** (cover, text): a filled shape drawn after a text hides more than half of it. */
    fun coveredTexts(layers: List<Layer>): List<Pair<Int, Int>> = texts(layers).flatMap { text ->
        layers.indices.filter { cover ->
            cover > text && layers[cover].condition == null && hidesWhatIsUnder(layers[cover]) && share(layers[text].frame, layers[cover].frame) > 0.5
        }.map { it to text }
    }

    fun overlapping(layers: List<Layer>): Set<Int> = (textOverlaps(layers) + iconOverlaps(layers) + coveredTexts(layers)).flatMap { listOf(it.first, it.second) }.toSet()

    /** The smallest shape or ring under the layer holding ≥ 80 % of it, smaller than half the widget. */
    fun container(index: Int, layers: List<Layer>, family: Family): Int? {
        if (index !in layers.indices) return null
        val frame = layers[index].frame
        val limit = 0.5 * family.width * family.height
        return layers.indices.filter { candidate ->
            candidate < index && layers[candidate].condition == null &&
                (layers[candidate].content is LayerContent.Shape || layers[candidate].content is LayerContent.Ring) &&
                layers[candidate].frame.w * layers[candidate].frame.h < limit && share(frame, layers[candidate].frame) >= 0.8
        }.minByOrNull { layers[it].frame.w * layers[it].frame.h }
    }
}

/**
 * Validation rules of brief §4.6 (SpecValidator.swift), with the same messages, since the AI retry
 * sends them back to the model. [ai] adds the AI-mode rules; [checksTextOverlaps] the overlap rule.
 */
class SpecValidator(private val ai: Boolean, private val checksTextOverlaps: Boolean = true) {
    companion object {
        const val MAX_LAYERS = 30
        /** A chart, dot grid or list is one layer however much it draws (ADR-029: raised from 60). */
        const val MAX_TOTAL_LAYERS = 100
        const val MAX_DOTS = 1600
        const val MAX_GRID_SIDE = 60
        const val MAX_SPANS = 12
        const val MAX_CHART_POINTS = 400
        const val MAX_STACK_DEPTH = 3
        const val MAX_CHILDREN = 12
        const val MAX_TEXT_LENGTH = 200
        val FONT_SIZES = 6.0..200.0
        const val MIN_AI_FONT_SIZE = 11.0
        val families = listOf("system", "system-rounded", "system-serif", "system-mono", "dot", "arabic", "hand", "serif-display", "condensed")
        val aiFieldTypes = setOf("text", "date", "image", "url", "shortcut", "timezone", "app", "ticker")

        /** Digits row by row: 0/1 on and off, or levels 0…9 when any digit is above 1 (SpecLiterals.dotPattern). */
        fun dotPattern(value: String): List<Double>? {
            val digits = value.filter { it != ' ' }
            if (digits.isEmpty() || digits.length > MAX_DOTS || !digits.all { it in '0'..'9' }) return null
            val binary = digits.all { it == '0' || it == '1' }
            return digits.map { (it - '0').toDouble() / if (binary) 1.0 else 9.0 }
        }
        val weekdayKeys = listOf("sun", "mon", "tue", "wed", "thu", "fri", "sat")

        fun isValidId(id: String) = id.isNotEmpty() && id.length <= 64 && id.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '.' || it == '-' || it == '_' }
    }

    private lateinit var spec: WidgetSpec
    private val issues = mutableListOf<String>()

    /** Every issue as "path: message"; empty when the spec is valid. */
    fun validate(spec: WidgetSpec): List<String> {
        this.spec = spec
        issues.clear()
        if (spec.schemaVersion > WidgetSpec.CURRENT_VERSION) fail("specVersion", "made for a newer version of Widget Studio (${spec.schemaVersion}); update the app")
        else if (spec.schemaVersion < 1) fail("specVersion", "must be 1 or ${WidgetSpec.CURRENT_VERSION}")
        spec.card?.let(::checkCard)
        if (!isValidId(spec.id)) fail("id", "use letters, digits, dots, dashes or underscores (max 64)")
        if (spec.name is LText.Plain) fail("name", "needs both \"en\" and \"ar\"")
        spec.name.allValues.forEach { text("name", it, allowBindings = false) }
        checkBackground()
        checkFields()
        if (spec.layers.isEmpty()) fail("layers", "needs at least one layer")
        // Tap areas don't count: every control needs one (ADR-027).
        if (spec.layers.count { it.content !is LayerContent.Button } > MAX_LAYERS) fail("layers", "at most $MAX_LAYERS layers")
        if (spec.layers.flatMap { it.flattenedStacks }.count { it.content !is LayerContent.Button } > MAX_TOTAL_LAYERS) fail("layers", "at most $MAX_TOTAL_LAYERS layers counting the children of stacks")
        spec.layers.forEachIndexed { index, layer -> checkLayer(layer, "layers[$index]", 0) }
        if (ai && checksTextOverlaps) {
            val drawn = spec.layers.map { it.copy(frame = clamped(it.frame, spec.family)) }
            for ((first, second) in SpecLayout.textOverlaps(drawn)) {
                fail("layers[$second]", "its text overlaps layers[$first]; put texts that belong together in one stack, or move the frames apart")
            }
        }
        return issues.toList()
    }

    fun clamped(frame: Frame, family: Family): Frame {
        val w = frame.w.coerceIn(0.0, family.width)
        val h = frame.h.coerceIn(0.0, family.height)
        return Frame(frame.x.coerceIn(0.0, family.width - w), frame.y.coerceIn(0.0, family.height - h), w, h)
    }

    private fun fail(path: String, message: String) {
        issues += if (path.isEmpty()) message else "$path: $message"
    }

    private fun color(path: String, value: String?) {
        if (value == null) return
        // ADR-029: a color binding (a calendar's color).
        Bindings.soleBinding(value)?.let { raw -> if (Capabilities.binding(raw.trim())?.type == "color") return binding(path, raw, null) }
        val token = value.startsWith("@") && SpecTokens.names.contains(value.drop(1))
        if (Drawing.parseHex(value) == null && !token) fail(path, "color must be #RRGGBB, #RRGGBBAA or a token (@${SpecTokens.names.joinToString(", @")})")
    }

    private fun format(value: Double) = if (value == Math.rint(value)) value.toLong().toString() else value.toString()

    private fun number(path: String, value: Double?, range: ClosedFloatingPointRange<Double>) {
        if (value == null) return
        if (!value.isFinite() || value !in range) fail(path, "must be between ${format(range.start)} and ${format(range.endInclusive)}")
    }

    private fun count(path: String, value: Int, range: IntRange) {
        if (value !in range) fail(path, "must be between ${range.first} and ${range.last}")
    }

    private fun text(path: String, value: String, allowBindings: Boolean = true, kinds: Set<BindingCatalog.Kind>? = null) {
        if (value.length > MAX_TEXT_LENGTH) fail(path, "at most $MAX_TEXT_LENGTH characters")
        if (DesignEditing.containsUrl(value)) fail(path, "remote URLs are not allowed in specs")
        val names = Bindings.tokenize(value).filterIsInstance<Bindings.Token.Binding>().map { it.name }
        if (!allowBindings && names.isNotEmpty()) {
            fail(path, "bindings are not allowed here")
            return
        }
        names.forEach { binding(path, it, kinds) }
    }

    private fun binding(path: String, raw: String, kinds: Set<BindingCatalog.Kind>?) {
        val name = BindingCatalog.parse(raw) ?: return fail(path, "unknown binding {{$raw}}")
        if (ai && !BindingCatalog.allowedInAI(name)) return fail(path, "binding {{$raw}} is not allowed in AI output")
        val kind: BindingCatalog.Kind = when (name) {
            is BindingCatalog.Name.Builtin -> {
                if (raw.trim() == "counter.progress" && spec.field("target")?.type != "number") fail(path, "{{counter.progress}} needs a number field with key \"target\"")
                BindingCatalog.catalog[name.name]?.first ?: BindingCatalog.Kind.TEXT
            }
            is BindingCatalog.Name.TimezoneTime -> {
                val field = spec.field(name.key) ?: return fail(path, "{{$raw}} refers to a missing field")
                if (field.type != "timezone") fail(path, "{{$raw}} needs a timezone field")
                BindingCatalog.Kind.TEXT
            }
            is BindingCatalog.Name.DaysUntil -> {
                val field = spec.field(name.key) ?: return fail(path, "{{$raw}} refers to a missing field")
                if (field.type != "date") fail(path, "{{$raw}} needs a date field")
                BindingCatalog.Kind.NUMBER
            }
            is BindingCatalog.Name.AppIcon -> {
                val field = spec.field(name.key) ?: return fail(path, "{{$raw}} refers to a missing field")
                if (field.type != "app") fail(path, "{{$raw}} needs a field of type app")
                BindingCatalog.Kind.IMAGE
            }
            is BindingCatalog.Name.Stock -> {
                val field = spec.field(name.key) ?: return fail(path, "{{$raw}} refers to a missing field")
                if (field.type != "ticker") fail(path, "{{$raw}} needs a field of type ticker")
                if (name.part == "series") BindingCatalog.Kind.LEVELS else BindingCatalog.Kind.NUMBER
            }
            is BindingCatalog.Name.Field -> {
                val field = spec.field(name.key) ?: return fail(path, "{{$raw}} refers to a missing field")
                if (ai && (field.type == "image" || field.type !in aiFieldTypes)) fail(path, "AI output may only bind text, date, link and Shortcut fields")
                when (field.type) {
                    "date" -> BindingCatalog.Kind.DATE
                    "number" -> BindingCatalog.Kind.NUMBER
                    "icon" -> BindingCatalog.Kind.SYMBOL
                    else -> BindingCatalog.Kind.TEXT
                }
            }
        }
        if (kinds != null && kind !in kinds) fail(path, "{{$raw}} doesn't give the right kind of value here")
    }

    private fun bindingOrLiteral(path: String, value: String, kinds: Set<BindingCatalog.Kind>, literal: (String) -> Boolean) {
        val raw = Bindings.soleBinding(value)
        if (raw != null) binding(path, raw, kinds) else if (!literal(value)) fail(path, "must be a binding like {{…}} or a valid literal")
    }

    private fun checkBackground() {
        val b = spec.background
        when (b.type) {
            "solid" -> {
                if (b.color == null) fail("background.color", "required for a solid background")
                color("background.color", b.color)
            }
            "gradient" -> {
                val colors = b.colors ?: emptyList()
                if (colors.size !in 2..4) fail("background.colors", "a gradient needs 2 to 4 colors")
                colors.forEachIndexed { index, value -> color("background.colors[$index]", value) }
                number("background.angle", b.angle, -360.0..360.0)
            }
            "glass" -> color("background.color", b.color)
            else -> fail("background.type", "unknown value")
        }
        color("background.outerColor", b.outerColor)
    }

    /** ADR-029: the card's shape, ratio, place and colors. */
    private fun checkCard(card: com.khaled.widgetstudio.spec.CardSpec) {
        number("card.aspect", card.aspect, 0.15..7.0)
        number("card.cornerRadius", card.cornerRadius, 0.0..200.0)
        card.bumps?.let { count("card.bumps", it, 5..24) }
        color("card.outerColor", card.outerColor)
        card.inset?.let { f ->
            val family = spec.family
            if (listOf(f.x, f.y, f.w, f.h).any { !it.isFinite() } || f.w <= 0 || f.h <= 0 || f.x < -0.5 || f.y < -0.5 ||
                f.x + f.w > family.width + 0.5 || f.y + f.h > family.height + 0.5) {
                fail("card.inset", "must lie inside the ${family.width.toInt()} × ${family.height.toInt()} canvas")
            }
        }
    }

    private fun gradient(path: String, g: com.khaled.widgetstudio.spec.SpecGradient?) {
        if (g == null) return
        if (g.colors.size !in 2..4) fail("$path.colors", "a gradient needs 2 to 4 colors")
        g.colors.forEachIndexed { index, value -> color("$path.colors[$index]", value) }
        number("$path.angle", g.angle, -360.0..360.0)
    }

    private fun checkFields() {
        val keys = mutableSetOf<String>()
        spec.fields.forEachIndexed { index, field ->
            val path = "fields[$index]"
            if (!BindingCatalog.isValidKey(field.key)) fail("$path.key", "letters, digits and underscores, starting with a letter")
            if (!keys.add(field.key)) fail("$path.key", "duplicate key \"${field.key}\"")
            if (ai && field.type !in aiFieldTypes) fail("$path.type", "AI output may only use text, date, url, shortcut, timezone, app, ticker and image fields")
            field.label.allValues.forEach { text("$path.label", it, allowBindings = false) }
            field.default?.allValues?.forEach { value ->
                val p = "$path.default"
                if (value.length > MAX_TEXT_LENGTH) fail(p, "at most $MAX_TEXT_LENGTH characters")
                when (field.type) {
                    "date" -> if (parseDate(value) == null) fail(p, "must be an ISO 8601 date")
                    "number" -> if (value.toDoubleOrNull() == null) fail(p, "must be a number")
                    "color" -> color(p, value)
                    "timezone" -> if (value.isNotEmpty() && runCatching { ZoneId.of(value) }.isFailure) fail(p, "unknown time zone")
                    "url" -> if (value.isNotEmpty()) fail(p, "URL fields can't have a default")
                    "icon" -> if (!IconWhitelist.isAllowed(value)) fail(p, "\"$value\" is not in the icon whitelist")
                    "app", "ticker" -> if (DesignEditing.containsUrl(value)) fail(p, "remote URLs are not allowed in specs")
                    else -> if (DesignEditing.containsUrl(value)) fail(p, "remote URLs are not allowed in specs")
                }
            }
        }
    }

    private fun parseDate(value: String): Any? = runCatching { java.time.Instant.parse(value) }.getOrNull()
        ?: runCatching { java.time.LocalDateTime.parse(value) }.getOrNull()
        ?: runCatching { java.time.LocalDate.parse(value) }.getOrNull()
        ?: runCatching { java.time.OffsetDateTime.parse(value) }.getOrNull()

    private fun font(font: com.khaled.widgetstudio.spec.FontSpec, path: String) {
        if (font.family !in families) fail("$path.family", "unknown font \"${font.family}\"; use ${families.joinToString(", ")}")
        number("$path.size", font.size, FONT_SIZES)
        if (ai && font.size < MIN_AI_FONT_SIZE) fail("$path.size", "at least ${MIN_AI_FONT_SIZE.toInt()}")
    }

    /** A `when`: known bindings, each optionally negated, compared or tested, joined by `&&` and `||`. */
    private fun condition(path: String, text: String) {
        val expression = com.khaled.widgetstudio.spec.SpecExpression.parse(text)
        if (expression == null) {
            fail(path, "use \"{{binding}}\", \"!{{binding}}\", \"{{binding}} == value\", \">= 0.9\", \"in 0.5..0.8\" or \"in a,b\", joined by && or ||")
            return
        }
        expression.bindings.forEach { binding(path, it, null) }
    }

    /** A state layer (ADR-028): a built-in set or written-out variants, always at the top level. */
    private fun checkStates(states: LayerContent.States, path: String, depth: Int) {
        if (depth > 0) fail("$path.type", "a states layer stays at the top level")
        color("$path.color", states.color)
        color("$path.accent", states.accent)
        color("$path.dim", states.dim)
        states.box?.let { box -> if (box.size != 2 || box.any { it <= 0 }) fail("$path.box", "needs a positive width and height") }
        if (states.set != null) {
            val set = com.khaled.widgetstudio.spec.Capabilities.stateSet(states.set)
            if (set == null) {
                fail("$path.set", "unknown state set \"${states.set}\"; use an id from the allowed list")
                return
            }
            if (set.value != null) {
                val raw = states.value?.let(Bindings::soleBinding)
                if (raw == null) {
                    fail("$path.value", "${set.id} needs one binding, like ${set.value}")
                    return
                }
                binding("$path.value", raw, null)
            }
        } else if (states.variants == null) {
            fail("$path.set", "needs a built-in set or variants")
        }
        val variants = states.variants ?: return
        if (variants.isEmpty() || variants.size > 12) fail("$path.variants", "needs 1 to 12 variants")
        if (variants.map { it.id }.toSet().size != variants.size) fail("$path.variants", "ids must differ")
        variants.forEachIndexed { index, variant ->
            val itemPath = "$path.variants[$index]"
            if (variant.condition != null) condition("$itemPath.when", variant.condition)
            else if (index != variants.size - 1) fail("$itemPath.when", "only the last variant can be the default")
            if (variant.layers.size > 12) fail("$itemPath.layers", "at most 12 layers")
            variant.layers.forEachIndexed { position, layer ->
                val layerPath = "$itemPath.layers[$position]"
                when (layer.content) {
                    is LayerContent.Button -> fail("$layerPath.type", "a button stays at the top level, over the state layer")
                    is LayerContent.States -> fail("$layerPath.type", "states don't nest")
                    else -> checkLayer(layer, layerPath, 0)
                }
            }
        }
    }

    private fun checkLayer(layer: Layer, path: String, depth: Int) {
        val f = layer.frame
        if (depth == 0 && (listOf(f.x, f.y, f.w, f.h).any { !it.isFinite() } || f.w <= 0 || f.h <= 0)) fail("$path.frame", "w and h must be positive numbers")
        number("$path.opacity", layer.opacity, 0.0..1.0)
        layer.condition?.let { condition("$path.when", it) }
        layer.rotation?.let { rotation -> bindingOrLiteral("$path.rotation", rotation, setOf(BindingCatalog.Kind.NUMBER)) { v -> v.toDoubleOrNull()?.let { it in -360.0..360.0 } ?: false } }
        val number1 = setOf(BindingCatalog.Kind.NUMBER)
        val fraction: (String) -> Boolean = { v -> v.toDoubleOrNull()?.let { it in 0.0..1.0 } ?: false }
        when (val c = layer.content) {
            is LayerContent.Unknown -> fail("$path.type", "unknown layer type \"${c.type}\"")
            is LayerContent.Text -> {
                c.value.allValues.forEach { text("$path.value", it) }
                font(c.font, "$path.font")
                number("$path.minScale", c.minScale, 0.3..1.0)
                c.spans?.let { spans ->
                    count("$path.spans", spans.size, 1..MAX_SPANS)
                    spans.forEachIndexed { index, span ->
                        val p = "$path.spans[$index]"
                        span.text.allValues.forEach { text("$p.text", it) }
                        span.font?.let { font(it, "$p.font") }
                        color("$p.color", span.color)
                        number("$p.baselineOffset", span.baselineOffset, -100.0..100.0)
                        number("$p.tracking", span.tracking, -10.0..40.0)
                    }
                }
                c.path?.let { arc -> number("$path.path.arc", arc.arc, 1.0..400.0); number("$path.path.start", arc.start, -720.0..720.0) }
                color("$path.color", c.color)
                c.maxLines?.let { count("$path.maxLines", it, 1..10) }
                number("$path.tracking", c.tracking, -10.0..40.0)
                if (c.liveKind == "timer" || c.liveKind == "relative") {
                    val raw = c.liveTarget?.let(Bindings::soleBinding)
                    if (raw == null) fail("$path.live.target", "needs a date binding like {{field.date}}") else binding("$path.live.target", raw, setOf(BindingCatalog.Kind.DATE))
                }
            }
            is LayerContent.Image -> {
                val raw = Bindings.soleBinding(c.source)
                if (raw != null) {
                    binding("$path.source", raw, setOf(BindingCatalog.Kind.IMAGE))
                } else {
                    val asset = c.source.startsWith("asset:") && isValidId(c.source.removePrefix("asset:"))
                    if (c.source != "user_image" && !asset) fail("$path.source", "must be \"user_image\", an image binding like {{media.artwork}} or {{media.appIcon}}, or \"asset:<id>\"")
                    else if (ai && c.source != "user_image") fail("$path.source", "AI output may only use \"user_image\"")
                    number("$path.cornerRadius", c.cornerRadius, 0.0..200.0)
                }
            }
            is LayerContent.Shape -> {
                if (c.fill == null && c.stroke == null && c.gradient == null) fail(path, "a shape needs a fill or a stroke")
                color("$path.fill", c.fill)
                gradient("$path.fill", c.gradient)
                c.sides?.let { count("$path.sides", it, 3..24) }
                number("$path.innerRatio", c.innerRatio, 0.0..0.95)
                number("$path.startAngle", c.startAngle, -720.0..720.0)
                number("$path.endAngle", c.endAngle, -720.0..720.0)
                c.points?.let { points ->
                    if (points.size !in 3..16) fail("$path.points", "a polygon needs 3 to 16 points")
                    if (points.any { p -> p.size != 2 || p.any { it !in -0.01..1.01 } }) fail("$path.points", "each point is [x, y] with fractions of the frame, 0 to 1")
                }
                c.progress?.let { bindingOrLiteral("$path.progress", it, number1, fraction) }
                c.stroke?.let { s ->
                    color("$path.stroke.color", s.color)
                    number("$path.stroke.width", s.width, 0.0..40.0)
                    if (s.dash != null && (s.dash.size > 8 || s.dash.any { it !in 0.0..100.0 })) fail("$path.stroke.dash", "up to 8 lengths between 0 and 100")
                }
                number("$path.cornerRadius", c.cornerRadius, 0.0..200.0)
            }
            is LayerContent.Icon -> {
                val raw = Bindings.soleBinding(c.symbol)
                if (raw != null) binding("$path.symbol", raw, setOf(BindingCatalog.Kind.SYMBOL))
                else if (!IconWhitelist.isAllowed(c.symbol) && !IconWhitelist.isSymbolName(c.symbol)) fail("$path.symbol", "\"${c.symbol}\" is not an SF Symbol name (lower-case words joined by dots)")
                number("$path.size", c.size, 4.0..200.0)
                color("$path.color", c.color)
            }
            is LayerContent.AnalogClock -> {
                listOf("faceColor" to c.faceColor, "tickColor" to c.tickColor, "hourColor" to c.hourColor, "minuteColor" to c.minuteColor, "accentColor" to c.accentColor)
                    .forEach { (key, value) -> color("$path.$key", value) }
                c.timezone?.let { zone -> bindingOrLiteral("$path.timezone", zone, setOf(BindingCatalog.Kind.TEXT)) { runCatching { ZoneId.of(it) }.isSuccess } }
                number("$path.hourWidth", c.hourWidth, 0.005..0.4); number("$path.minuteWidth", c.minuteWidth, 0.005..0.4)
                number("$path.hourLength", c.hourLength, 0.1..1.2); number("$path.minuteLength", c.minuteLength, 0.1..1.2)
            }
            is LayerContent.DotGrid -> {
                count("$path.rows", c.rows, 1..MAX_GRID_SIDE)
                count("$path.cols", c.cols, 1..MAX_GRID_SIDE)
                if (c.rows * c.cols > MAX_DOTS) fail(path, "at most $MAX_DOTS dots")
                c.levelColors?.let { colors -> count("$path.levelColors", colors.size, 1..10); colors.forEachIndexed { i, v -> color("$path.levelColors[$i]", v) } }
                number("$path.dotSize", c.dotSize, 0.5..60.0)
                number("$path.gap", c.gap, 0.0..60.0)
                color("$path.onColor", c.onColor); color("$path.offColor", c.offColor); color("$path.highlightColor", c.highlightColor)
                bindingOrLiteral("$path.values", c.values, setOf(BindingCatalog.Kind.LEVELS, BindingCatalog.Kind.NUMBER)) { v -> dotPattern(v) != null }
            }
            is LayerContent.DotBars -> {
                count("$path.bars", c.bars, 1..31)
                count("$path.maxDots", c.maxDots, 1..24)
                bindingOrLiteral("$path.values", c.values, setOf(BindingCatalog.Kind.LEVELS)) { v -> v.split(",").map { it.trim().toDoubleOrNull() }.let { p -> p.isNotEmpty() && p.size <= 31 && p.all { it != null && it in 0.0..1.0 } } }
                color("$path.color", c.color); color("$path.offColor", c.offColor); color("$path.highlightColor", c.highlightColor)
                c.labels?.allValues?.forEach { text("$path.labels", it, kinds = setOf(BindingCatalog.Kind.TEXT)) }
            }
            is LayerContent.Ring -> {
                bindingOrLiteral("$path.progress", c.progress, number1, fraction)
                color("$path.color", c.color); color("$path.trackColor", c.trackColor)
                number("$path.lineWidth", c.lineWidth, 0.5..60.0)
            }
            is LayerContent.ForecastRow -> {
                count("$path.days", c.days, if (c.mode == "hourly") 1..8 else 1..7)
                color("$path.color", c.color); color("$path.dividerColor", c.dividerColor); color("$path.labelColor", c.labelColor)
                c.font?.let { font(it, "$path.font") }
            }
            is LayerContent.Chart -> {
                bindingOrLiteral("$path.values", c.values, setOf(BindingCatalog.Kind.LEVELS)) { v -> LayerContent.Chart.parse(v)?.let { it.size <= MAX_CHART_POINTS } ?: false }
                color("$path.color", c.color); color("$path.fill", c.fill); gradient("$path.fill", c.gradient)
                listOf("baselineColor" to c.baselineColor, "highlightColor" to c.highlightColor, "labelColor" to c.labelColor, "downColor" to c.downColor)
                    .forEach { (key, value) -> color("$path.$key", value) }
                number("$path.lineWidth", c.lineWidth, 0.5..20.0); number("$path.barWidth", c.barWidth, 0.05..1.0); number("$path.cornerRadius", c.cornerRadius, 0.0..40.0)
                c.baseline?.let { if (it.lowercase() !in listOf("first", "average") && it.toDoubleOrNull() == null) fail("$path.baseline", "a number, \"first\" or \"average\"") }
                if (c.min != null && c.max != null && c.min >= c.max) fail("$path.max", "must be above min")
                listOf("xLabels" to c.xLabels, "yLabels" to c.yLabels).forEach { (key, labels) ->
                    labels?.allValues?.forEach { value -> text("$path.$key", value); if (value.split(",").size > 12) fail("$path.$key", "at most 12 labels") }
                }
                c.labelFont?.let { font(it, "$path.labelFont") }
            }
            is LayerContent.CalendarMonth -> {
                font(c.font, "$path.font"); font(c.effectiveTitleFont, "$path.titleFont"); font(c.effectiveWeekdayFont, "$path.weekdayFont")
                listOf("color" to c.color, "titleColor" to c.titleColor, "weekdayColor" to c.weekdayColor, "weekendColor" to c.weekendColor,
                    "todayColor" to c.todayColor, "todayTextColor" to c.todayTextColor).forEach { (key, value) -> color("$path.$key", value) }
                c.weekendDays?.forEachIndexed { index, day -> if (day.lowercase() !in weekdayKeys) fail("$path.weekendDays[$index]", "use ${weekdayKeys.joinToString(", ")}") }
            }
            is LayerContent.ListL -> {
                count("$path.items", c.items.size, 1..8)
                font(c.font, "$path.font")
                listOf("color" to c.color, "detailColor" to c.detailColor, "markerColor" to c.markerColor, "dividerColor" to c.dividerColor).forEach { (key, value) -> color("$path.$key", value) }
                c.items.forEachIndexed { index, item ->
                    val p = "$path.items[$index]"
                    item.title.allValues.forEach { text("$p.title", it) }
                    item.detail?.allValues?.forEach { text("$p.detail", it) }
                    item.subtitle?.allValues?.forEach { text("$p.subtitle", it) }
                    item.detail2?.allValues?.forEach { text("$p.detail2", it) }
                    if (item.icon != null && !IconWhitelist.isAllowed(item.icon)) fail("$p.icon", "\"${item.icon}\" is not in the icon whitelist")
                    color("$p.color", item.color)
                    item.done?.let { condition("$path.items.done", it) }
                }
            }
            is LayerContent.ProgressBar -> {
                bindingOrLiteral("$path.progress", c.progress, number1, fraction)
                color("$path.color", c.color); color("$path.trackColor", c.trackColor)
                c.segments?.let { count("$path.segments", it, 1..20) }
                number("$path.cornerRadius", c.cornerRadius, 0.0..200.0)
                c.knob?.let { k -> number("$path.knob.size", k.size, 0.0..80.0); color("$path.knob.color", k.color) }
            }
            is LayerContent.Button -> {
                val capability = Capabilities.action(c.action) ?: return fail("$path.action", "unknown action \"${c.action}\"; use an id from the allowed list")
                if (ai && !capability.ai) return fail("$path.action", "${capability.id} is not allowed in AI output")
                val required = capability.argFieldType
                if (required == null) {
                    c.arg?.takeIf { it.isNotEmpty() }?.let { text("$path.arg", it) }
                } else {
                    val raw = c.arg?.let(Bindings::soleBinding)
                    val key = (raw?.let(BindingCatalog::parse) as? BindingCatalog.Name.Field)?.key
                    if (key == null || spec.field(key)?.type != required) fail("$path.arg", "must be {{field.<key>}} of a $required field")
                }
            }
            is LayerContent.Stack -> checkStack(c, path, depth + 1)
            is LayerContent.States -> checkStates(c, path, depth)
            is LayerContent.Spacer -> {
                if (depth == 0) fail("$path.type", "a spacer only goes inside a vertical or horizontal stack")
                number("$path.minLength", c.minLength, 0.0..200.0)
            }
        }
    }

    private fun checkStack(stack: LayerContent.Stack, path: String, depth: Int) {
        if (depth > MAX_STACK_DEPTH) fail(path, "stacks nest at most $MAX_STACK_DEPTH deep")
        count("$path.children", stack.children.size, 1..MAX_CHILDREN)
        number("$path.spacing", stack.spacing, 0.0..100.0)
        number("$path.padding", stack.padding, 0.0..100.0)
        if (stack.axis == "grid") count("$path.columns", stack.columns ?: 2, 1..8) else if (stack.columns != null) fail("$path.columns", "only grids have columns")
        if (stack.axis == "radial") {
            number("$path.radius", stack.radius, 0.0..400.0); number("$path.startAngle", stack.startAngle, -720.0..720.0); number("$path.sweep", stack.sweep, 0.0..360.0)
        }
        stack.children.forEachIndexed { index, child ->
            val p = "$path.children[$index]"
            val size = child.frame
            if (!size.w.isFinite() || !size.h.isFinite() || size.w < 0 || size.h < 0) fail(p, "width and height must be positive numbers or absent")
            when (child.content) {
                is LayerContent.Text, is LayerContent.Icon, is LayerContent.Stack -> Unit
                is LayerContent.Spacer -> if (stack.axis == "grid") fail(p, "grids can't hold spacers") else if (stack.axis == "radial") fail(p, "a radial stack can't hold spacers")
                is LayerContent.Shape -> if (stack.axis != "radial" && (if (stack.axis == "horizontal") size.w <= 0 else size.h <= 0))
                    fail(p, if (stack.axis == "horizontal") "needs a width inside a horizontal stack" else "needs a height inside this stack")
                is LayerContent.Ring, is LayerContent.ProgressBar, is LayerContent.AnalogClock ->
                    if (if (stack.axis == "horizontal") size.w <= 0 else size.h <= 0) fail(p, if (stack.axis == "horizontal") "needs a width inside a horizontal stack" else "needs a height inside this stack")
                else -> fail("$p.type", "\"${com.khaled.widgetstudio.spec.SpecWriter.typeName(child.content)}\" can't go in a stack; give it its own frame")
            }
            checkLayer(child, p, depth)
        }
    }
}

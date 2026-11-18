package com.khaled.widgetstudio.spec

/**
 * The widget spec (brief §4), the same JSON the iOS app reads (WidgetKitCore/Spec). Every change
 * to the spec must update both models and both renderers (ADR-025).
 */
data class WidgetSpec(
    val schemaVersion: Int,
    val id: String,
    val name: LText,
    val family: Family,
    val theme: Theme,
    val refresh: String,
    val background: Background,
    val fields: List<FieldSpec>,
    val layers: List<Layer>,
    val category: String?,
    /** Elements that look live but aren't, with why (prompt v5's wiring list, ADR-027). */
    val decorative: List<DecorativeNote> = emptyList(),
    /** The card inside the widget (ADR-029); layer frames are in its canvas. */
    val card: CardSpec? = null,
) {
    fun field(key: String): FieldSpec? = fields.firstOrNull { it.key == key }

    /** The card in the family canvas: the whole canvas without a card (WidgetSpec.cardFrame). */
    val cardFrame: Frame get() = card?.frame(family) ?: Frame(0.0, 0.0, family.width, family.height)
    /** Layer coordinates: the card's own size, else the family canvas. */
    val canvasWidth: Double get() = cardFrame.w
    val canvasHeight: Double get() = cardFrame.h

    companion object {
        /** The newest spec version this app reads (ADR-029); version 1 still opens. */
        const val CURRENT_VERSION = 2
    }
}

/** The card of ADR-029 (CardSpec in SpecDrawing.swift). */
data class CardSpec(
    val shape: String? = null, val aspect: Double? = null, val inset: Frame? = null, val cornerRadius: Double? = null,
    val orientation: String? = null, val bumps: Int? = null, val outerColor: String? = null,
) {
    val effectiveAspect: Double?
        get() {
            if (aspect != null && aspect.isFinite() && aspect > 0) return aspect
            return when (shape) {
                "circle", "scallop" -> 1.0
                "capsule" -> if (orientation == "vertical") 0.5 else null
                else -> null
            }
        }

    fun frame(family: Family): Frame {
        if (inset != null && inset.w > 0 && inset.h > 0) {
            val w = inset.w.coerceIn(0.0, family.width)
            val h = inset.h.coerceIn(0.0, family.height)
            return Frame(inset.x.coerceIn(0.0, family.width - w), inset.y.coerceIn(0.0, family.height - h), w, h)
        }
        val a = effectiveAspect
        if (a == null) {
            if (shape == "capsule") {
                val pad = minOf(family.width, family.height) * 0.04
                return Frame(pad, pad, family.width - 2 * pad, family.height - 2 * pad)
            }
            return Frame(0.0, 0.0, family.width, family.height)
        }
        val width = minOf(family.width, family.height * a)
        val height = width / a
        fun half(v: Double) = Math.rint(v * 2) / 2
        return Frame(half((family.width - width) / 2), half((family.height - height) / 2), half(width), half(height))
    }

    val hasOuter: Boolean get() = shape != "none" && ((shape != "roundedRect" && shape != null) || effectiveAspect != null || inset != null)
}

/** ADR-029 drawing types (SpecDrawing.swift). */
data class TextSpan(val text: LText, val font: FontSpec? = null, val color: String? = null, val baselineOffset: Double? = null, val case: String? = null, val tracking: Double? = null)
data class TextPath(val arc: Double? = null, val start: Double? = null, val inside: Boolean? = null)
data class SpecGradient(val type: String, val colors: List<String>, val angle: Double? = null)
data class Knob(val size: Double? = null, val color: String? = null)

data class DecorativeNote(val element: String, val reason: String)

enum class Family(val width: Double, val height: Double) {
    /** XLARGE (ADR-030): iOS 27's 4 × 6 portrait widget and Android's XL size. */
    SMALL(170.0, 170.0), MEDIUM(364.0, 170.0), LARGE(364.0, 382.0), XLARGE(364.0, 570.0);

    companion object {
        fun of(raw: String): Family = when (raw) {
            "medium" -> MEDIUM
            "large" -> LARGE
            "xlarge" -> XLARGE
            else -> SMALL
        }
    }
}

enum class Theme { LIGHT, DARK }

/** A visible text: one string, or English and Arabic. */
sealed class LText {
    data class Plain(val text: String) : LText()
    data class Localized(val en: String, val ar: String) : LText()

    fun resolved(language: String): String = when (this) {
        is Plain -> text
        is Localized -> if (language.startsWith("ar")) ar else en
    }

    val allValues: List<String>
        get() = when (this) {
            is Plain -> listOf(text)
            is Localized -> listOf(en, ar)
        }
}

data class Background(
    val type: String,
    val color: String?,
    val colors: List<String>?,
    val angle: Double?,
    val outerColor: String?,
    /** With `outerColor`: `circle` (default) or `capsule` (ADR-024). */
    val cardShape: String?,
)

data class FieldSpec(val key: String, val type: String, val label: LText, val default: LText?)

data class Frame(val x: Double, val y: Double, val w: Double, val h: Double) {
    fun mirrored(canvasWidth: Double) = Frame(canvasWidth - x - w, y, w, h)
}

data class FontSpec(val family: String, val size: Double, val weight: String?)

data class Layer(
    val frame: Frame,
    val opacity: Double?,
    val mirror: Boolean?,
    val condition: String?,
    val rotation: String?,
    val content: LayerContent,
) {
    /** This layer, every layer inside a stack, and every look of a state layer. */
    val flattened: List<Layer>
        get() = when (content) {
            is LayerContent.Stack -> listOf(this) + content.children.flatMap { it.flattened }
            is LayerContent.States -> listOf(this) + content.expanded.flatMap { variant -> variant.layers.flatMap { it.flattened } }
            else -> listOf(this)
        }

    /** This layer and the children of stacks: what is drawn at once, for the layer limits. */
    val flattenedStacks: List<Layer>
        get() = if (content is LayerContent.Stack) listOf(this) + content.children.flatMap { it.flattenedStacks } else listOf(this)
}

/** One look of a state layer (ADR-028); no [condition] = the default. */
data class StateVariant(val id: String, val title: LText?, val condition: String?, val layers: List<Layer>, val sample: Map<String, String>?)

data class Stroke(val color: String, val width: Double, val dash: List<Double>?)

data class ListItem(
    val title: LText, val detail: LText?, val icon: String?, val color: String?,
    /** A condition: the row is a checkbox, ticked and faded while it holds (ADR-028). */
    val done: String? = null,
    /** ADR-029: a smaller line under the title, and a second detail under the first. */
    val subtitle: LText? = null,
    val detail2: LText? = null,
)

sealed class LayerContent {
    data class Text(
        val value: LText, val font: FontSpec, val color: String, val align: String?, val maxLines: Int?,
        val tracking: Double?, val liveKind: String?, val liveTarget: String?,
        /** ADR-029: runs with their own look, upper/lower case, the smallest shrink, text on a circle. */
        val spans: List<TextSpan>? = null, val case: String? = null, val minScale: Double? = null, val path: TextPath? = null,
    ) : LayerContent()

    /** `filter` (none, mono, halftone) is applied once when the photo is saved, never in the widget. */
    data class Image(val source: String, val fit: String?, val mask: String?, val cornerRadius: Double?, val filter: String? = null) : LayerContent()

    /** ADR-029 adds line, triangle, polygon, sector, star and scallop (ShapeGeometry). */
    data class Shape(
        val kind: String, val fill: String?, val stroke: Stroke?, val cornerRadius: Double?, val glass: Boolean?,
        val gradient: SpecGradient? = null, val points: List<List<Double>>? = null, val sides: Int? = null, val innerRatio: Double? = null,
        val startAngle: Double? = null, val endAngle: Double? = null, val progress: String? = null, val direction: String? = null,
    ) : LayerContent()

    data class Icon(val symbol: String, val size: Double, val color: String, val style: String? = null) : LayerContent()

    data class AnalogClock(
        val style: String?, val faceColor: String?, val tickColor: String?, val hourColor: String?,
        val minuteColor: String?, val accentColor: String?, val timezone: String?,
        val hourWidth: Double? = null, val minuteWidth: Double? = null, val handCap: String? = null, val hourLength: Double? = null,
        val minuteLength: Double? = null, val ticks: String? = null, val seconds: String? = null, val centerDot: Boolean? = null,
    ) : LayerContent()

    data class DotGrid(
        val rows: Int, val cols: Int, val dotSize: Double, val gap: Double, val onColor: String,
        val offColor: String, val values: String, val highlightColor: String?,
        val levelColors: List<String>? = null, val mask: String? = null, val sizeByLevel: Boolean? = null, val order: String? = null, val fade: String? = null,
    ) : LayerContent()

    data class DotBars(
        val bars: Int, val maxDots: Int, val values: String, val color: String, val offColor: String?,
        val labels: LText?, val highlightColor: String?,
    ) : LayerContent()

    data class Ring(val progress: String, val color: String, val trackColor: String?, val lineWidth: Double) : LayerContent()

    data class ForecastRow(
        val days: Int, val color: String, val mode: String? = null, val font: FontSpec? = null, val iconStyle: String? = null,
        val showLow: Boolean? = null, val dividerColor: String? = null, val labelColor: String? = null, val showIcons: Boolean? = null,
    ) : LayerContent()

    data class Button(val action: String, val arg: String?) : LayerContent()

    data class CalendarMonth(
        val font: FontSpec, val color: String, val titleFormat: String?, val titleCase: String?, val titleFont: FontSpec?,
        val titleColor: String?, val titleAlign: String?, val weekdays: String?, val weekdayFont: FontSpec?,
        val weekdayColor: String?, val weekStart: String?, val weekendDays: List<String>?, val weekendColor: String?,
        val todayStyle: String?, val todayColor: String?, val todayTextColor: String?, val otherDays: String?,
        /** ADR-029: month, week or 2weeks. */
        val rows: String? = null,
    ) : LayerContent() {
        val effectiveTitleFont get() = titleFont ?: FontSpec(font.family, font.size * 1.6, "bold")
        val effectiveWeekdayFont get() = weekdayFont ?: FontSpec(font.family, font.size, "semibold")
    }

    data class ListL(
        val items: List<ListItem>, val font: FontSpec, val color: String, val detailColor: String?, val marker: String?,
        val markerColor: String?, val dividerColor: String?,
    ) : LayerContent()

    /** [vertical] fills from the bottom up: a volume or brightness slider (ADR-027). */
    data class ProgressBar(
        val progress: String, val color: String, val trackColor: String?, val segments: Int?, val cornerRadius: Double?, val vertical: Boolean? = null,
        val knob: Knob? = null,
    ) : LayerContent()

    /** axis `radial` (ADR-029): children around a circle. */
    data class Stack(
        val axis: String, val spacing: Double?, val padding: Double?, val alignItems: String?, val justify: String?,
        val columns: Int?, val children: List<Layer>,
        val radius: Double? = null, val startAngle: Double? = null, val sweep: Double? = null, val rotateChildren: Boolean? = null,
    ) : LayerContent()

    /** A chart of one series (ChartLayer, ADR-029). */
    data class Chart(
        val kind: String, val values: String, val color: String, val fill: String? = null, val gradient: SpecGradient? = null,
        val lineWidth: Double? = null, val barWidth: Double? = null, val cornerRadius: Double? = null, val baseline: String? = null,
        val baselineColor: String? = null, val min: Double? = null, val max: Double? = null, val highlight: String? = null,
        val highlightColor: String? = null, val xLabels: LText? = null, val yLabels: LText? = null, val labelFont: FontSpec? = null,
        val labelColor: String? = null, val downColor: String? = null, val smooth: Boolean? = null,
    ) : LayerContent() {
        companion object {
            /** low/high per point; candles take "low:high" pairs (ChartLayer.parse). */
            fun parse(text: String): List<Pair<Double, Double>>? {
                val items = text.split(",").map { it.trim() }.filter { it.isNotEmpty() }
                if (items.isEmpty() || items.size > 400) return null
                return items.map { item ->
                    val parts = item.split(":")
                    val numbers = parts.map { it.trim().toDoubleOrNull() ?: return null }
                    when (numbers.size) {
                        1 -> numbers[0] to numbers[0]
                        2 -> minOf(numbers[0], numbers[1]) to maxOf(numbers[0], numbers[1])
                        else -> return null
                    }
                }
            }
        }
    }

    data class Spacer(val minLength: Double?) : LayerContent()

    /**
     * One look per state, chosen by real data (States.swift, ADR-028): [set] is a built-in set of the
     * catalog, [variants] writes them out. The first variant whose `when` holds is drawn.
     */
    data class States(
        val set: String?, val value: String?, val color: String, val accent: String, val dim: String, val box: List<Double>?, val variants: List<StateVariant>?,
    ) : LayerContent() {
        val expanded: List<StateVariant>
            get() = variants ?: set?.let { StateSets.variants(it, value ?: "", color, accent, dim) } ?: emptyList()

        /** The coordinate space of the variants. */
        fun boxSize(frame: Frame): Pair<Double, Double> {
            val own = box ?: set?.let { Capabilities.stateSet(it)?.box }
            return if (own != null && own.size == 2 && own[0] > 0 && own[1] > 0) own[0] to own[1] else maxOf(frame.w, 1.0) to maxOf(frame.h, 1.0)
        }

        /** Names this layer's states in a render's forced states (the editor's preview). */
        val key: String get() = set ?: variants?.firstOrNull()?.id ?: "states"
    }

    data class Unknown(val type: String) : LayerContent()
}

/** Theme color tokens (TEMPLATES.md "Style tokens", ADR-011), same values as SpecTokens.swift. */
object SpecTokens {
    val names = listOf("bg", "fg", "muted", "accent", "outer", "line", "dim", "onAccent")

    fun hex(name: String, theme: Theme): String? {
        val light = theme == Theme.LIGHT
        return when (name) {
            "bg" -> if (light) "#FFFFFF" else "#0E0E0E"
            "fg" -> if (light) "#0E0E0E" else "#FFFFFF"
            "muted" -> if (light) "#8A8A8A" else "#7A7A7A"
            "accent" -> "#E2231A"
            "outer" -> if (light) "#E6E9EC" else "#000000"
            "line" -> if (light) "#0E0E0E1F" else "#FFFFFF26"
            "dim" -> if (light) "#0E0E0E1A" else "#FFFFFF26"
            "onAccent" -> "#FFFFFF"
            else -> null
        }
    }
}

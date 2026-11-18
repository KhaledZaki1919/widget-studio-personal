package com.khaled.widgetstudio.spec

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Reads spec JSON into [WidgetSpec], with the same defaults as the Swift decoder. */
object SpecParser {
    private val json = Json { ignoreUnknownKeys = true }

    class SpecException(message: String) : Exception(message)

    fun parse(text: String): WidgetSpec = spec(json.parseToJsonElement(text).jsonObject)

    fun spec(o: JsonObject): WidgetSpec = WidgetSpec(
        // ADR-029: AI replies write specVersion; saved designs and templates schemaVersion.
        schemaVersion = o.int("schemaVersion") ?: o.int("specVersion") ?: throw SpecException("missing schemaVersion"),
        id = o.str("id") ?: throw SpecException("missing id"),
        name = o.ltext("name") ?: throw SpecException("missing name"),
        family = Family.of(o.str("family") ?: "small"),
        theme = if (o.str("theme") == "light") Theme.LIGHT else Theme.DARK,
        refresh = o.str("refresh") ?: "none",
        background = background(o.obj("background") ?: throw SpecException("missing background")),
        fields = o.arr("fields")?.map { field(it.jsonObject) } ?: emptyList(),
        layers = o.arr("layers")?.map { layer(it.jsonObject, child = false) } ?: throw SpecException("missing layers"),
        category = o.str("category"),
        decorative = o.arr("decorative")?.mapNotNull { item ->
            val note = item as? JsonObject ?: return@mapNotNull null
            DecorativeNote(note.str("element") ?: return@mapNotNull null, note.str("reason") ?: "")
        } ?: emptyList(),
        card = o.obj("card")?.let { c ->
            CardSpec(
                c.str("shape"), c.num("aspect"), c.obj("inset")?.let { Frame(it.num("x") ?: 0.0, it.num("y") ?: 0.0, it.num("w") ?: 0.0, it.num("h") ?: 0.0) },
                c.num("cornerRadius"), c.str("orientation"), c.int("bumps"), c.str("outerColor"),
            )
        },
    )

    /** `fill` as a gradient object (ADR-029), else null. */
    private fun gradient(value: JsonElement?): SpecGradient? = (value as? JsonObject)?.let { g ->
        SpecGradient(g.str("type") ?: "linear", g.arr("colors")?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content } ?: emptyList(), g.num("angle"))
    }

    /** A number or a string (rotation, progress, values, baseline). */
    private fun numberOrString(o: JsonObject, key: String): String? =
        (o[key] as? JsonPrimitive)?.takeIf { it.toString() != "null" }?.let { p -> if (p.isString) p.content else p.doubleOrNull?.let(::formatNumber) }

    private fun background(o: JsonObject) = Background(
        type = o.str("type") ?: "solid",
        color = o.str("color"),
        colors = o.arr("colors")?.map { it.jsonPrimitive.content },
        angle = o.num("angle"),
        outerColor = o.str("outerColor"),
        cardShape = o.str("cardShape"),
    )

    private fun field(o: JsonObject) = FieldSpec(
        key = o.str("key") ?: "",
        type = o.str("type") ?: "text",
        label = o.ltext("label") ?: LText.Plain(""),
        default = o.ltext("default"),
    )

    private fun font(o: JsonObject?): FontSpec? = o?.let { FontSpec(it.str("family") ?: "system", it.num("size") ?: 14.0, it.str("weight")) }

    fun layer(o: JsonObject, child: Boolean): Layer {
        // Children of a stack give only width/height (0 or absent = natural size, M6.1).
        val frame = o.obj("frame")?.let { Frame(it.num("x") ?: 0.0, it.num("y") ?: 0.0, it.num("w") ?: 0.0, it.num("h") ?: 0.0) }
            ?: Frame(0.0, 0.0, o.num("width") ?: 0.0, o.num("height") ?: 0.0)
        val rotation = o["rotation"]?.let { (it as? JsonPrimitive)?.let { p -> p.doubleOrNull?.let(::formatNumber) ?: p.content } }
        return Layer(frame, o.num("opacity"), o.bool("mirror"), o.str("when"), rotation, content(o))
    }

    private fun formatNumber(value: Double): String = if (value == Math.rint(value)) value.toLong().toString() else value.toString()

    private fun content(o: JsonObject): LayerContent = when (val type = o.str("type")) {
        "text" -> {
            val live = o.obj("live")
            val spans = o.arr("spans")?.mapNotNull { item ->
                val s = item as? JsonObject ?: return@mapNotNull null
                TextSpan(s.ltext("text") ?: LText.Plain(""), font(s.obj("font")), s.str("color"), s.num("baselineOffset"), s.str("case"), s.num("tracking"))
            }
            // With spans, `value` may be left out: it is then the spans' text.
            val joined = spans?.takeIf { it.isNotEmpty() }?.let { list ->
                val en = list.joinToString("") { it.text.resolved("en") }
                val ar = list.joinToString("") { it.text.resolved("ar") }
                if (en == ar) LText.Plain(en) else LText.Localized(en, ar)
            }
            LayerContent.Text(
                o.ltext("value") ?: joined ?: LText.Plain(""), font(o.obj("font")) ?: FontSpec("system", 14.0, null), o.str("color") ?: "#FFFFFF",
                o.str("align"), o.int("maxLines"), o.num("tracking"), live?.str("kind"), live?.str("target"),
                spans, o.str("case"), o.num("minScale"), o.obj("path")?.let { TextPath(it.num("arc"), it.num("start"), it.bool("inside")) },
            )
        }
        "image" -> LayerContent.Image(o.str("source") ?: "user_image", o.str("fit"), o.str("mask"), o.num("cornerRadius"), o.str("filter"))
        "shape" -> {
            val gradient = gradient(o["fill"])
            LayerContent.Shape(
                o.str("kind") ?: "rect", o.str("fill") ?: gradient?.colors?.firstOrNull(),
                o.obj("stroke")?.let { Stroke(it.str("color") ?: "#FFFFFF", it.num("width") ?: 1.0, it.arr("dash")?.mapNotNull { d -> d.jsonPrimitive.doubleOrNull }) },
                o.num("cornerRadius"), o.bool("glass"),
                gradient, o.arr("points")?.mapNotNull { p -> (p as? JsonArray)?.mapNotNull { (it as? JsonPrimitive)?.doubleOrNull } },
                o.int("sides"), o.num("innerRatio"), o.num("startAngle"), o.num("endAngle"), numberOrString(o, "progress"), o.str("direction"),
            )
        }
        "icon" -> LayerContent.Icon(o.str("symbol") ?: "questionmark", o.num("size") ?: 20.0, o.str("color") ?: "#FFFFFF", o.str("style"))
        "analogClock" -> LayerContent.AnalogClock(
            o.str("style"), o.str("faceColor"), o.str("tickColor"), o.str("hourColor"), o.str("minuteColor"), o.str("accentColor"), o.str("timezone"),
            o.num("hourWidth"), o.num("minuteWidth"), o.str("handCap"), o.num("hourLength"), o.num("minuteLength"), numberOrString(o, "ticks"),
            o.str("seconds"), o.bool("centerDot"),
        )
        "dotGrid" -> LayerContent.DotGrid(
            o.int("rows") ?: 1, o.int("cols") ?: 1, o.num("dotSize") ?: 4.0, o.num("gap") ?: 2.0, o.str("onColor") ?: "#FFFFFF",
            o.str("offColor") ?: "#FFFFFF26", numberOrString(o, "values") ?: "", o.str("highlightColor"),
            o.arr("levelColors")?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content }, o.str("mask"), o.bool("sizeByLevel"),
            o.str("order"), o.str("fade"),
        )
        "chart" -> LayerContent.Chart(
            o.str("kind") ?: "line", numberOrString(o, "values") ?: "", o.str("color") ?: "#FFFFFF", o.str("fill"), gradient(o["fill"]),
            o.num("lineWidth"), o.num("barWidth"), o.num("cornerRadius"), numberOrString(o, "baseline"), o.str("baselineColor"), o.num("min"),
            o.num("max"), o.str("highlight"), o.str("highlightColor"), o.ltext("xLabels"), o.ltext("yLabels"), font(o.obj("labelFont")),
            o.str("labelColor"), o.str("downColor"), o.bool("smooth"),
        )
        "dotBars" -> LayerContent.DotBars(
            o.int("bars") ?: 7, o.int("maxDots") ?: 8, o.str("values") ?: "", o.str("color") ?: "#FFFFFF", o.str("offColor"),
            o.ltext("labels"), o.str("highlightColor"),
        )
        "ring" -> LayerContent.Ring(o.str("progress") ?: "0", o.str("color") ?: "#FFFFFF", o.str("trackColor"), o.num("lineWidth") ?: 6.0)
        "forecastRow" -> LayerContent.ForecastRow(
            o.int("days") ?: 5, o.str("color") ?: "#FFFFFF", o.str("mode"), font(o.obj("font")), o.str("iconStyle"), o.bool("showLow"),
            o.str("dividerColor"), o.str("labelColor"), o.bool("showIcons"),
        )
        "button" -> LayerContent.Button(o.str("action") ?: "open.app", o.str("arg"))
        "calendarMonth" -> LayerContent.CalendarMonth(
            font(o.obj("font")) ?: FontSpec("system", 11.0, null), o.str("color") ?: "#FFFFFF", o.str("titleFormat"), o.str("titleCase"),
            font(o.obj("titleFont")), o.str("titleColor"), o.str("titleAlign"), o.str("weekdays"), font(o.obj("weekdayFont")),
            o.str("weekdayColor"), o.str("weekStart"), o.arr("weekendDays")?.map { it.jsonPrimitive.content }, o.str("weekendColor"),
            o.str("todayStyle"), o.str("todayColor"), o.str("todayTextColor"), o.str("otherDays"), o.str("rows"),
        )
        "list" -> LayerContent.ListL(
            o.arr("items")?.map { item ->
                val i = item.jsonObject
                ListItem(i.ltext("title") ?: LText.Plain(""), i.ltext("detail"), i.str("icon"), i.str("color"), i.str("done"), i.ltext("subtitle"), i.ltext("detail2"))
            } ?: emptyList(),
            font(o.obj("font")) ?: FontSpec("system", 13.0, null), o.str("color") ?: "#FFFFFF", o.str("detailColor"), o.str("marker"),
            o.str("markerColor"), o.str("dividerColor"),
        )
        "progressBar" -> LayerContent.ProgressBar(
            numberOrString(o, "progress") ?: "0", o.str("color") ?: "#FFFFFF", o.str("trackColor"), o.int("segments"), o.num("cornerRadius"), o.bool("vertical"),
            o.obj("knob")?.let { Knob(it.num("size"), it.str("color")) },
        )
        "stack" -> LayerContent.Stack(
            o.str("axis") ?: "vertical", o.num("spacing"), o.num("padding"), o.str("alignItems"), o.str("justify"), o.int("columns"),
            o.arr("children")?.map { layer(it.jsonObject, child = true) } ?: emptyList(),
            o.num("radius"), o.num("startAngle"), o.num("sweep"), o.bool("rotateChildren"),
        )
        "spacer" -> LayerContent.Spacer(o.num("minLength"))
        "states" -> LayerContent.States(
            o.str("set"), o.str("value"), o.str("color") ?: "@fg", o.str("accent") ?: "@accent", o.str("dim") ?: "@dim",
            o.arr("box")?.mapNotNull { it.jsonPrimitive.doubleOrNull }, o.arr("variants")?.map { variant(it.jsonObject) },
        )
        else -> LayerContent.Unknown(type ?: "")
    }

    fun variant(o: JsonObject) = StateVariant(
        o.str("id") ?: "", o.ltext("title"), o.str("when"), o.arr("layers")?.map { layer(it.jsonObject, child = false) } ?: emptyList(),
        o.obj("sample")?.mapValues { (_, value) -> value.jsonPrimitive.content },
    )

    // MARK: JSON helpers (null values count as absent, like the Swift decoder after removingNulls)

    private fun JsonObject.prim(key: String): JsonPrimitive? = (this[key] as? JsonPrimitive)?.takeIf { it.toString() != "null" }
    private fun JsonObject.str(key: String): String? = prim(key)?.takeIf { it.isString }?.content
    private fun JsonObject.num(key: String): Double? = prim(key)?.doubleOrNull
    private fun JsonObject.int(key: String): Int? = prim(key)?.intOrNull ?: prim(key)?.doubleOrNull?.toInt()
    private fun JsonObject.bool(key: String): Boolean? = prim(key)?.booleanOrNull
    private fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject
    private fun JsonObject.arr(key: String): JsonArray? = this[key] as? JsonArray

    private fun JsonObject.ltext(key: String): LText? = when (val value: JsonElement? = this[key]) {
        is JsonPrimitive -> if (value.isString) LText.Plain(value.content) else null
        is JsonObject -> {
            val en = value.str("en")
            val ar = value.str("ar")
            if (en != null && ar != null) LText.Localized(en, ar) else null
        }
        else -> null
    }
}

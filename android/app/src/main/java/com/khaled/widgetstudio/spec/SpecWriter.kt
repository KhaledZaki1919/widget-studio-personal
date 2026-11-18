package com.khaled.widgetstudio.spec

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/** Writes a [WidgetSpec] as spec JSON (the inverse of [SpecParser]); absent values are left out. */
object SpecWriter {
    fun write(spec: WidgetSpec): JsonObject = buildJsonObject {
        put("schemaVersion", spec.schemaVersion)
        put("id", spec.id)
        spec.category?.let { put("category", it) }
        put("name", ltext(spec.name))
        put("family", spec.family.name.lowercase())
        put("theme", spec.theme.name.lowercase())
        put("refresh", spec.refresh)
        put("background", background(spec.background))
        if (spec.fields.isNotEmpty()) put("fields", JsonArray(spec.fields.map(::field)))
        put("layers", JsonArray(spec.layers.map { layer(it, child = false) }))
        spec.card?.let { card ->
            put("card", buildJsonObject {
                card.shape?.let { put("shape", it) }; card.aspect?.let { put("aspect", it) }
                card.inset?.let { f -> put("inset", buildJsonObject { put("x", f.x); put("y", f.y); put("w", f.w); put("h", f.h) }) }
                card.cornerRadius?.let { put("cornerRadius", it) }; card.orientation?.let { put("orientation", it) }
                card.bumps?.let { put("bumps", it) }; card.outerColor?.let { put("outerColor", it) }
            })
        }
        if (spec.decorative.isNotEmpty()) {
            put("decorative", JsonArray(spec.decorative.map { note -> buildJsonObject { put("element", note.element); put("reason", note.reason) } }))
        }
    }

    fun ltext(text: LText): JsonElement = when (text) {
        is LText.Plain -> JsonPrimitive(text.text)
        is LText.Localized -> buildJsonObject {
            put("en", text.en)
            put("ar", text.ar)
        }
    }

    private fun background(b: Background) = buildJsonObject {
        put("type", b.type)
        b.color?.let { put("color", it) }
        b.colors?.let { put("colors", JsonArray(it.map(::JsonPrimitive))) }
        b.angle?.let { put("angle", it) }
        b.outerColor?.let { put("outerColor", it) }
        b.cardShape?.let { put("cardShape", it) }
    }

    private fun field(f: FieldSpec) = buildJsonObject {
        put("key", f.key)
        put("type", f.type)
        put("label", ltext(f.label))
        f.default?.let { put("default", ltext(it)) }
    }

    private fun gradient(g: SpecGradient) = buildJsonObject {
        put("type", g.type)
        put("colors", JsonArray(g.colors.map(::JsonPrimitive)))
        g.angle?.let { put("angle", it) }
    }

    private fun font(f: FontSpec) = buildJsonObject {
        put("family", f.family)
        put("size", f.size)
        f.weight?.let { put("weight", it) }
    }

    fun layer(layer: Layer, child: Boolean): JsonObject {
        val fields = linkedMapOf<String, JsonElement>()
        fun set(key: String, value: Any?) {
            when (value) {
                null -> Unit
                is JsonElement -> fields[key] = value
                is String -> fields[key] = JsonPrimitive(value)
                is Number -> fields[key] = JsonPrimitive(value)
                is Boolean -> fields[key] = JsonPrimitive(value)
            }
        }
        set("type", typeName(layer.content))
        if (child) {
            if (layer.frame.w > 0) set("width", layer.frame.w)
            if (layer.frame.h > 0) set("height", layer.frame.h)
        } else {
            set("frame", buildJsonObject {
                put("x", layer.frame.x)
                put("y", layer.frame.y)
                put("w", layer.frame.w)
                put("h", layer.frame.h)
            })
        }
        set("opacity", layer.opacity)
        set("mirror", layer.mirror)
        set("when", layer.condition)
        set("rotation", layer.rotation)
        when (val c = layer.content) {
            is LayerContent.Text -> {
                set("value", ltext(c.value)); set("font", font(c.font)); set("color", c.color); set("align", c.align)
                set("maxLines", c.maxLines); set("tracking", c.tracking)
                if (c.liveKind != null) set("live", buildJsonObject { put("kind", c.liveKind); c.liveTarget?.let { put("target", it) } })
                c.spans?.let { spans ->
                    set("spans", JsonArray(spans.map { span ->
                        buildJsonObject {
                            put("text", ltext(span.text)); span.font?.let { put("font", font(it)) }; span.color?.let { put("color", it) }
                            span.baselineOffset?.let { put("baselineOffset", it) }; span.case?.let { put("case", it) }; span.tracking?.let { put("tracking", it) }
                        }
                    }))
                }
                set("case", c.case); set("minScale", c.minScale)
                c.path?.let { p -> set("path", buildJsonObject { p.arc?.let { put("arc", it) }; p.start?.let { put("start", it) }; p.inside?.let { put("inside", it) } }) }
            }
            is LayerContent.Image -> { set("source", c.source); set("fit", c.fit); set("mask", c.mask); set("cornerRadius", c.cornerRadius); set("filter", c.filter) }
            is LayerContent.Shape -> {
                set("kind", c.kind); set("fill", c.gradient?.let(::gradient) ?: c.fill); set("cornerRadius", c.cornerRadius); set("glass", c.glass)
                c.points?.let { points -> set("points", JsonArray(points.map { p -> JsonArray(p.map(::JsonPrimitive)) })) }
                set("sides", c.sides); set("innerRatio", c.innerRatio); set("startAngle", c.startAngle); set("endAngle", c.endAngle)
                set("progress", c.progress); set("direction", c.direction)
                c.stroke?.let { s -> set("stroke", buildJsonObject { put("color", s.color); put("width", s.width); s.dash?.let { put("dash", JsonArray(it.map(::JsonPrimitive))) } }) }
            }
            is LayerContent.Icon -> { set("symbol", c.symbol); set("size", c.size); set("color", c.color); set("style", c.style) }
            is LayerContent.AnalogClock -> {
                set("style", c.style); set("faceColor", c.faceColor); set("tickColor", c.tickColor); set("hourColor", c.hourColor)
                set("minuteColor", c.minuteColor); set("accentColor", c.accentColor); set("timezone", c.timezone)
                set("hourWidth", c.hourWidth); set("minuteWidth", c.minuteWidth); set("handCap", c.handCap); set("hourLength", c.hourLength)
                set("minuteLength", c.minuteLength); set("ticks", c.ticks); set("seconds", c.seconds); set("centerDot", c.centerDot)
            }
            is LayerContent.DotGrid -> {
                set("rows", c.rows); set("cols", c.cols); set("dotSize", c.dotSize); set("gap", c.gap); set("onColor", c.onColor)
                set("offColor", c.offColor); set("values", c.values); set("highlightColor", c.highlightColor)
                c.levelColors?.let { set("levelColors", JsonArray(it.map(::JsonPrimitive))) }
                set("mask", c.mask); set("sizeByLevel", c.sizeByLevel); set("order", c.order); set("fade", c.fade)
            }
            is LayerContent.Chart -> {
                set("kind", c.kind); set("values", c.values); set("color", c.color); set("fill", c.gradient?.let(::gradient) ?: c.fill)
                set("lineWidth", c.lineWidth); set("barWidth", c.barWidth); set("cornerRadius", c.cornerRadius); set("baseline", c.baseline)
                set("baselineColor", c.baselineColor); set("min", c.min); set("max", c.max); set("highlight", c.highlight)
                set("highlightColor", c.highlightColor); c.xLabels?.let { set("xLabels", ltext(it)) }; c.yLabels?.let { set("yLabels", ltext(it)) }
                c.labelFont?.let { set("labelFont", font(it)) }; set("labelColor", c.labelColor); set("downColor", c.downColor); set("smooth", c.smooth)
            }
            is LayerContent.DotBars -> {
                set("bars", c.bars); set("maxDots", c.maxDots); set("values", c.values); set("color", c.color); set("offColor", c.offColor)
                c.labels?.let { set("labels", ltext(it)) }; set("highlightColor", c.highlightColor)
            }
            is LayerContent.Ring -> { set("progress", c.progress); set("color", c.color); set("trackColor", c.trackColor); set("lineWidth", c.lineWidth) }
            is LayerContent.ForecastRow -> {
                set("days", c.days); set("color", c.color); set("mode", c.mode); c.font?.let { set("font", font(it)) }; set("iconStyle", c.iconStyle)
                set("showLow", c.showLow); set("dividerColor", c.dividerColor); set("labelColor", c.labelColor); set("showIcons", c.showIcons)
            }
            is LayerContent.Button -> { set("action", c.action); set("arg", c.arg) }
            is LayerContent.CalendarMonth -> {
                set("font", font(c.font)); set("color", c.color); set("titleFormat", c.titleFormat); set("titleCase", c.titleCase)
                c.titleFont?.let { set("titleFont", font(it)) }; set("titleColor", c.titleColor); set("titleAlign", c.titleAlign)
                set("weekdays", c.weekdays); c.weekdayFont?.let { set("weekdayFont", font(it)) }; set("weekdayColor", c.weekdayColor)
                set("weekStart", c.weekStart); c.weekendDays?.let { set("weekendDays", JsonArray(it.map(::JsonPrimitive))) }
                set("weekendColor", c.weekendColor); set("todayStyle", c.todayStyle); set("todayColor", c.todayColor)
                set("todayTextColor", c.todayTextColor); set("otherDays", c.otherDays); set("rows", c.rows)
            }
            is LayerContent.ListL -> {
                set("items", JsonArray(c.items.map { item ->
                    buildJsonObject {
                        put("title", ltext(item.title)); item.detail?.let { put("detail", ltext(it)) }
                        item.icon?.let { put("icon", it) }; item.color?.let { put("color", it) }; item.done?.let { put("done", it) }
                        item.subtitle?.let { put("subtitle", ltext(it)) }; item.detail2?.let { put("detail2", ltext(it)) }
                    }
                }))
                set("font", font(c.font)); set("color", c.color); set("detailColor", c.detailColor); set("marker", c.marker)
                set("markerColor", c.markerColor); set("dividerColor", c.dividerColor)
            }
            is LayerContent.ProgressBar -> { set("progress", c.progress); set("color", c.color); set("trackColor", c.trackColor); set("segments", c.segments); set("cornerRadius", c.cornerRadius); set("vertical", c.vertical)
                c.knob?.let { k -> set("knob", buildJsonObject { k.size?.let { put("size", it) }; k.color?.let { put("color", it) } }) }
            }
            is LayerContent.Stack -> {
                set("axis", c.axis); set("spacing", c.spacing); set("padding", c.padding); set("alignItems", c.alignItems)
                set("justify", c.justify); set("columns", c.columns); set("children", JsonArray(c.children.map { layer(it, child = true) }))
                set("radius", c.radius); set("startAngle", c.startAngle); set("sweep", c.sweep); set("rotateChildren", c.rotateChildren)
            }
            is LayerContent.Spacer -> set("minLength", c.minLength)
            is LayerContent.States -> {
                set("set", c.set); set("value", c.value); set("color", c.color); set("accent", c.accent); set("dim", c.dim)
                c.box?.let { box -> set("box", JsonArray(box.map(::JsonPrimitive))) }
                c.variants?.let { variants -> set("variants", JsonArray(variants.map(::variant))) }
            }
            is LayerContent.Unknown -> Unit
        }
        return JsonObject(fields)
    }

    private fun variant(v: StateVariant) = buildJsonObject {
        put("id", v.id)
        v.title?.let { put("title", ltext(it)) }
        v.condition?.let { put("when", it) }
        put("layers", JsonArray(v.layers.map { layer(it, child = false) }))
        v.sample?.let { sample -> put("sample", JsonObject(sample.mapValues { (_, value) -> JsonPrimitive(value) })) }
    }

    fun typeName(content: LayerContent) = when (content) {
        is LayerContent.Text -> "text"
        is LayerContent.Image -> "image"
        is LayerContent.Shape -> "shape"
        is LayerContent.Icon -> "icon"
        is LayerContent.AnalogClock -> "analogClock"
        is LayerContent.DotGrid -> "dotGrid"
        is LayerContent.DotBars -> "dotBars"
        is LayerContent.Ring -> "ring"
        is LayerContent.ForecastRow -> "forecastRow"
        is LayerContent.Button -> "button"
        is LayerContent.CalendarMonth -> "calendarMonth"
        is LayerContent.ListL -> "list"
        is LayerContent.ProgressBar -> "progressBar"
        is LayerContent.Stack -> "stack"
        is LayerContent.Spacer -> "spacer"
        is LayerContent.States -> "states"
        is LayerContent.Chart -> "chart"
        is LayerContent.Unknown -> content.type
    }
}

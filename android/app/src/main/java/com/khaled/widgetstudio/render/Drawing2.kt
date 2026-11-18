package com.khaled.widgetstudio.render

import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PointF
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import com.khaled.widgetstudio.spec.CardSpec
import com.khaled.widgetstudio.spec.FontSpec
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.SpecGradient
import com.khaled.widgetstudio.spec.SpecTokens
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// ADR-029: shapes, gradients and charts (DrawingViews.swift). Angles are degrees clockwise from 12 o'clock.

/** Paths for every shape kind and card outline (ShapeGeometry in Swift). */
object ShapeGeometry {
    fun point(rect: RectF, degrees: Double, share: Double = 1.0): PointF {
        val radians = Math.toRadians(degrees)
        return PointF(rect.centerX() + (sin(radians) * share).toFloat() * rect.width() / 2, rect.centerY() - (cos(radians) * share).toFloat() * rect.height() / 2)
    }

    fun scallop(rect: RectF, bumps: Int, depth: Double = 0.07): Path = Path().apply {
        val count = bumps.coerceIn(3, 40)
        val steps = 240
        for (step in 0..steps) {
            val theta = step.toDouble() / steps * 360
            val p = point(rect, theta, 1 - depth + depth * cos(count * Math.toRadians(theta)))
            if (step == 0) moveTo(p.x, p.y) else lineTo(p.x, p.y)
        }
        close()
    }

    fun polygon(points: List<PointF>): Path = Path().apply {
        points.firstOrNull()?.let { moveTo(it.x, it.y) } ?: return@apply
        points.drop(1).forEach { lineTo(it.x, it.y) }
        close()
    }

    fun regular(rect: RectF, sides: Int): Path {
        val count = sides.coerceIn(3, 24)
        return polygon((0 until count).map { point(rect, it * 360.0 / count) })
    }

    fun star(rect: RectF, rays: Int, inner: Double): Path {
        val count = rays.coerceIn(3, 24)
        return polygon((0 until count * 2).map { point(rect, it * 180.0 / count, if (it % 2 == 0) 1.0 else inner.coerceIn(0.05, 0.95)) })
    }

    fun sector(rect: RectF, start: Double, end: Double, inner: Double): Path = Path().apply {
        val sweep = (end - start).coerceIn(0.0, 360.0)
        if (sweep <= 0) return@apply
        val steps = max(2, (sweep / 3).toInt())
        val hole = inner.coerceIn(0.0, 0.95)
        val first = if (hole > 0) point(rect, start, hole) else PointF(rect.centerX(), rect.centerY())
        moveTo(first.x, first.y)
        for (i in 0..steps) point(rect, start + sweep * i / steps).let { lineTo(it.x, it.y) }
        if (hole > 0) for (i in steps downTo 0) point(rect, start + sweep * i / steps, hole).let { lineTo(it.x, it.y) }
        close()
    }

    fun triangle(rect: RectF, direction: String?): Path = when (direction ?: "up") {
        "down" -> polygon(listOf(PointF(rect.left, rect.top), PointF(rect.right, rect.top), PointF(rect.centerX(), rect.bottom)))
        "left" -> polygon(listOf(PointF(rect.right, rect.top), PointF(rect.right, rect.bottom), PointF(rect.left, rect.centerY())))
        "right" -> polygon(listOf(PointF(rect.left, rect.top), PointF(rect.right, rect.centerY()), PointF(rect.left, rect.bottom)))
        else -> polygon(listOf(PointF(rect.centerX(), rect.top), PointF(rect.right, rect.bottom), PointF(rect.left, rect.bottom)))
    }

    fun line(rect: RectF, direction: String?): Path = Path().apply {
        when (direction ?: if (rect.width() >= rect.height()) "horizontal" else "vertical") {
            "vertical", "up", "down" -> { moveTo(rect.centerX(), rect.top); lineTo(rect.centerX(), rect.bottom) }
            "diagonal" -> { moveTo(rect.left, rect.top); lineTo(rect.right, rect.bottom) }
            "antidiagonal" -> { moveTo(rect.left, rect.bottom); lineTo(rect.right, rect.top) }
            else -> { moveTo(rect.left, rect.centerY()); lineTo(rect.right, rect.centerY()) }
        }
    }

    /** The new kinds of a shape layer; null for rect, roundedRect, circle and capsule (Drawing.shapePath). */
    fun path(shape: LayerContent.Shape, rect: RectF, progress: Double?): Path? = when (shape.kind) {
        "line" -> line(rect, shape.direction)
        "triangle" -> triangle(rect, shape.direction)
        "polygon" -> shape.points?.takeIf { it.size >= 3 }?.let { pts -> polygon(pts.filter { it.size == 2 }.map { PointF(rect.left + it[0].toFloat() * rect.width(), rect.top + it[1].toFloat() * rect.height()) }) }
            ?: regular(rect, shape.sides ?: 6)
        "star" -> star(rect, shape.sides ?: 5, shape.innerRatio ?: 0.45)
        "scallop" -> scallop(rect, shape.sides ?: 12)
        "sector" -> {
            val start = shape.startAngle ?: 0.0
            val end = progress?.let { start + 360 * it.coerceIn(0.0, 1.0) } ?: shape.endAngle ?: (start + 90)
            sector(rect, start, end, shape.innerRatio ?: 0.0)
        }
        else -> null
    }

    /** A card outline (ADR-029). */
    fun card(card: CardSpec?, rect: RectF, scale: Float): Path = Path().apply {
        when (card?.shape) {
            "circle" -> addCircle(rect.centerX(), rect.centerY(), min(rect.width(), rect.height()) / 2, Path.Direction.CW)
            "capsule" -> min(rect.width(), rect.height()).div(2).let { addRoundRect(rect, it, it, Path.Direction.CW) }
            "scallop" -> addPath(scallop(rect, card.bumps ?: 12))
            else -> ((card?.cornerRadius ?: 20.0) * scale).toFloat().let { addRoundRect(rect, it, it, Path.Direction.CW) }
        }
    }
}

/** A gradient as a shader over [rect] (like the background: 0° left to right, 90° top to bottom). */
internal fun Drawing.shader(gradient: SpecGradient, rect: RectF): Shader? {
    val colors = gradient.colors.take(4).map { color(it) }.toIntArray()
    if (colors.size < 2) return null
    if (gradient.type == "radial") return RadialGradient(rect.centerX(), rect.centerY(), max(rect.width(), rect.height()) / 2, colors, null, Shader.TileMode.CLAMP)
    val angle = Math.toRadians(gradient.angle ?: 90.0)
    val dx = (cos(angle) / 2).toFloat()
    val dy = (sin(angle) / 2).toFloat()
    return LinearGradient(
        rect.left + rect.width() * (0.5f - dx), rect.top + rect.height() * (0.5f - dy),
        rect.left + rect.width() * (0.5f + dx), rect.top + rect.height() * (0.5f + dy), colors, null, Shader.TileMode.CLAMP,
    )
}

/** Chart layers (ChartView / ChartModel in Swift). */
internal class ChartPainter(private val d: Drawing) {
    private fun muted() = d.color(SpecTokens.hex("muted", d.theme) ?: "#8A8A8A")

    fun draw(canvas: Canvas, chart: LayerContent.Chart, rect: RectF, scale: Float, mirrored: Boolean) {
        val points: List<Pair<Double, Double>> = (d.resolver.soleValue(chart.values) as? com.khaled.widgetstudio.spec.BindingResolver.Value.Levels)?.levels?.map { it to it }
            ?: LayerContent.Chart.parse(chart.values) ?: emptyList()
        val labelFont = chart.labelFont ?: FontSpec("system", 10.0, "medium")
        val labelSize = (labelFont.size * scale).toFloat()
        val language = d.context.language
        val xTexts = chart.xLabels?.let { d.resolver.render(it.resolved(language)).split(",").map(String::trim) } ?: emptyList()
        val yTexts = chart.yLabels?.let { d.resolver.render(it.resolved(language)).split(",").map(String::trim) } ?: emptyList()
        val yWidth = if (yTexts.isEmpty()) 0f else (yTexts.maxOf { it.length }) * labelSize * 0.62f + 4 * scale
        val xHeight = if (xTexts.isEmpty()) 0f else labelSize * 1.5f
        val plot = RectF(rect.left + if (mirrored) 0f else yWidth, rect.top + labelSize * 0.2f, rect.right - if (mirrored) yWidth else 0f, rect.bottom - xHeight)
        if (plot.width() <= 1 || plot.height() <= 1) return
        var low = chart.min ?: (points.minOfOrNull { it.first } ?: 0.0)
        var high = chart.max ?: (points.maxOfOrNull { it.second } ?: 1.0)
        if (chart.kind == "bars" && chart.min == null) low = min(0.0, low)
        if (high - low < 1e-9) high = low + 1
        if (chart.kind != "bars" && chart.min == null && chart.max == null) {
            val pad = (high - low) * 0.08
            low -= pad
            high += pad
        }
        fun y(value: Double) = plot.bottom - ((value - low) / (high - low)).toFloat() * plot.height()
        val count = points.size
        val slot = if (count > 0) plot.width() / count else plot.width()
        fun x(index: Int): Float {
            val position = if (mirrored) count - 1 - index else index
            return when (chart.kind) {
                "bars", "candles" -> plot.left + slot * (position + 0.5f)
                else -> if (count > 1) plot.left + plot.width() * position / (count - 1) else plot.centerX()
            }
        }
        val baseline = when (chart.baseline?.lowercase()) {
            null -> null
            "first" -> points.firstOrNull()?.second
            "average" -> points.takeIf { it.isNotEmpty() }?.map { it.second }?.average()
            else -> chart.baseline.toDoubleOrNull()
        }
        val color = d.color(chart.color)
        val highlightColor = d.color(chart.highlightColor ?: chart.color)
        val highlighted = when (chart.highlight) {
            "last" -> if (count > 0) count - 1 else null
            "max" -> points.indices.maxByOrNull { points[it].second }
            "min" -> points.indices.minByOrNull { points[it].second }
            else -> null
        }
        baseline?.let { value ->
            val p = d.paint(d.color(chart.baselineColor, muted()), Paint.Style.STROKE).apply {
                strokeWidth = max(0.5f, scale)
                pathEffect = DashPathEffect(floatArrayOf(3 * scale, 3 * scale), 0f)
            }
            canvas.drawLine(plot.left, y(value), plot.right, y(value), p)
        }
        when (chart.kind) {
            "bars", "candles" -> {
                val width = slot * (chart.barWidth ?: if (chart.kind == "candles") 0.35 else 0.6).coerceIn(0.05, 1.0).toFloat()
                val zero = y(max(low, min(high, baseline ?: max(low, 0.0))))
                points.forEachIndexed { index, (lo, hi) ->
                    val bar = if (chart.kind == "candles") {
                        val top = y(hi)
                        val bottom = max(y(lo), top + width)
                        RectF(x(index) - width / 2, top, x(index) + width / 2, bottom)
                    } else {
                        val top = y(hi)
                        RectF(x(index) - width / 2, min(top, zero), x(index) + width / 2, max(max(top, zero), min(top, zero) + 1f))
                    }
                    val down = baseline != null && hi < baseline
                    val fill = if (index == highlighted) highlightColor else if (down) d.color(chart.downColor, color) else color
                    val radius = if (chart.kind == "candles") width / 2 else min(((chart.cornerRadius ?: 2.0) * scale).toFloat(), width / 2)
                    canvas.drawRoundRect(bar, radius, radius, d.paint(fill))
                }
            }
            else -> {
                val centers = points.indices.map { PointF(x(it), y(points[it].second)) }
                val line = Path()
                centers.forEachIndexed { index, p ->
                    if (index == 0) line.moveTo(p.x, p.y) else {
                        if (chart.kind == "steps") line.lineTo(p.x, centers[index - 1].y)
                        line.lineTo(p.x, p.y)
                    }
                }
                if (centers.isNotEmpty() && (chart.kind == "area" || chart.fill != null || chart.gradient != null)) {
                    val area = Path(line).apply {
                        lineTo(centers.last().x, plot.bottom)
                        lineTo(centers.first().x, plot.bottom)
                        close()
                    }
                    val paint = Paint(Paint.ANTI_ALIAS_FLAG)
                    when {
                        chart.gradient != null -> paint.shader = d.shader(chart.gradient, plot)
                        chart.fill != null -> paint.color = d.color(chart.fill)
                        else -> paint.shader = LinearGradient(0f, plot.top, 0f, plot.bottom, d.withAlpha(color, 0.35), d.withAlpha(color, 0.0), Shader.TileMode.CLAMP)
                    }
                    canvas.drawPath(area, paint)
                }
                canvas.drawPath(line, d.paint(color, Paint.Style.STROKE).apply {
                    strokeWidth = ((chart.lineWidth ?: 2.0) * scale).toFloat()
                    strokeCap = Paint.Cap.ROUND
                    strokeJoin = Paint.Join.ROUND
                })
                highlighted?.let { index -> centers.getOrNull(index)?.let { canvas.drawCircle(it.x, it.y, ((chart.lineWidth ?: 2.0) * scale * 1.25).toFloat(), d.paint(highlightColor)) } }
            }
        }
        val labelColor = d.color(chart.labelColor, muted())
        val labelY = plot.bottom + labelSize * 0.25f
        xTexts.forEachIndexed { index, text ->
            val share = if (xTexts.size > 1) index.toFloat() / (xTexts.size - 1) else 0.5f
            val position = if (mirrored) 1 - share else share
            val inset = labelSize * text.length * 0.31f
            val cx = plot.left + inset + (plot.width() - 2 * inset) * position
            d.text.drawFitted(canvas, text, labelFont, labelColor, "center", 1, null, RectF(cx - inset - labelSize, labelY, cx + inset + labelSize, labelY + labelSize * 1.25f), scale)
        }
        val labelLeft = if (mirrored) plot.right else rect.left
        yTexts.forEachIndexed { index, text ->
            val share = if (yTexts.size > 1) index.toFloat() / (yTexts.size - 1) else 0.5f
            val cy = plot.top + plot.height() * share
            d.text.drawFitted(canvas, text, labelFont, labelColor, if (mirrored) "trailing" else "leading", 1, null,
                RectF(labelLeft, cy - labelSize * 0.7f, labelLeft + yWidth - 2 * scale, cy + labelSize * 0.7f), scale)
        }
    }

    @Suppress("unused")
    private fun near(a: Float, b: Float) = abs(a - b) < 0.5f
}

/** A dot grid with ADR-029's options (DotGridView.swift): levels, level colors, a mask, fill order, halftone size and fade. */
internal class DotGridPainter(private val d: Drawing) {
    fun draw(canvas: Canvas, grid: LayerContent.DotGrid, rect: RectF, scale: Float, mirrored: Boolean) {
        val cells = grid.rows * grid.cols
        val levels = DotGridLayout.levels(d.resolver, grid)
        val on = d.color(grid.onColor)
        val off = d.color(grid.offColor)
        val highlight = d.color(grid.highlightColor ?: grid.onColor)
        val bands = grid.levelColors?.map { d.color(it) }
        val dot = (grid.dotSize * scale).toFloat()
        val gap = (grid.gap * scale).toFloat()
        val width = grid.cols * dot + (grid.cols - 1) * gap
        val height = grid.rows * dot + (grid.rows - 1) * gap
        val left = rect.left + (rect.width() - width) / 2
        val top = rect.top + (rect.height() - height) / 2
        val box = RectF(left, top, left + width, top + height)
        val mask = grid.mask?.let { DotGridLayout.maskName(it, d.resolver) }?.let { ShapeGeometry.mask(it, box) }
        val region = mask?.let { android.graphics.Region().apply { setPath(it, android.graphics.Region(box.left.toInt() - 1, box.top.toInt() - 1, box.right.toInt() + 1, box.bottom.toInt() + 1)) } }
        for (index in 0 until cells) {
            val row = index / grid.cols
            val col = index % grid.cols
            val level = levels.getOrElse(index) { 0.0 }
            if (level < 0) continue
            val column = if (mirrored) grid.cols - 1 - col else col
            val x = left + column * (dot + gap) + dot / 2
            val y = top + row * (dot + gap) + dot / 2
            if (region != null && !region.contains(x.toInt(), y.toInt())) continue
            val fade = DotGridLayout.fade(grid.fade, column.toFloat() / maxOf(grid.cols - 1, 1), row.toFloat() / maxOf(grid.rows - 1, 1))
            val radius = dot / 2 * fade
            if (grid.sizeByLevel == true) {
                if (level > 0) canvas.drawCircle(x, y, radius * maxOf(0.15f, level.coerceAtMost(1.0).toFloat()), d.paint(if (level >= 2) highlight else DotGridLayout.band(bands, level) ?: on))
                else if (android.graphics.Color.alpha(off) > 0) canvas.drawCircle(x, y, radius, d.paint(off))
                continue
            }
            canvas.drawCircle(x, y, radius, d.paint(off))
            when {
                level >= 2 -> canvas.drawCircle(x, y, radius, d.paint(highlight))
                level > 0 -> {
                    val band = DotGridLayout.band(bands, level)
                    canvas.drawCircle(x, y, radius, d.paint(band ?: d.withAlpha(on, min(level, 1.0))))
                }
            }
        }
    }
}

/** Dot grid rules shared by the painter and the tests (DotGridLayout.swift). */
object DotGridLayout {
    /** Levels per cell: a number binding lights that share in [order]; literals and level bindings as written. */
    fun levels(resolver: com.khaled.widgetstudio.spec.BindingResolver, grid: LayerContent.DotGrid): List<Double> {
        val cells = grid.rows * grid.cols
        val share = (resolver.soleValue(grid.values) as? com.khaled.widgetstudio.spec.BindingResolver.Value.Number)?.value
        if (share == null) return resolver.levels(grid.values)
        val lit = Math.round(share.coerceIn(0.0, 1.0) * cells).toInt()
        val result = MutableList(cells) { 0.0 }
        order(grid.rows, grid.cols, grid.order).take(lit).forEach { result[it] = 1.0 }
        return result
    }

    /** Cell indices (row-major) in lighting order. */
    fun order(rows: Int, cols: Int, order: String?): List<Int> = when (order) {
        "columns" -> (0 until cols).flatMap { c -> (0 until rows).map { r -> r * cols + c } }
        "bottomUp" -> (0 until cols).flatMap { c -> (rows - 1 downTo 0).map { r -> r * cols + c } }
        else -> (0 until rows * cols).toList()
    }

    /** The color band of a level 0…1 among [bands]. */
    fun band(bands: List<Int>?, level: Double): Int? {
        if (bands.isNullOrEmpty() || level <= 0) return null
        val index = (Math.ceil(level.coerceAtMost(1.0) * bands.size).toInt() - 1).coerceIn(0, bands.size - 1)
        return bands[index]
    }

    /** Dot size factor for a halftone fade toward a side (x, y are 0…1 across the grid). */
    fun fade(side: String?, x: Float, y: Float): Float = when (side) {
        "left" -> 0.25f + 0.75f * x
        "right" -> 0.25f + 0.75f * (1 - x)
        "up" -> 0.25f + 0.75f * y
        "down" -> 0.25f + 0.75f * (1 - y)
        else -> 1f
    }

    /** \`weather\` becomes the current condition's shape. */
    fun maskName(mask: String, resolver: com.khaled.widgetstudio.spec.BindingResolver): String {
        if (mask != "weather") return mask
        val kind = resolver.value("weather.kind")?.let(resolver::display) ?: return "cloud"
        val day = resolver.value("time.isDay")?.let(resolver::display) != "0"
        return when (kind) {
            "clear" -> if (day) "sun" else "moon"
            "storm" -> "bolt"
            else -> "cloud"
        }
    }
}

/** Mask outlines for dot grids, in [box] (ShapeGeometry.mask in Swift). */
fun ShapeGeometry.mask(name: String, box: RectF): Path {
    fun at(x: Float, y: Float) = PointF(box.left + x * box.width(), box.top + y * box.height())
    fun circle(x: Float, y: Float, r: Float) = Path().apply { addCircle(box.left + x * box.width(), box.top + y * box.height(), r * min(box.width(), box.height()), Path.Direction.CW) }
    val side = min(box.width(), box.height())
    val square = RectF(box.centerX() - side / 2, box.centerY() - side / 2, box.centerX() + side / 2, box.centerY() + side / 2)
    return when (name) {
        "cloud" -> Path().apply {
            addPath(circle(0.3f, 0.6f, 0.22f)); addPath(circle(0.52f, 0.42f, 0.3f)); addPath(circle(0.75f, 0.6f, 0.2f))
            addRoundRect(RectF(box.left + 0.1f * box.width(), box.top + 0.55f * box.height(), box.left + 0.94f * box.width(), box.top + 0.82f * box.height()), 0.13f * side, 0.13f * side, Path.Direction.CW)
        }
        "sun" -> star(square, 12, 0.72)
        "moon" -> Path().apply { op(circle(0.5f, 0.5f, 0.45f), circle(0.68f, 0.38f, 0.38f), Path.Op.DIFFERENCE) }
        "drop" -> Path().apply {
            val tip = at(0.5f, 0.05f)
            moveTo(tip.x, tip.y)
            quadTo(box.left + 0.85f * box.width(), box.top + 0.45f * box.height(), box.left + 0.8f * box.width(), box.top + 0.68f * box.height())
            addPath(circle(0.5f, 0.66f, 0.3f))
            lineTo(box.left + 0.2f * box.width(), box.top + 0.68f * box.height())
            quadTo(box.left + 0.15f * box.width(), box.top + 0.45f * box.height(), tip.x, tip.y)
            close()
        }
        "heart" -> Path().apply {
            addPath(circle(0.3f, 0.35f, 0.25f)); addPath(circle(0.7f, 0.35f, 0.25f))
            addPath(polygon(listOf(at(0.06f, 0.42f), at(0.94f, 0.42f), at(0.5f, 0.95f))))
        }
        "bolt" -> polygon(listOf(at(0.58f, 0.02f), at(0.18f, 0.56f), at(0.46f, 0.56f), at(0.38f, 0.98f), at(0.82f, 0.4f), at(0.54f, 0.4f)))
        else -> Path().apply { addCircle(box.centerX(), box.centerY(), side / 2, Path.Direction.CW) }
    }
}

package com.khaled.widgetstudio.render

import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import com.khaled.widgetstudio.spec.FontSpec
import com.khaled.widgetstudio.spec.LText
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.MonthGrid
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/** The chart-like layers (ChartViews, DotViews, CalendarListViews in Swift). */
internal class ChartDrawer(private val d: Drawing) {
    private val context get() = d.context

    // MARK: Analog clock (hour and minute hands only: widgets update once a minute)

    fun analogClock(canvas: Canvas, clock: LayerContent.AnalogClock, rect: RectF) {
        val dark = d.theme == com.khaled.widgetstudio.spec.Theme.DARK
        val face = d.color(clock.faceColor ?: if (dark) "#1A1A1A" else "#FFFFFF")
        val ink = d.color(clock.tickColor ?: if (dark) "#FFFFFF" else "#0E0E0E")
        val hour = d.color(clock.hourColor ?: if (dark) "#FFFFFF" else "#0E0E0E")
        val minute = d.color(clock.minuteColor ?: if (dark) "#FFFFFF" else "#0E0E0E")
        val accent = d.color(clock.accentColor ?: "#E31C24")
        val zone = clock.timezone?.let { value ->
            val raw = com.khaled.widgetstudio.spec.Bindings.soleBinding(value)
            val name = if (raw != null && raw.startsWith("field.")) d.resolver.fieldValue(raw.removePrefix("field.")) else value
            name?.let { runCatching { ZoneId.of(it) }.getOrNull() }
        } ?: context.zone
        val time = context.now.atZone(zone)
        val radius = min(rect.width(), rect.height()) / 2
        val cx = rect.centerX()
        val cy = rect.centerY()
        canvas.drawCircle(cx, cy, radius, d.paint(face))
        // ADR-029: marks `60` (default), `12`, `dots` (default for style dot) or `none`.
        val ticks = clock.ticks ?: if (clock.style == "dot") "dots" else "60"
        if (ticks != "none") for (tick in 0 until 60) {
            val isHour = tick % 5 == 0
            if ((ticks == "dots" || ticks == "12") && !isHour) continue
            val angle = tick / 60.0 * 2 * Math.PI
            val dx = sin(angle).toFloat()
            val dy = -cos(angle).toFloat()
            if (ticks == "dots") {
                canvas.drawCircle(cx + dx * radius * 0.82f, cy + dy * radius * 0.82f, radius * 0.035f, d.paint(ink))
            } else {
                val outer = radius * 0.92f
                val inner = radius * if (isHour) 0.76f else 0.86f
                val p = d.paint(ink, Paint.Style.STROKE).apply { strokeWidth = radius * if (isHour) 0.035f else 0.015f }
                canvas.drawLine(cx + dx * inner, cy + dy * inner, cx + dx * outer, cy + dy * outer, p)
            }
        }
        val round = clock.handCap != "flat"
        hand(canvas, cx, cy, radius, ((time.hour % 12) + time.minute / 60.0) / 12, (clock.hourLength ?: 0.5).toFloat(), (clock.hourWidth ?: 0.07).toFloat(), hour, round)
        hand(canvas, cx, cy, radius, time.minute / 60.0, (clock.minuteLength ?: 0.75).toFloat(), (clock.minuteWidth ?: 0.045).toFloat(), minute, round)
        // Seconds as of the render (a hand or a dot on the rim) in the accent color.
        when (clock.seconds) {
            "hand" -> hand(canvas, cx, cy, radius, time.second / 60.0, 0.85f, 0.015f, accent, true)
            "dot" -> {
                val angle = time.second / 60.0 * 2 * Math.PI
                canvas.drawCircle(cx + sin(angle).toFloat() * radius * 0.86f, cy - cos(angle).toFloat() * radius * 0.86f, radius * 0.05f, d.paint(accent))
            }
        }
        if (clock.centerDot != false) canvas.drawCircle(cx, cy, radius * 0.045f, d.paint(accent))
    }

    private fun hand(canvas: Canvas, cx: Float, cy: Float, radius: Float, fraction: Double, length: Float, width: Float, color: Int, round: Boolean = true) {
        val angle = fraction * 2 * Math.PI
        val p = d.paint(color, Paint.Style.STROKE).apply {
            strokeWidth = radius * width
            strokeCap = if (round) Paint.Cap.ROUND else Paint.Cap.BUTT
        }
        canvas.drawLine(cx, cy, cx + sin(angle).toFloat() * radius * length, cy - cos(angle).toFloat() * radius * length, p)
    }

    // MARK: Dots

    fun dotGrid(canvas: Canvas, grid: LayerContent.DotGrid, rect: RectF, scale: Float, mirrored: Boolean) {
        if (grid.levelColors != null || grid.mask != null || grid.sizeByLevel == true || grid.order != null || (grid.fade ?: "none") != "none") {
            return DotGridPainter(d).draw(canvas, grid, rect, scale, mirrored)
        }
        val levels = d.resolver.gridLevels(grid.values, grid.rows * grid.cols)
        val on = d.color(grid.onColor)
        val off = d.color(grid.offColor)
        val highlight = d.color(grid.highlightColor ?: grid.onColor)
        val dot = (grid.dotSize * scale).toFloat()
        val gap = (grid.gap * scale).toFloat()
        val width = grid.cols * dot + (grid.cols - 1) * gap
        val height = grid.rows * dot + (grid.rows - 1) * gap
        val left = rect.left + (rect.width() - width) / 2
        val top = rect.top + (rect.height() - height) / 2
        for (row in 0 until grid.rows) for (col in 0 until grid.cols) {
            val index = row * grid.cols + col
            val level = levels.getOrElse(index) { 0.0 }
            if (level < 0) continue
            val column = if (mirrored) grid.cols - 1 - col else col
            val x = left + column * (dot + gap) + dot / 2
            val y = top + row * (dot + gap) + dot / 2
            canvas.drawCircle(x, y, dot / 2, d.paint(off))
            when {
                level >= MonthGrid.HIGHLIGHT -> canvas.drawCircle(x, y, dot / 2, d.paint(highlight))
                level > 0 -> canvas.drawCircle(x, y, dot / 2, d.paint(d.withAlpha(on, min(level, 1.0))))
            }
        }
    }

    fun dotBars(canvas: Canvas, bars: LayerContent.DotBars, rect: RectF, scale: Float, mirrored: Boolean) {
        fun <T> ordered(items: List<T>, filler: T): List<T> {
            val padded = items.take(bars.bars) + List(maxOf(0, bars.bars - items.size)) { filler }
            return if (mirrored) padded.reversed() else padded
        }
        val levels = ordered(d.resolver.levels(bars.values), 0.0)
        val labels = ordered(bars.labels?.resolved(context.language)?.let(d.resolver::render)?.split(",")?.map { it.trim() } ?: emptyList(), "")
        val color = d.color(bars.color)
        val off = d.color(bars.offColor ?: "#FFFFFF26")
        val best = if (bars.highlightColor == null) null else levels.indices.maxByOrNull { levels[it] }
        val highlight = d.color(bars.highlightColor ?: bars.color)
        val hasLabels = labels.any { it.isNotEmpty() }
        val labelHeight = if (hasLabels) 8 * 1.7f * scale else 0f
        val chart = RectF(rect.left, rect.top, rect.right, rect.bottom - if (hasLabels) labelHeight + 4 * scale else 0f)
        val dot = min(chart.width() / (bars.bars * 1.6f), chart.height() / (bars.maxDots * 1.4f))
        val columnWidth = chart.width() / bars.bars
        val rowHeight = chart.height() / bars.maxDots
        for (bar in 0 until bars.bars) {
            val lit = (levels[bar].coerceIn(0.0, 1.0) * bars.maxDots).roundToInt()
            for (row in 0 until bars.maxDots) {
                val x = chart.left + bar * columnWidth + columnWidth / 2
                val y = chart.bottom - (row + 1) * rowHeight + rowHeight / 2
                canvas.drawCircle(x, y, dot / 2, d.paint(if (row < lit) (if (bar == best) highlight else color) else off))
            }
        }
        if (hasLabels) for (bar in 0 until bars.bars) {
            val cell = RectF(rect.left + bar * columnWidth, rect.bottom - labelHeight, rect.left + (bar + 1) * columnWidth, rect.bottom)
            d.text.drawFitted(canvas, labels[bar], FontSpec("system", 8.0, "medium"), d.withAlpha(color, 0.7), "center", 1, null, cell, scale)
        }
    }

    fun ring(canvas: Canvas, ring: LayerContent.Ring, rect: RectF, scale: Float) {
        val progress = (d.resolver.number(ring.progress) ?: 0.0).coerceIn(0.0, 1.0)
        val width = (ring.lineWidth * scale).toFloat()
        val side = min(rect.width(), rect.height()) - width
        val box = RectF(rect.centerX() - side / 2, rect.centerY() - side / 2, rect.centerX() + side / 2, rect.centerY() + side / 2)
        canvas.drawOval(box, d.paint(d.color(ring.trackColor ?: "#FFFFFF33"), Paint.Style.STROKE).apply { strokeWidth = width })
        val p = d.paint(d.color(ring.color), Paint.Style.STROKE).apply {
            strokeWidth = width
            strokeCap = Paint.Cap.ROUND
        }
        if (progress > 0) canvas.drawArc(box, -90f, (progress * 360).toFloat(), false, p)
    }

    fun progress(canvas: Canvas, bar: LayerContent.ProgressBar, rect: RectF, scale: Float, mirrored: Boolean) {
        val value = (d.resolver.number(bar.progress) ?: 0.0).coerceIn(0.0, 1.0)
        val vertical = bar.vertical == true
        val radius = bar.cornerRadius?.let { (it * scale).toFloat() } ?: ((if (vertical) rect.width() else rect.height()) / 2)
        val fill = d.color(bar.color)
        val track = d.color(bar.trackColor ?: "#8080804D")
        val segments = bar.segments ?: 1
        if (vertical) {
            if (segments > 1) {
                val lit = (value * segments).roundToInt()
                val gap = maxOf(1f, 2 * scale)
                val height = (rect.height() - gap * (segments - 1)) / segments
                val r = min(radius, rect.width() / 2)
                for (index in 0 until segments) {
                    val y = rect.top + index * (height + gap)
                    canvas.drawRoundRect(RectF(rect.left, y, rect.right, y + height), r, r, d.paint(if (index >= segments - lit) fill else track))
                }
            } else {
                canvas.drawRoundRect(rect, radius, radius, d.paint(track))
                val h = (rect.height() * value).toFloat()
                canvas.drawRoundRect(RectF(rect.left, rect.bottom - h, rect.right, rect.bottom), radius, radius, d.paint(fill))
            }
        } else if (segments > 1) {
            val lit = (value * segments).roundToInt()
            val gap = maxOf(1f, 2 * scale)
            val width = (rect.width() - gap * (segments - 1)) / segments
            val r = min(radius, rect.height() / 2)
            for (index in 0 until segments) {
                val on = if (mirrored) index >= segments - lit else index < lit
                val x = rect.left + index * (width + gap)
                canvas.drawRoundRect(RectF(x, rect.top, x + width, rect.bottom), r, r, d.paint(if (on) fill else track))
            }
        } else {
            canvas.drawRoundRect(rect, radius, radius, d.paint(track))
            val w = (rect.width() * value).toFloat()
            val filled = if (mirrored) RectF(rect.right - w, rect.top, rect.right, rect.bottom) else RectF(rect.left, rect.top, rect.left + w, rect.bottom)
            canvas.drawRoundRect(filled, radius, radius, d.paint(fill))
        }
        // ADR-029: a round knob at the fill's end.
        bar.knob?.let { knob ->
            val size = knob.size?.let { (it * scale).toFloat() } ?: (2 * minOf(rect.width(), rect.height()))
            val knobColor = d.color(knob.color ?: bar.color)
            if (vertical) canvas.drawCircle(rect.centerX(), rect.bottom - (rect.height() * value).toFloat(), size / 2, d.paint(knobColor))
            else {
                val x = if (mirrored) rect.right - (rect.width() * value).toFloat() else rect.left + (rect.width() * value).toFloat()
                canvas.drawCircle(x, rect.centerY(), size / 2, d.paint(knobColor))
            }
        }
    }

    // MARK: Forecast

    fun forecast(canvas: Canvas, row: LayerContent.ForecastRow, rect: RectF, scale: Float, mirrored: Boolean) {
        if (row.mode == "hourly" || row.font != null || row.dividerColor != null || row.showLow != null || row.iconStyle != null || row.labelColor != null || row.showIcons != null) {
            return forecastColumns(canvas, row, rect, scale, mirrored)
        }
        val next = context.data.weather?.forecast?.take(row.days) ?: emptyList()
        val days = if (mirrored) next.reversed() else next
        val color = d.color(row.color)
        if (days.isEmpty()) {
            d.text.drawFitted(canvas, "--", FontSpec("system", 13.0, null), color, "center", 1, null, rect, scale)
            return
        }
        val column = rect.width() / days.size
        // Name 9, symbol 15, high 13, low 9 (points), 3 pt apart, centered vertically.
        // Arabic day names need taller lines than Latin ones.
        val heights = listOf(9 * 1.7f, 15 * 1.2f, 13 * 1.3f, 9 * 1.4f).map { it * scale }
        val total = heights.sum() + 3 * scale * 3
        for ((index, day) in days.withIndex()) {
            val left = rect.left + index * column
            var y = rect.centerY() - total / 2
            val name = DateTimeFormatter.ofPattern(if (context.isArabic) "EEEE" else "EEE", context.locale).format(day.date)
            d.text.drawFitted(canvas, name, FontSpec("system", 9.0, "medium"), d.withAlpha(color, 0.7), "center", 1, null, RectF(left, y, left + column, y + heights[0]), scale)
            y += heights[0] + 3 * scale
            val symbol = if (d.renderer.icons.isAllowed(day.symbol)) day.symbol else "questionmark"
            d.drawSymbol(canvas, d.renderer.icons.material(symbol), left + column / 2, y + heights[1] / 2, 15 * scale, color)
            y += heights[1] + 3 * scale
            d.text.drawFitted(canvas, "${day.high.roundToInt()}°", FontSpec("dot", 13.0, "bold"), color, "center", 1, null, RectF(left, y, left + column, y + heights[2]), scale)
            y += heights[2] + 3 * scale
            d.text.drawFitted(canvas, "${day.low.roundToInt()}°", FontSpec("system", 9.0, null), d.withAlpha(color, 0.6), "center", 1, null, RectF(left, y, left + column, y + heights[3]), scale)
        }
    }

    /** ADR-029: hourly or daily columns with the row's font, icon style, lows and dividers. */
    private fun forecastColumns(canvas: Canvas, row: LayerContent.ForecastRow, rect: RectF, scale: Float, mirrored: Boolean) {
        data class Column(val label: String, val symbol: String, val high: String, val low: String?)
        val hourly = row.mode == "hourly"
        val columns = if (hourly) (1..row.days).mapNotNull { n ->
            val time = d.resolver.value("hourly.$n.time")?.let(d.resolver::display) ?: return@mapNotNull null
            val symbol = d.resolver.value("hourly.$n.symbol")?.let(d.resolver::display) ?: "cloud.fill"
            val temp = d.resolver.value("hourly.$n.temp")?.let(d.resolver::display) ?: "--"
            Column(time, symbol, "$temp°", null)
        } else (context.data.weather?.forecast?.take(row.days) ?: emptyList()).map { day ->
            Column(DateTimeFormatter.ofPattern(if (context.isArabic) "EEEE" else "EEE", context.locale).format(day.date), day.symbol, "${day.high.roundToInt()}°", "${day.low.roundToInt()}°")
        }
        val color = d.color(row.color)
        if (columns.isEmpty()) {
            d.text.drawFitted(canvas, "--", FontSpec("system", 13.0, null), color, "center", 1, null, rect, scale)
            return
        }
        val ordered = if (mirrored) columns.reversed() else columns
        val font = row.font ?: FontSpec("system", 12.0, "semibold")
        val labelFont = FontSpec(font.family, font.size * 0.85, null)
        val labelColor = d.color(row.labelColor, d.withAlpha(color, 0.6))
        val showIcons = row.showIcons != false
        val showLow = !hourly && row.showLow != false
        val width = rect.width() / ordered.size
        val lines = listOf(labelFont.size * 1.4, if (showIcons) font.size * 1.5 else 0.0, font.size * 1.35, if (showLow) labelFont.size * 1.35 else 0.0).map { (it * scale).toFloat() }
        val gap = 3 * scale
        val total = lines.sum() + gap * lines.count { it > 0 }.minus(1).coerceAtLeast(0)
        for ((index, column) in ordered.withIndex()) {
            val left = rect.left + index * width
            var y = rect.centerY() - total / 2
            d.text.drawFitted(canvas, column.label, labelFont, labelColor, "center", 1, null, RectF(left, y, left + width, y + lines[0]), scale)
            y += lines[0] + gap
            if (showIcons) {
                val outline = row.iconStyle == "outline"
                val symbol = if (outline) column.symbol.replace(".fill", "") else column.symbol
                d.drawSymbol(canvas, d.renderer.icons.material(symbol), left + width / 2, y + lines[1] / 2, (font.size * 1.25 * scale).toFloat(), color, outline)
                y += lines[1] + gap
            }
            d.text.drawFitted(canvas, column.high, font, color, "center", 1, null, RectF(left, y, left + width, y + lines[2]), scale)
            y += lines[2] + gap
            if (showLow && column.low != null) d.text.drawFitted(canvas, column.low, labelFont, labelColor, "center", 1, null, RectF(left, y, left + width, y + lines[3]), scale)
            if (row.dividerColor != null && index > 0) {
                canvas.drawRect(RectF(left - maxOf(0.5f, 0.5f * scale), rect.centerY() - total / 2, left + maxOf(0.5f, 0.5f * scale), rect.centerY() + total / 2), d.paint(d.color(row.dividerColor)))
            }
        }
    }

    // MARK: Calendar

    fun calendar(canvas: Canvas, layer: LayerContent.CalendarMonth, rect: RectF, scale: Float, mirrored: Boolean) {
        val layout = CalendarLayout(layer, context.now.atZone(context.zone).toLocalDate(), context.locale, context.isArabic)
        val titleFont = layer.effectiveTitleFont
        val weekdayFont = layer.effectiveWeekdayFont
        val titleHeight = if (layout.title.isEmpty()) 0f else (titleFont.size * 1.35 * scale).toFloat()
        val headerHeight = if (layout.weekdays.isEmpty()) 0f else (weekdayFont.size * 1.7 * scale).toFloat()
        val cellWidth = rect.width() / 7
        val cellHeight = maxOf(0f, (rect.height() - titleHeight - headerHeight) / maxOf(layout.rows.size, 1))
        val columns = if (mirrored) (6 downTo 0).toList() else (0..6).toList()
        var y = rect.top
        if (layout.title.isNotEmpty()) {
            var align = layer.titleAlign ?: "leading"
            if (mirrored) align = if (align == "leading") "trailing" else if (align == "trailing") "leading" else align
            val inset = cellWidth * 0.18f
            d.text.drawFitted(canvas, layout.title, titleFont, d.color(layer.titleColor ?: layer.color), align, 1, null,
                RectF(rect.left + inset, y, rect.right - inset, y + titleHeight), scale)
            y += titleHeight
        }
        val weekdayColor = layer.weekdayColor ?: layer.color
        if (layout.weekdays.isNotEmpty()) {
            for ((position, column) in columns.withIndex()) {
                val color = if (layout.weekendColumns[column]) layer.weekendColor ?: weekdayColor else weekdayColor
                val cell = RectF(rect.left + position * cellWidth, y, rect.left + (position + 1) * cellWidth, y + headerHeight)
                d.text.drawFitted(canvas, layout.weekdays[column], weekdayFont, d.color(color), "center", 1, null, cell, scale)
            }
            y += headerHeight
        }
        val style = layer.todayStyle ?: "filled"
        val highlight = d.color(layer.todayColor ?: layer.color)
        for (row in layout.rows) {
            for ((position, column) in columns.withIndex()) {
                val cell = row[column]
                val box = RectF(rect.left + position * cellWidth, y, rect.left + (position + 1) * cellWidth, y + cellHeight)
                val side = min(cellWidth, cellHeight) * 0.86f
                val square = RectF(box.centerX() - side / 2, box.centerY() - side / 2, box.centerX() + side / 2, box.centerY() + side / 2)
                if (cell.isToday) when (style) {
                    "filled" -> canvas.drawRoundRect(square, side * 0.28f, side * 0.28f, d.paint(highlight))
                    "circle" -> canvas.drawOval(square, d.paint(highlight))
                    "ring" -> canvas.drawOval(square, d.paint(highlight, Paint.Style.STROKE).apply { strokeWidth = maxOf(1f, 1.5f * scale) })
                    "dot" -> canvas.drawCircle(box.centerX(), box.centerY() + side * 0.42f, side * 0.08f, d.paint(highlight))
                }
                val day = cell.day ?: continue
                val onHighlight = cell.isToday && (style == "filled" || style == "circle")
                val color = if (onHighlight) layer.todayTextColor ?: "#FFFFFF" else if (cell.isWeekend) layer.weekendColor ?: layer.color else layer.color
                val c = d.color(color)
                d.text.drawFitted(canvas, day.toString(), layer.font, if (cell.isOtherMonth) d.withAlpha(c, 0.3) else c, "center", 1, null, box, scale)
            }
            y += cellHeight
        }
    }

    // MARK: List

    fun list(canvas: Canvas, list: LayerContent.ListL, rect: RectF, scale: Float, mirrored: Boolean) {
        val rowHeight = rect.height() / maxOf(list.items.size, 1)
        val size = (list.font.size * scale).toFloat()
        val color = d.color(list.color)
        for ((index, item) in list.items.withIndex()) {
            val row = RectF(rect.left, rect.top + index * rowHeight, rect.right, rect.top + (index + 1) * rowHeight)
            val markerColor = d.color(item.color?.let(d.resolver::render) ?: list.markerColor ?: list.color)
            val isDone = item.done?.let(d.resolver::isSatisfied) ?: false
            val markerWidth = marker(canvas, list, item, row, size, scale, markerColor, mirrored)
            val gap = 8 * scale
            val title = text(item.title)
            val detail = item.detail?.let(::text)
            val detailColor = list.detailColor?.let { d.color(it) } ?: d.withAlpha(color, 0.6)
            val detailWidth = detail?.let { minOf(d.text.naturalWidth(it, list.font, null, scale), row.width() * 0.45f) } ?: 0f
            val titleLeft = if (mirrored) row.left + detailWidth + 4 * scale else row.left + (if (markerWidth > 0) markerWidth + gap else 0f)
            val titleRight = if (mirrored) row.right - (if (markerWidth > 0) markerWidth + gap else 0f) else row.right - detailWidth - 4 * scale
            // ADR-029: a subtitle under the title and a second detail under the first share the row's height.
            val subtitle = item.subtitle?.let(::text)
            val detail2 = item.detail2?.let(::text)
            val small = com.khaled.widgetstudio.spec.FontSpec(list.font.family, list.font.size * 0.82, null)
            val titleBox = RectF(titleLeft, row.top, titleRight, if (subtitle != null) row.top + row.height() * 0.56f else row.bottom)
            d.text.drawFitted(canvas, title, list.font, if (isDone) d.withAlpha(color, 0.5) else color, if (mirrored) "trailing" else "leading", 1, null, titleBox, scale, 0.6f)
            subtitle?.let { d.text.drawFitted(canvas, it, small, detailColor, if (mirrored) "trailing" else "leading", 1, null, RectF(titleLeft, titleBox.bottom, titleRight, row.bottom), scale, 0.6f) }
            if (detail != null) {
                val box = if (mirrored) RectF(row.left, row.top, row.left + detailWidth, row.bottom) else RectF(row.right - detailWidth, row.top, row.right, row.bottom)
                val top = if (detail2 != null) RectF(box.left, box.top, box.right, box.top + box.height() * 0.5f) else box
                d.text.drawFitted(canvas, detail, if (detail2 != null) small else list.font, detailColor, if (mirrored) "leading" else "trailing", 1, null, top, scale, 0.6f)
                detail2?.let { d.text.drawFitted(canvas, it, small, detailColor, if (mirrored) "leading" else "trailing", 1, null, RectF(box.left, top.bottom, box.right, box.bottom), scale, 0.6f) }
            }
            val divider = list.dividerColor
            if (divider != null && index < list.items.size - 1) {
                canvas.drawRect(RectF(row.left, row.bottom - maxOf(0.5f, 0.75f * scale), row.right, row.bottom), d.paint(d.color(divider)))
            }
        }
    }

    private fun text(value: LText) = BidiText.isolatingNumbers(d.resolver.render(value.resolved(context.language)))

    /** Draws the row's marker at its leading (or, mirrored, trailing) edge; returns its width. */
    private fun marker(canvas: Canvas, list: LayerContent.ListL, item: com.khaled.widgetstudio.spec.ListItem, row: RectF, size: Float, scale: Float, color: Int, mirrored: Boolean): Float {
        // A row with a done state is a checkbox, whatever the list's marker says.
        val kind = item.done?.let { if (d.resolver.isSatisfied(it)) "check" else "circle" } ?: list.marker ?: "none"
        val width = when (kind) {
            "dot" -> size * 0.45f
            "circle" -> size * 0.95f
            "check" -> size
            "icon" -> size * 1.2f
            "bar" -> 3 * scale
            else -> return 0f
        }
        val cx = if (mirrored) row.right - width / 2 else row.left + width / 2
        val cy = row.centerY()
        when (kind) {
            "dot" -> canvas.drawCircle(cx, cy, width / 2, d.paint(color))
            "circle" -> canvas.drawCircle(cx, cy, width / 2, d.paint(color, Paint.Style.STROKE).apply { strokeWidth = maxOf(1f, 1.5f * scale) })
            "check" -> d.drawSymbol(canvas, "check_circle", cx, cy, size, color)
            "icon" -> {
                val icon = item.icon?.takeIf { d.renderer.icons.isAllowed(it) } ?: "circle.fill"
                d.drawSymbol(canvas, d.renderer.icons.material(icon), cx, cy, size * 0.9f, color)
            }
            "bar" -> canvas.drawRoundRect(RectF(cx - width / 2, row.top + row.height() * 0.12f, cx + width / 2, row.bottom - row.height() * 0.12f), 1.5f * scale, 1.5f * scale, d.paint(color))
        }
        return width
    }
}

/** The month a calendar layer shows (CalendarMonthLayout in Swift). */
internal class CalendarLayout(layer: LayerContent.CalendarMonth, date: LocalDate, locale: java.util.Locale, arabic: Boolean) {
    data class Cell(val day: Int?, val isOtherMonth: Boolean, val isToday: Boolean, val isWeekend: Boolean)

    val title: String
    val weekdays: List<String>
    val weekendColumns: List<Boolean>
    val rows: List<List<Cell>>

    init {
        // The locale's first weekday: Saturday for Arabic (ar_EG), Sunday for English (en_US).
        val first = when (layer.weekStart ?: "locale") {
            "saturday" -> DayOfWeek.SATURDAY
            "sunday" -> DayOfWeek.SUNDAY
            "monday" -> DayOfWeek.MONDAY
            else -> if (arabic) DayOfWeek.SATURDAY else DayOfWeek.SUNDAY
        }
        val format = layer.titleFormat ?: "MMM"
        title = if (format == "none") "" else {
            val text = DateTimeFormatter.ofPattern(format.replace("MMMM", "LLLL").replace("MMM", "LLL"), locale).format(date)
            when (layer.titleCase ?: "upper") {
                "upper" -> text.uppercase(locale)
                "lower" -> text.lowercase(locale)
                else -> text
            }
        }
        val keys = listOf("sun", "mon", "tue", "wed", "thu", "fri", "sat")
        val weekend = (layer.weekendDays ?: emptyList()).mapNotNull { keys.indexOf(it.lowercase()).takeIf { i -> i >= 0 } }.toSet()
        // Column → day index with 0 = Sunday, like the Swift layout.
        val columns = (0 until 7).map { ((first.value % 7) + it) % 7 }
        val style = if ((layer.weekdays ?: "narrow") in listOf("short", "two")) TextStyle.SHORT_STANDALONE else TextStyle.NARROW_STANDALONE
        weekdays = if ((layer.weekdays ?: "narrow") == "none") emptyList() else columns.map { column ->
            val name = DayOfWeek.of(if (column == 0) 7 else column).getDisplayName(style, locale)
            // "Mo Tu" (ADR-029); Arabic keeps its short name.
            if (layer.weekdays == "two" && !arabic) name.take(2) else name
        }
        weekendColumns = columns.map { it in weekend }

        val cells = mutableListOf<Cell>()
        val start = date.withDayOfMonth(1)
        val leading = (start.dayOfWeek.value % 7 - first.value % 7 + 7) % 7
        val dimmed = (layer.otherDays ?: "hidden") == "dimmed"
        val previousCount = start.minusDays(1).lengthOfMonth()
        for (index in 0 until leading) cells += Cell(if (dimmed) previousCount - leading + 1 + index else null, true, false, weekendColumns[index])
        for (day in 1..date.lengthOfMonth()) cells += Cell(day, false, day == date.dayOfMonth, weekendColumns[cells.size % 7])
        var next = 1
        while (cells.size % 7 != 0) {
            cells += Cell(if (dimmed) next else null, true, false, weekendColumns[cells.size % 7])
            next += 1
        }
        val month = cells.chunked(7)
        // ADR-029: a week strip shows the week holding today (and the next for two weeks), across months.
        rows = when (layer.rows) {
            "week", "2weeks" -> {
                val firstOfWeek = date.minusDays(((date.dayOfWeek.value % 7 - first.value % 7 + 7) % 7).toLong())
                (0 until if (layer.rows == "week") 1 else 2).map { row ->
                    (0 until 7).map { column ->
                        val day = firstOfWeek.plusDays((row * 7 + column).toLong())
                        Cell(day.dayOfMonth, day.month != date.month, day == date, weekendColumns[column])
                    }
                }
            }
            else -> month
        }
    }
}

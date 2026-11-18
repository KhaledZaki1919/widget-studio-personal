package com.khaled.widgetstudio.render

import android.graphics.Canvas
import android.graphics.RectF
import com.khaled.widgetstudio.spec.Layer
import com.khaled.widgetstudio.spec.LayerContent
import kotlin.math.max

/**
 * `stack` layers (StackViews.swift, M6.1): children laid out vertically, horizontally or in a grid
 * inside the frame. Texts and icons take their natural size (texts fill the width in vertical
 * stacks and grids), other layers the size they give; spacers share the free space. When the
 * content doesn't fit, the whole stack is drawn smaller (100 → 40 %), like ViewThatFits on iOS.
 * Mirrored, horizontal items and grid rows run the other way and start/end swap; glyphs never flip.
 */
internal class StackLayout(private val d: Drawing) {
    private data class Item(val layer: Layer, val width: Float, val height: Float, val flexible: Boolean)

    fun draw(canvas: Canvas, stack: LayerContent.Stack, frame: RectF, scale: Float, mirrored: Boolean) {
        val pad = ((stack.padding ?: 0.0) * scale).toFloat()
        val area = RectF(frame.left + pad, frame.top + pad, frame.right - pad, frame.bottom - pad)
        val visible = stack.children.filter { it.condition == null || d.resolver.isSatisfied(it.condition) }
        if (stack.axis == "radial") return radial(canvas, stack, visible, frame, scale, mirrored)
        for (factor in listOf(1f, 0.85f, 0.7f, 0.55f, 0.4f)) {
            val s = scale * factor
            val fits = when (stack.axis) {
                "horizontal" -> natural(visible, stack, s, area).let { (w, _) -> w <= area.width() + 0.5f }
                "grid" -> natural(visible, stack, s, area).let { (w, h) -> w <= area.width() + 0.5f && h <= area.height() + 0.5f }
                else -> natural(visible, stack, s, area).let { (_, h) -> h <= area.height() + 0.5f }
            }
            if (fits || factor == 0.4f) {
                place(canvas, stack, visible, area, s, mirrored)
                return
            }
        }
    }

    private fun spacing(stack: LayerContent.Stack, scale: Float) = ((stack.spacing ?: 4.0) * scale).toFloat()

    /** Width and height the content needs at [scale]. */
    private fun natural(children: List<Layer>, stack: LayerContent.Stack, scale: Float, area: RectF): Pair<Float, Float> {
        val gap = spacing(stack, scale)
        return when (stack.axis) {
            "horizontal" -> {
                val items = children.map { measure(it, "horizontal", scale, area.width(), area.height()) }
                items.sumOf { (if (it.flexible) 0f else it.width).toDouble() }.toFloat() + gap * max(0, items.size - 1) to (items.maxOfOrNull { it.height } ?: 0f)
            }
            "grid" -> {
                val rows = rows(children, stack)
                val columns = (stack.columns ?: 2).coerceIn(1, 8)
                val cellWidth = (area.width() - gap * (columns - 1)) / columns
                val heights = rows.map { row -> row.maxOfOrNull { measure(it, "grid", scale, cellWidth, area.height()).height } ?: 0f }
                area.width() to heights.sum() + gap * max(0, rows.size - 1)
            }
            else -> {
                val items = children.map { measure(it, "vertical", scale, area.width(), area.height()) }
                // The width is what the widest child needs, not the space offered: a column of texts beside a big
                // number in a horizontal stack must not claim the whole row (fixes the row shrinking to 40 %).
                val widths = children.map { measure(it, "intrinsic", scale, area.width(), area.height()).width }
                (widths.maxOrNull() ?: 0f) to items.sumOf { (if (it.flexible) 0f else it.height).toDouble() }.toFloat() + gap * max(0, items.size - 1)
            }
        }
    }

    /** A radial stack (RadialStackView.swift): children around a circle, turned with their angle when asked. */
    private fun radial(canvas: Canvas, stack: LayerContent.Stack, children: List<Layer>, frame: RectF, scale: Float, mirrored: Boolean) {
        val sizes = children.map { measure(it, "intrinsic", scale, frame.width(), frame.height()) }
        val largest = sizes.maxOfOrNull { maxOf(it.width, it.height) } ?: 0f
        val side = minOf(frame.width(), frame.height())
        val radius = stack.radius?.let { (it * scale).toFloat() } ?: maxOf(side / 2 - largest / 2 - ((stack.padding ?: 0.0) * scale).toFloat(), 1f)
        val start = stack.startAngle ?: 0.0
        val sweep = (stack.sweep ?: 360.0).coerceIn(0.0, 360.0)
        val step = if (children.size > 1) (if (sweep >= 360) 360.0 / children.size else sweep / (children.size - 1)) else 0.0
        children.forEachIndexed { index, child ->
            val angle = if (mirrored) start - step * index else start + step * index
            val radians = Math.toRadians(angle)
            val cx = frame.centerX() + (Math.sin(radians) * radius).toFloat()
            val cy = frame.centerY() - (Math.cos(radians) * radius).toFloat()
            val item = sizes[index]
            canvas.save()
            if (stack.rotateChildren == true) canvas.rotate(angle.toFloat(), cx, cy)
            d.layer(canvas, child, RectF(cx - item.width / 2, cy - item.height / 2, cx + item.width / 2, cy + item.height / 2), scale, mirrored, "center", fillWidth = false)
            canvas.restore()
        }
    }

    private fun rows(children: List<Layer>, stack: LayerContent.Stack): List<List<Layer>> = children.chunked((stack.columns ?: 2).coerceIn(1, 8))

    /** A child's size in a stack along [axis], given the space across it. */
    private fun measure(child: Layer, axis: String, scale: Float, availableWidth: Float, availableHeight: Float): Item {
        val givenW = if (child.frame.w > 0) (child.frame.w * scale).toFloat() else null
        val givenH = if (child.frame.h > 0) (child.frame.h * scale).toFloat() else null
        return when (val content = child.content) {
            is LayerContent.Spacer -> {
                val min = ((content.minLength ?: 0.0) * scale).toFloat()
                Item(child, min, min, flexible = true)
            }
            is LayerContent.Text -> {
                val value = d.text.value(content)
                val lines = max(content.maxLines ?: 1, value.count { it == '\n' } + 1)
                val width = givenW ?: if (axis == "horizontal" || axis == "intrinsic") minOf(d.text.naturalWidth(value, content.font, content.tracking, scale), availableWidth) else availableWidth
                val height = givenH ?: d.text.naturalHeight(value, content.font, content.tracking, scale, width, lines)
                Item(child, width, height, false)
            }
            is LayerContent.Icon -> Item(child, givenW ?: (content.size * scale).toFloat(), givenH ?: (content.size * scale).toFloat(), false)
            is LayerContent.Stack -> {
                if (axis == "intrinsic" && givenW == null) {
                    val visible = content.children.filter { it.condition == null || d.resolver.isSatisfied(it.condition) }
                    val (w, h) = natural(visible, content, scale, RectF(0f, 0f, availableWidth, givenH ?: availableHeight))
                    val pad = ((content.padding ?: 0.0) * scale * 2).toFloat()
                    return Item(child, minOf(w + pad, availableWidth), givenH ?: (h + pad), false)
                }
                val width = givenW ?: if (axis == "horizontal") 0f else availableWidth
                val inner = RectF(0f, 0f, if (width > 0) width else availableWidth, givenH ?: availableHeight)
                val pad = ((content.padding ?: 0.0) * scale * 2).toFloat()
                val visible = content.children.filter { it.condition == null || d.resolver.isSatisfied(it.condition) }
                val (w, h) = natural(visible, content, scale, inner)
                Item(child, givenW ?: if (axis == "horizontal") w + pad else availableWidth, givenH ?: (h + pad), false)
            }
            else -> Item(
                child,
                givenW ?: if (axis == "horizontal") 0f else availableWidth,
                givenH ?: if (axis == "horizontal") availableHeight else 0f,
                false,
            )
        }
    }

    private fun place(canvas: Canvas, stack: LayerContent.Stack, children: List<Layer>, area: RectF, scale: Float, mirrored: Boolean) {
        val gap = spacing(stack, scale)
        val align = stack.alignItems
        val justify = stack.justify ?: "start"
        // Texts without their own align follow the stack's cross alignment (horizontal stacks: leading).
        val textAlign = if (stack.axis == "horizontal") "leading" else when (align ?: "start") {
            "center" -> "center"
            "end" -> "trailing"
            else -> "leading"
        }
        fun horizontalOffset(free: Float, value: String): Float {
            val resolved = if (mirrored) when (value) {
                "start" -> "end"
                "end" -> "start"
                else -> value
            } else value
            return when (resolved) {
                "center" -> free / 2
                "end" -> free
                else -> 0f
            }
        }
        fun verticalOffset(free: Float, value: String) = when (value) {
            "center" -> free / 2
            "end" -> free
            else -> 0f
        }
        when (stack.axis) {
            "horizontal" -> {
                val ordered = if (mirrored) children.reversed() else children
                val items = ordered.map { measure(it, "horizontal", scale, area.width(), area.height()) }
                val fixed = items.sumOf { (if (it.flexible) 0f else it.width).toDouble() }.toFloat() + gap * max(0, items.size - 1)
                val spacers = items.count { it.flexible }
                val free = max(0f, area.width() - fixed)
                var x = area.left + if (spacers == 0) horizontalOffset(free, justify) else 0f
                for (item in items) {
                    val width = if (item.flexible) max(item.width, free / spacers) else item.width
                    val height = minOf(item.height, area.height())
                    val y = area.top + verticalOffset(area.height() - height, align ?: "center")
                    if (!item.flexible) d.layer(canvas, item.layer, RectF(x, y, x + width, y + height), scale, mirrored, textAlign, fillWidth = false)
                    x += width + gap
                }
            }
            "grid" -> {
                val columns = (stack.columns ?: 2).coerceIn(1, 8)
                val cellWidth = (area.width() - gap * (columns - 1)) / columns
                var y = area.top
                for (row in rows(children, stack)) {
                    val ordered = if (mirrored) row.reversed() else row
                    val items = ordered.map { measure(it, "grid", scale, cellWidth, area.height()) }
                    val rowHeight = items.maxOfOrNull { it.height } ?: 0f
                    for ((index, item) in items.withIndex()) {
                        val column = if (mirrored) columns - row.size + index else index
                        val width = minOf(item.width, cellWidth)
                        val x = area.left + column * (cellWidth + gap) + horizontalOffset(cellWidth - width, align ?: "start")
                        val top = y + (rowHeight - item.height) / 2
                        d.layer(canvas, item.layer, RectF(x, top, x + width, top + item.height), scale, mirrored, textAlign)
                    }
                    y += rowHeight + gap
                }
            }
            else -> {
                val items = children.map { measure(it, "vertical", scale, area.width(), area.height()) }
                val fixed = items.sumOf { (if (it.flexible) 0f else it.height).toDouble() }.toFloat() + gap * max(0, items.size - 1)
                val spacers = items.count { it.flexible }
                val free = max(0f, area.height() - fixed)
                var y = area.top + if (spacers == 0) verticalOffset(free, justify) else 0f
                for (item in items) {
                    val height = if (item.flexible) max(item.height, free / spacers) else item.height
                    val width = minOf(item.width, area.width())
                    val x = area.left + horizontalOffset(area.width() - width, align ?: "start")
                    if (!item.flexible) d.layer(canvas, item.layer, RectF(x, y, x + width, y + height), scale, mirrored, textAlign)
                    y += height + gap
                }
            }
        }
    }
}

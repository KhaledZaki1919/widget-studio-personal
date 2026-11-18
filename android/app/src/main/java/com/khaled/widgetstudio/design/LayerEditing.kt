package com.khaled.widgetstudio.design

import com.khaled.widgetstudio.spec.Frame
import com.khaled.widgetstudio.spec.Layer
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.WidgetSpec
import kotlin.math.abs
import kotlin.math.floor

/**
 * The layer editor's operations (LayerEditing.swift, ADR-022) on a spec's layer tree. A path is
 * `[3]` for the fourth top-level layer, `[3, 0]` for the first child of that stack. The AI layout
 * fix uses the same grouping and reflow.
 */
object LayerEditing {
    fun layer(path: List<Int>, layers: List<Layer>): Layer? {
        val first = path.firstOrNull() ?: return null
        val layer = layers.getOrNull(first) ?: return null
        if (path.size == 1) return layer
        val stack = layer.content as? LayerContent.Stack ?: return null
        return layer(path.drop(1), stack.children)
    }

    /** Applies [body] to the list that holds the layer at [path]; returns the new top-level list. */
    private fun siblings(path: List<Int>, layers: List<Layer>, body: (MutableList<Layer>) -> Unit): List<Layer> {
        val first = path.firstOrNull() ?: return layers
        val list = layers.toMutableList()
        if (path.size == 1) {
            body(list)
            return list
        }
        val layer = list.getOrNull(first) ?: return layers
        val stack = layer.content as? LayerContent.Stack ?: return layers
        list[first] = layer.copy(content = stack.copy(children = siblings(path.drop(1), stack.children, body)))
        return list
    }

    fun replace(path: List<Int>, layers: List<Layer>, with: Layer): List<Layer> =
        siblings(path, layers) { list -> path.last().let { if (it in list.indices) list[it] = with } }

    /** A stack keeps at least one child. */
    fun remove(path: List<Int>, layers: List<Layer>): List<Layer> = siblings(path, layers) { list ->
        val last = path.last()
        if (last in list.indices && (path.size == 1 || list.size > 1)) list.removeAt(last)
    }

    /** A copy right after the layer; a top-level copy moves 6 units so both show. */
    fun duplicate(path: List<Int>, layers: List<Layer>): List<Layer> = siblings(path, layers) { list ->
        val last = path.last()
        if (last !in list.indices) return@siblings
        var copy = list[last]
        if (path.size == 1) copy = copy.copy(frame = copy.frame.copy(x = copy.frame.x + 6, y = copy.frame.y + 6))
        list.add(last + 1, copy)
    }

    /** Moves the layer at [from] to [to] among its siblings (`[]` parent = the top level). */
    fun move(parent: List<Int>, from: Int, to: Int, layers: List<Layer>): List<Layer> = siblings(parent + 0, layers) { list ->
        if (from !in list.indices) return@siblings
        val item = list.removeAt(from)
        list.add(to.coerceIn(0, list.size), item)
    }

    fun canStack(layer: Layer) = when (layer.content) {
        is LayerContent.Text, is LayerContent.Icon, is LayerContent.Stack, is LayerContent.Shape, is LayerContent.Ring,
        is LayerContent.ProgressBar, is LayerContent.AnalogClock -> true
        else -> false
    }

    fun depth(layer: Layer): Int = (layer.content as? LayerContent.Stack)?.let { 1 + (it.children.maxOfOrNull(::depth) ?: 0) } ?: 0

    private fun axis(frames: List<Frame>): String {
        val xs = frames.map { it.x + it.w / 2 }
        val ys = frames.map { it.y + it.h / 2 }
        val spreadX = (xs.maxOrNull() ?: 0.0) - (xs.minOrNull() ?: 0.0)
        val spreadY = (ys.maxOrNull() ?: 0.0) - (ys.minOrNull() ?: 0.0)
        return if (spreadX > maxOf(spreadY * 2, 20.0)) "horizontal" else "vertical"
    }

    private fun precedes(a: Frame, b: Frame, axis: String): Boolean {
        val (pa, pb) = if (axis == "horizontal") (a.x + a.w / 2 to a.y) to (b.x + b.w / 2 to b.y) else (a.y + a.h / 2 to a.x) to (b.y + b.h / 2 to b.x)
        return pa.first < pb.first || (pa.first == pb.first && pa.second < pb.second)
    }

    private fun sorted(items: List<Layer>, axis: String) = items.sortedWith { a, b -> if (precedes(a.frame, b.frame, axis)) -1 else if (precedes(b.frame, a.frame, axis)) 1 else 0 }

    fun union(frames: List<Frame>): Frame {
        val minX = frames.minOf { it.x }
        val minY = frames.minOf { it.y }
        return Frame(minX, minY, frames.maxOf { it.x + it.w } - minX, frames.maxOf { it.y + it.h } - minY)
    }

    private const val SPACER_GAP = 16.0
    private val zero = Frame(0.0, 0.0, 0.0, 0.0)

    private fun line(items: List<Layer>, axis: String, keepsRowFrames: Boolean = false): LayerContent.Stack {
        val children = mutableListOf<Layer>()
        items.forEachIndexed { index, item ->
            if (index > 0) {
                val previous = items[index - 1].frame
                val gap = if (axis == "horizontal") item.frame.x - (previous.x + previous.w) else item.frame.y - (previous.y + previous.h)
                val trailing = axis == "horizontal" && (item.content as? LayerContent.Text)?.align == "trailing"
                if (gap > SPACER_GAP || trailing) children += Layer(zero, null, null, null, null, LayerContent.Spacer(null))
            }
            val frame = when (item.content) {
                is LayerContent.Text, is LayerContent.Icon -> zero
                is LayerContent.Stack -> if (keepsRowFrames) zero else Frame(0.0, 0.0, item.frame.w, item.frame.h)
                else -> Frame(0.0, 0.0, item.frame.w, item.frame.h)
            }
            children += item.copy(frame = frame, mirror = null)
        }
        return LayerContent.Stack(axis, spacing(items.map { it.frame }, axis), null, alignment(items, axis), null, null, children)
    }

    private fun rows(layers: List<Layer>): List<List<Layer>> {
        fun centerY(f: Frame) = f.y + f.h / 2
        val rows = mutableListOf<MutableList<Layer>>()
        for (layer in layers.sortedBy { centerY(it.frame) }) {
            val first = rows.lastOrNull()?.firstOrNull()
            if (first != null && abs(centerY(layer.frame) - centerY(first.frame)) < minOf(layer.frame.h, first.frame.h) / 2) rows.last() += layer
            else rows += mutableListOf(layer)
        }
        return rows.flatMap { row ->
            val xs = row.map { it.frame.x + it.frame.w / 2 }
            if (row.size > 1 && (xs.max() - xs.min()) < 20) sorted(row, "vertical").map { listOf(it) } else listOf(sorted(row, "horizontal"))
        }
    }

    private fun spacing(frames: List<Frame>, axis: String): Double {
        val gaps = frames.zipWithNext { a, b -> if (axis == "horizontal") b.x - (a.x + a.w) else b.y - (a.y + a.h) }.filter { it > 0 }
        if (gaps.isEmpty()) return 4.0
        return Math.rint(gaps.average()).coerceIn(2.0, 12.0)
    }

    private fun alignment(layers: List<Layer>, axis: String): String? {
        if (axis != "vertical") return null
        val align = layers.firstNotNullOfOrNull { (it.content as? LayerContent.Text)?.let { t -> t.align ?: "leading" } } ?: "leading"
        return when (align) {
            "center" -> "center"
            "trailing" -> "end"
            else -> null
        }
    }

    /**
     * Wraps top-level layers in one stack over their combined frame: rows held apart by spacers
     * in a column. Returns the new list and the stack's index, or null when they can't share one.
     */
    fun group(indexes: Collection<Int>, layers: List<Layer>, chosenAxis: String? = null): Pair<List<Layer>, Int>? {
        val members = indexes.toSortedSet().filter { it in layers.indices }
        if (members.size < 2 || members.size > SpecValidator.MAX_CHILDREN) return null
        val picked = members.map { layers[it] }
        if (!picked.all(::canStack) || (picked.maxOf(::depth) + 1) > SpecValidator.MAX_STACK_DEPTH) return null
        val stack = if (chosenAxis != null) line(sorted(picked, chosenAxis), chosenAxis) else {
            val rows = rows(picked)
            if (rows.size == 1) line(rows[0], "horizontal") else {
                if (!rows.all { it.size == 1 } && picked.maxOf(::depth) + 2 > SpecValidator.MAX_STACK_DEPTH) return null
                val items = rows.map { row -> if (row.size == 1) row[0] else Layer(union(row.map { it.frame }), null, null, null, null, line(row, "horizontal")) }
                line(items, "vertical", keepsRowFrames = true)
            }
        }
        if (stack.children.size > SpecValidator.MAX_CHILDREN) return null
        val stackLayer = Layer(union(picked.map { it.frame }), null, if (picked.any { it.mirror == true }) true else null, null, null, stack)
        val list = layers.toMutableList()
        members.reversed().forEach { list.removeAt(it) }
        val position = members.last() - (members.size - 1)
        list.add(position, stackLayer)
        return list to position
    }

    /** The stack's children back as top-level layers in bands across its frame. */
    fun ungroup(index: Int, layers: List<Layer>): List<Layer> {
        val layer = layers.getOrNull(index) ?: return layers
        val stack = layer.content as? LayerContent.Stack ?: return layers
        val items = stack.children.filter { it.content !is LayerContent.Spacer }
        val count = maxOf(items.size, 1).toDouble()
        val f = layer.frame
        val freed = items.mapIndexed { offset, child ->
            val share = offset.toDouble()
            val frame = if (stack.axis == "horizontal") Frame(f.x + f.w * share / count, f.y, f.w / count, f.h) else Frame(f.x, f.y + f.h * share / count, f.w, f.h / count)
            child.copy(frame = frame, mirror = layer.mirror)
        }
        return layers.toMutableList().apply { removeAt(index); addAll(index, freed) }
    }

    /** Moves layers apart into bands along one axis, sized by their share (lists, calendars). */
    fun reflow(indexes: Collection<Int>, layers: List<Layer>): List<Layer> {
        val members = indexes.toSortedSet().filter { it in layers.indices }
        if (members.size < 2) return layers
        val frames = members.map { layers[it].frame }
        val axis = axis(frames)
        val bounds = union(frames)
        val order = members.sortedWith { a, b -> if (precedes(layers[a].frame, layers[b].frame, axis)) -1 else if (precedes(layers[b].frame, layers[a].frame, axis)) 1 else 0 }
        val gap = 2.0
        val total = order.sumOf { if (axis == "horizontal") layers[it].frame.w else layers[it].frame.h }
        val room = (if (axis == "horizontal") bounds.w else bounds.h) - gap * (order.size - 1)
        if (total <= 0 || room <= 0) return layers
        val list = layers.toMutableList()
        var cursor = if (axis == "horizontal") bounds.x else bounds.y
        for (index in order) {
            val f = list[index].frame
            val frame = if (axis == "horizontal") f.copy(x = cursor, w = room * f.w / total).also { cursor += it.w + gap }
            else f.copy(y = cursor, h = room * f.h / total).also { cursor += it.h + gap }
            list[index] = list[index].copy(frame = frame)
        }
        return list
    }
}

/** What happened to the layout of an AI answer (ADR-022). */
sealed class LayoutRepair {
    data object Clean : LayoutRepair()
    data class Fixed(val before: WidgetSpec) : LayoutRepair()
    data class NeedsEditing(val problems: List<String>) : LayoutRepair()
}

/** Repairs the layout of the last AI answer locally (AILayoutFix.swift, ADR-022/023). */
object AILayoutFix {
    private const val MAX_PASSES = 8

    fun fix(spec: WidgetSpec): WidgetSpec {
        var layers = spec.layers.map { layer ->
            val icon = layer.content as? LayerContent.Icon ?: return@map layer
            val side = minOf(layer.frame.w, layer.frame.h)
            if (icon.size > side * 1.15) layer.copy(content = icon.copy(size = floor(side))) else layer
        }
        layers = raiseCoveredTexts(layers)
        repeat(MAX_PASSES) {
            val group = firstGroup(layers, spec)
            if (group != null) {
                layers = LayerEditing.group(group, layers)?.first ?: LayerEditing.reflow(group, layers)
            } else {
                layers = trimAcrossContainers(layers, spec) ?: return spec.copy(layers = layers)
            }
        }
        return spec.copy(layers = layers)
    }

    private fun raiseCoveredTexts(start: List<Layer>): List<Layer> {
        var layers = start
        repeat(layers.size) {
            val (cover, text) = SpecLayout.coveredTexts(layers).firstOrNull() ?: return layers
            val list = layers.toMutableList()
            val layer = list.removeAt(text)
            list.add(cover, layer)
            layers = list
        }
        return layers
    }

    private fun firstGroup(layers: List<Layer>, spec: WidgetSpec): List<Int>? {
        val pairs = (SpecLayout.textOverlaps(layers) + SpecLayout.iconOverlaps(layers)).filter {
            SpecLayout.container(it.first, layers, spec.family) == SpecLayout.container(it.second, layers, spec.family)
        }
        val start = pairs.flatMap { listOf(it.first, it.second) }.minOrNull() ?: return null
        val group = mutableSetOf(start)
        var grew = true
        while (grew) {
            grew = false
            for ((a, b) in pairs) if ((a in group) != (b in group)) {
                group += a
                group += b
                grew = true
            }
        }
        return group.sorted()
    }

    /** A layer outside a shape that overlaps a text inside it shrinks to clear the shape. Null when nothing to trim. */
    private fun trimAcrossContainers(layers: List<Layer>, spec: WidgetSpec): List<Layer>? {
        for ((a, b) in SpecLayout.textOverlaps(layers) + SpecLayout.iconOverlaps(layers)) {
            val ca = SpecLayout.container(a, layers, spec.family)
            val cb = SpecLayout.container(b, layers, spec.family)
            if (ca == cb) continue
            val (outside, inner) = if (ca == null) a to cb else if (cb == null) b to ca else a to cb
            inner ?: continue
            val trimmed = clear(layers[outside].frame, layers[inner].frame) ?: continue
            return layers.toMutableList().apply { this[outside] = this[outside].copy(frame = trimmed) }
        }
        return null
    }

    private fun clear(frame: Frame, box: Frame): Frame? = listOf(
        Frame(frame.x, frame.y, frame.w, box.y - frame.y),
        Frame(frame.x, box.y + box.h, frame.w, frame.y + frame.h - (box.y + box.h)),
        Frame(frame.x, frame.y, box.x - frame.x, frame.h),
        Frame(box.x + box.w, frame.y, frame.x + frame.w - (box.x + box.w), frame.h),
    ).filter { it.w >= 20 && it.h >= 12 }.maxByOrNull { it.w * it.h }?.takeIf { it.w * it.h >= 0.35 * frame.w * frame.h }

    /** Every text a spec shows (the fix must keep them all). */
    fun texts(spec: WidgetSpec): List<String> = spec.layers.flatMap { it.flattened }.flatMap { layer ->
        when (val c = layer.content) {
            is LayerContent.Text -> c.value.allValues
            is LayerContent.ListL -> c.items.flatMap { it.title.allValues + (it.detail?.allValues ?: emptyList()) }
            else -> emptyList()
        }
    }.sorted()
}

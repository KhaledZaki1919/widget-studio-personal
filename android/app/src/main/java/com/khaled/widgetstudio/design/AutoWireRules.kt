package com.khaled.widgetstudio.design

import com.khaled.widgetstudio.spec.Bindings
import com.khaled.widgetstudio.spec.Capabilities
import com.khaled.widgetstudio.spec.Capability
import com.khaled.widgetstudio.spec.Frame
import com.khaled.widgetstudio.spec.Layer
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.StateSet
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max

/**
 * The post-pass steps of the product rules (AutoWireRules.swift, ADR-028). A percent, ring, bar or
 * dot grid takes the binding its nearest label names, never a default: with no label and no topic
 * it stays static and DesignRules lists it. A row of weather icons follows each day. A frozen mood
 * or illustration becomes a state layer from the catalog.
 */
internal val shareTopics = listOf("media", "volume", "brightness", "battery", "steps", "timer", "tasks", "year", "month", "week")

internal fun AutoWire.Run.words(layer: Layer): String {
    val text = layer.content as? LayerContent.Text ?: return ""
    val parts = text.value.allValues.filter { !it.contains("{{") }.toMutableList()
    for (name in text.value.allValues.flatMap(AutoWire::names)) {
        val key = name.trim().takeIf { it.startsWith("field.") }?.removePrefix("field.") ?: continue
        val field = spec.field(key) ?: continue
        parts += field.label.allValues + (field.default?.allValues ?: emptyList())
    }
    return parts.joinToString(" ").lowercase()
}

internal fun AutoWire.Run.icons(layer: Layer): List<String> {
    val icon = layer.content as? LayerContent.Icon ?: return emptyList()
    return Bindings.soleBinding(icon.symbol)?.let { Capabilities.binding(it)?.icons ?: emptyList() } ?: listOf(icon.symbol)
}

/** Text and icons around a layer, nearest first; children of its own stack always count. */
internal fun AutoWire.Run.neighbors(item: AutoWire.Found, reach: Double = 60.0): List<AutoWire.Found> {
    fun distance(frame: Frame): Double {
        val dx = max(max(item.frame.x - (frame.x + frame.w), frame.x - (item.frame.x + item.frame.w)), 0.0)
        val dy = max(max(item.frame.y - (frame.y + frame.h), frame.y - (item.frame.y + item.frame.h)), 0.0)
        return hypot(dx, dy)
    }
    return AutoWire.walk(spec.layers).filter { other ->
        if (other.path == item.path) return@filter false
        if (other.layer.content !is LayerContent.Text && other.layer.content !is LayerContent.Icon) return@filter false
        val sameStack = item.path.size > 1 && other.path.size > 1 && item.path[0] == other.path[0]
        sameStack || distance(other.frame) <= reach
    }.sortedBy { distance(it.frame) }
}

/** Time shares last: "Daily steps" is about steps. */
private fun shares(kind: String): List<Capability> {
    val all = Capabilities.bindings.filter { it.isShare && it.ai && it.keywords.isNotEmpty() && (kind == "text" || kind in it.layers) }
    return all.filter { it.group != "time" } + all.filter { it.group == "time" }
}

private fun match(candidates: List<Capability>, words: String, icons: List<String>): Capability? =
    candidates.firstOrNull { capability -> capability.keywords.any { AutoWire.occurs(it, words) } || capability.icons.any { it in icons } }

/** What the nearest label names: the layer's own words first, then its neighbors in order. */
internal fun AutoWire.Run.namedShare(item: AutoWire.Found, kind: String, own: String = ""): String? {
    val candidates = shares(kind)
    match(candidates, own.lowercase(), emptyList())?.let { return it.id }
    for (other in neighbors(item)) match(candidates, words(other.layer), icons(other.layer))?.let { return it.id }
    return null
}

/** The binding for a share on this layer, or null when nothing says what it is: never a default. */
internal fun AutoWire.Run.shareBinding(item: AutoWire.Found, kind: String, own: String = ""): String? {
    namedShare(item, kind, own)?.let { return it }
    val toTry = if (kind == "text") shareTopics.filter { it != "media" } else shareTopics
    val prefix = topics.best(*toTry.toTypedArray()) ?: return null
    return shares(kind).firstOrNull { it.prefix == prefix }?.id
}

/** Whether the design shows any value of this topic. */
internal fun AutoWire.Run.showsTopic(prefix: String): Boolean =
    com.khaled.widgetstudio.spec.BindingNames.names(spec).any { it.trim().substringBefore('.') == prefix }

/** Whether anything near the layer speaks of this capability. */
internal fun AutoWire.Run.isNamed(capability: Capability, item: AutoWire.Found, own: String = ""): Boolean {
    if (capability.keywords.any { AutoWire.occurs(it, own.lowercase()) }) return true
    return neighbors(item).any { other ->
        capability.keywords.any { AutoWire.occurs(it, words(other.layer)) } || capability.icons.any { it in icons(other.layer) }
    }
}

/** The share a layer shows, when it shows exactly one. */
internal fun AutoWire.Run.boundShare(layer: Layer): Pair<Capability, String>? {
    val (value, kind) = when (val c = layer.content) {
        is LayerContent.Text -> c.value.resolved("en") to "text"
        is LayerContent.Ring -> c.progress to "ring"
        is LayerContent.ProgressBar -> c.progress to "progressBar"
        is LayerContent.DotGrid -> c.values to "dotGrid"
        else -> return null
    }
    val bound = AutoWire.names(value).mapNotNull { Capabilities.binding(it) }.filter { it.isShare }
    return if (bound.size == 1) bound[0] to kind else null
}

/** The drawn set this layer stands for: the only one the card is about, or the nearest. */
internal fun AutoWire.Run.artSet(item: AutoWire.Found): StateSet? {
    val drawn = Capabilities.stateSets.filter { set ->
        set.variants.firstOrNull()?.layers?.firstOrNull()?.content is LayerContent.DotGrid && set.topic != null && topics.has(set.topic)
    }
    if (drawn.size <= 1) return drawn.firstOrNull()
    return drawn.firstOrNull { set -> Capabilities.bindings.any { it.prefix == set.topic && isNamed(it, item) } }
}

/** The indexes of the pieces inside a head, when the layer at [index] is one. */
internal fun AutoWire.Run.faceParts(index: Int, layers: List<Layer>): List<Int>? {
    val head = layers[index]
    val shape = head.content as? LayerContent.Shape ?: return null
    if (shape.kind != "circle" || head.frame.w < 36 || abs(head.frame.w - head.frame.h) > 4) return null
    val inside = layers.indices.filter { other ->
        val piece = layers[other].content as? LayerContent.Shape
        other != index && piece != null && layers[other].condition == null && (piece.fill != null || piece.stroke != null) &&
            AutoWire.inside(layers[other].frame, head.frame) && layers[other].frame.w < head.frame.w * 0.6
    }
    val eyes = inside.count { other -> (layers[other].content as? LayerContent.Shape)?.kind == "circle" && layers[other].frame.w <= head.frame.w * 0.3 }
    return if (eyes >= 2) inside else null
}

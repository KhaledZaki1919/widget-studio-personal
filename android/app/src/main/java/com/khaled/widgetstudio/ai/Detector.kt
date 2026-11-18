package com.khaled.widgetstudio.ai

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.RectF
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/** One widget found in a picked image, in image pixels (origin top left). */
data class DetectedWidget(val rect: RectF, val shape: CardShape) {
    /** Wide → medium; as wide as most of the image (a large widget on a home screen) → large; else small. */
    fun suggestedSize(imageWidth: Int): String {
        if (rect.height() <= 0) return "auto"
        val aspect = rect.width() / rect.height()
        if (aspect > 1.5f) return "medium"
        if (shape != CardShape.CIRCLE && rect.width() > 0.6f * imageWidth && aspect > 0.75f) return "large"
        return "small"
    }
}

/**
 * Finds the widget card(s) in a screenshot or design (ADR-024; WidgetDetector.swift uses Apple's
 * Vision, which Android doesn't have, so this works on the pixels):
 * 1. a downscaled copy is split into regions of near-equal neighboring colors (smooth gradients
 *    stay one region), each with its box and pixel count;
 * 2. regions that don't touch the image edge and cover at least 1.5 % of it are candidates;
 * 3. each candidate's corner radius is measured along the four diagonals: about half the short
 *    side means a circle (square box) or a capsule, less a rounded rectangle. Candidates whose four
 *    corners disagree (a wallpaper blob half hidden behind a card) are dropped, and so are those
 *    that fill too little of their box for their shape, counting the text inside them;
 * 4. candidates inside another candidate are dropped;
 * 5. with no card, the content floating on the wallpaper (all small regions off the edge) is boxed.
 * Results are in reading order; empty means "use the whole image".
 */
object WidgetDetector {
    private const val WORK_SIDE = 256
    private const val MIN_AREA = 0.015
    private const val NEIGHBOR = 14

    fun detect(image: Bitmap): List<DetectedWidget> {
        val scale = min(1f, WORK_SIDE.toFloat() / max(image.width, image.height))
        val small = if (scale < 1f) Bitmap.createScaledBitmap(image, max(1, (image.width * scale).toInt()), max(1, (image.height * scale).toInt()), true) else image
        val w = small.width
        val h = small.height
        val pixels = IntArray(w * h)
        small.getPixels(pixels, 0, w, 0, 0, w, h)
        val labels = segment(pixels, w, h)
        val regions = regions(labels, w, h)
        val total = (w * h).toDouble()

        val candidates = regions.values.filter { r ->
            r.count >= MIN_AREA * total && !r.touchesEdge(w, h) && r.width >= 6 && r.height >= 6
        }.mapNotNull { r ->
            val radii = cornerRadii(labels, w, r) ?: return@mapNotNull null
            val short = min(r.width, r.height).toFloat()
            val spread = radii.max() - radii.min()
            if (spread > max(4f, 0.35f * radii.max())) return@mapNotNull null   // corners disagree: a half-hidden shape
            val radius = radii.sorted()[1] / 2 + radii.sorted()[2] / 2
            val aspect = r.width.toFloat() / r.height
            val shape = if (radius >= 0.4f * short) (if (aspect > 0.85f && aspect < 1.18f) CardShape.CIRCLE else CardShape.CAPSULE) else CardShape.ROUNDED_RECT
            // How much of the box the region fills, counting the regions (text) inside it.
            val inside = regions.values.filter { it.label != r.label && it.minX >= r.minX && it.maxX <= r.maxX && it.minY >= r.minY && it.maxY <= r.maxY }.sumOf { it.count }
            val fill = (r.count + inside).toDouble() / (r.width.toDouble() * r.height)
            val expected = when (shape) {
                CardShape.CIRCLE -> Math.PI / 4
                CardShape.CAPSULE -> 1 - (short / max(r.width, r.height)) * (1 - Math.PI / 4)
                else -> 1 - (4 - Math.PI) * (radius * radius) / (r.width.toDouble() * r.height)
            }
            if (fill < 0.88 * expected) return@mapNotNull null
            r to shape
        }
        var kept = candidates.filter { (r, _) ->
            candidates.none { (o, _) -> o !== r && o.minX <= r.minX && o.maxX >= r.maxX && o.minY <= r.minY && o.maxY >= r.maxY && o.count > r.count }
        }.map { (r, shape) -> DetectedWidget(RectF(r.minX / scale, r.minY / scale, (r.maxX + 1) / scale, (r.maxY + 1) / scale), shape) }
        if (kept.isEmpty()) kept = listOfNotNull(floating(regions.values, w, h, scale, image))
        return readingOrder(kept)
    }

    private class Region(val label: Int) {
        var count = 0
        var minX = Int.MAX_VALUE
        var minY = Int.MAX_VALUE
        var maxX = -1
        var maxY = -1
        val width get() = maxX - minX + 1
        val height get() = maxY - minY + 1
        fun touchesEdge(w: Int, h: Int) = minX <= 0 || minY <= 0 || maxX >= w - 1 || maxY >= h - 1
    }

    /** Union-find over neighbors whose channels differ by at most [NEIGHBOR]. */
    private fun segment(pixels: IntArray, w: Int, h: Int): IntArray {
        val parent = IntArray(pixels.size) { it }
        fun find(i: Int): Int {
            var x = i
            while (parent[x] != x) {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }
        fun close(a: Int, b: Int) = abs(Color.red(a) - Color.red(b)) <= NEIGHBOR && abs(Color.green(a) - Color.green(b)) <= NEIGHBOR && abs(Color.blue(a) - Color.blue(b)) <= NEIGHBOR
        for (y in 0 until h) for (x in 0 until w) {
            val i = y * w + x
            if (x + 1 < w && close(pixels[i], pixels[i + 1])) parent[find(i)] = find(i + 1)
            if (y + 1 < h && close(pixels[i], pixels[i + w])) parent[find(i)] = find(i + w)
        }
        return IntArray(pixels.size) { find(it) }
    }

    private fun regions(labels: IntArray, w: Int, h: Int): Map<Int, Region> {
        val map = HashMap<Int, Region>()
        for (y in 0 until h) for (x in 0 until w) {
            val r = map.getOrPut(labels[y * w + x]) { Region(labels[y * w + x]) }
            r.count++
            if (x < r.minX) r.minX = x
            if (x > r.maxX) r.maxX = x
            if (y < r.minY) r.minY = y
            if (y > r.maxY) r.maxY = y
        }
        return map
    }

    /** Each corner's radius from how far its diagonal runs before reaching the region: r(√2 − 1). */
    private fun cornerRadii(labels: IntArray, w: Int, r: Region): List<Float>? {
        val limit = min(r.width, r.height) / 2
        val corners = listOf(Triple(r.minX, r.minY, 1 to 1), Triple(r.maxX, r.minY, -1 to 1), Triple(r.minX, r.maxY, 1 to -1), Triple(r.maxX, r.maxY, -1 to -1))
        return corners.map { (x0, y0, step) ->
            var s = 0
            while (s < limit && labels[(y0 + s * step.second) * w + (x0 + s * step.first)] != r.label) s++
            if (s >= limit) return null
            (s * sqrt(2.0) / (sqrt(2.0) - 1)).toFloat()
        }
    }

    /** No card: the small regions off the edge (text, numbers) boxed together, padded 8 %. */
    private fun floating(regions: Collection<Region>, w: Int, h: Int, scale: Float, image: Bitmap): DetectedWidget? {
        val parts = regions.filter { !it.touchesEdge(w, h) && it.count >= 0.0002 * w * h }
        if (parts.isEmpty()) return null
        val minX = parts.minOf { it.minX }
        val minY = parts.minOf { it.minY }
        val maxX = parts.maxOf { it.maxX } + 1
        val maxY = parts.maxOf { it.maxY } + 1
        val pad = 0.08f * max(maxX - minX, maxY - minY)
        val box = RectF((minX - pad) / scale, (minY - pad) / scale, (maxX + pad) / scale, (maxY + pad) / scale)
        box.intersect(0f, 0f, image.width.toFloat(), image.height.toFloat())
        if (box.width() * box.height() >= 0.9f * image.width * image.height) return null
        return DetectedWidget(box, CardShape.NONE)
    }

    private fun readingOrder(widgets: List<DetectedWidget>) = widgets.sortedWith { a, b ->
        if (abs(a.rect.centerY() - b.rect.centerY()) < min(a.rect.height(), b.rect.height()) / 2) a.rect.left.compareTo(b.rect.left)
        else a.rect.centerY().compareTo(b.rect.centerY())
    }

    fun crop(image: Bitmap, rect: RectF): Bitmap? {
        val left = rect.left.toInt().coerceIn(0, image.width - 1)
        val top = rect.top.toInt().coerceIn(0, image.height - 1)
        val right = rect.right.toInt().coerceIn(left + 1, image.width)
        val bottom = rect.bottom.toInt().coerceIn(top + 1, image.height)
        if (right - left < 8 || bottom - top < 8) return null
        return Bitmap.createBitmap(image, left, top, right - left, bottom - top)
    }

    /** The most common color (quantized) in a ring just outside [rect], or along the image's edge. */
    fun wallpaperColor(image: Bitmap, rect: RectF?): String? {
        val w = image.width
        val h = image.height
        val pixels = IntArray(w * h)
        image.getPixels(pixels, 0, w, 0, 0, w, h)
        val ring = rect?.let { max(4f, 0.04f * max(it.width(), it.height())) } ?: 0f
        val outer = rect?.let { RectF(it.left - ring, it.top - ring, it.right + ring, it.bottom + ring) }
        val counts = HashMap<Int, IntArray>()
        val step = max(1, max(w, h) / 400)
        for (y in 0 until h step step) for (x in 0 until w step step) {
            val inRing = outer != null && rect != null && outer.contains(x.toFloat(), y.toFloat()) && !rect.contains(x.toFloat(), y.toFloat())
            val onEdge = x < step * 2 || y < step * 2 || x >= w - step * 2 || y >= h - step * 2
            if (!inRing && !onEdge) continue
            val p = pixels[y * w + x]
            val key = (Color.red(p) shr 4 shl 8) or (Color.green(p) shr 4 shl 4) or (Color.blue(p) shr 4)
            val entry = counts.getOrPut(key) { IntArray(4) }
            entry[0]++; entry[1] += Color.red(p); entry[2] += Color.green(p); entry[3] += Color.blue(p)
        }
        val best = counts.values.maxByOrNull { it[0] } ?: return null
        return "#%02X%02X%02X".format(best[1] / best[0], best[2] / best[0], best[3] / best[0])
    }
}

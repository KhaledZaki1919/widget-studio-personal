package com.khaled.widgetstudio.render

import android.graphics.Canvas
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.SpannableStringBuilder
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.text.style.AbsoluteSizeSpan
import android.text.style.MetricAffectingSpan
import com.khaled.widgetstudio.spec.FontSpec
import com.khaled.widgetstudio.spec.LayerContent
import java.time.Duration
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.ceil

/**
 * Text layers (TextLayerView.swift): the spec font, Arabic text one point larger in a Latin
 * family, tracking for Latin only, "°" in the system font inside dot text, at most `maxLines`
 * lines (explicit line breaks always get theirs), shrinking to half size before truncating.
 * `leading`/`trailing` are the canvas's left and right (the canvas is always left to right).
 */
internal class TextDrawer(private val d: Drawing) {
    /** The string a text layer shows, bindings resolved and Latin runs isolated. */
    fun value(text: LayerContent.Text): String {
        val context = d.context
        when (text.liveKind) {
            "time" -> return DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(context.locale).format(context.now.atZone(context.zone))
            "timer", "relative" -> {
                val target = text.liveTarget?.let(d.resolver::date) ?: return "--"
                return frozen(Duration.between(minOf(context.now, target), maxOf(context.now, target)))
            }
        }
        return BidiText.isolatingNumbers(cased(d.resolver.render(text.value.resolved(context.language)), text.case))
    }

    private fun cased(value: String, case: String?): String = when (case) {
        "upper" -> value.uppercase(d.context.locale)
        "lower" -> value.lowercase(d.context.locale)
        else -> value
    }

    /** ADR-029: the runs of a text, each with its own font, color, raised baseline, case and tracking. */
    fun spans(text: LayerContent.Text, scale: Float): CharSequence {
        val builder = SpannableStringBuilder()
        for (span in text.spans ?: emptyList()) {
            val value = BidiText.isolatingNumbers(cased(d.resolver.render(span.text.resolved(d.context.language)), span.case ?: text.case))
            if (value.isEmpty()) continue
            val start = builder.length
            builder.append(value)
            val end = builder.length
            val font = span.font ?: text.font
            val arabic = Fonts.containsArabic(value)
            builder.setSpan(TypefaceSpanCompat(d.renderer.fonts.typeface(font, value)), start, end, 0)
            builder.setSpan(AbsoluteSizeSpan(((font.size + if (arabic && font.family != "arabic") 1 else 0) * scale).toInt()), start, end, 0)
            builder.setSpan(android.text.style.ForegroundColorSpan(d.color(span.color ?: text.color)), start, end, 0)
            span.baselineOffset?.let { builder.setSpan(BaselineSpan((it * scale).toFloat()), start, end, 0) }
            val tracking = span.tracking ?: text.tracking
            if (!arabic && tracking != null) builder.setSpan(TrackingSpan((tracking * scale).toFloat()), start, end, 0)
        }
        return builder
    }

    /** Text along a circle (ArcTextView.swift): each character placed and turned on the arc, centered on `start`. */
    fun drawArc(canvas: Canvas, text: LayerContent.Text, value: String, rect: RectF, scale: Float) {
        val path = text.path ?: return
        val size = (text.font.size * scale).toFloat()
        val radius = path.arc?.let { (it * scale).toFloat() } ?: maxOf(minOf(rect.width(), rect.height()) / 2 - size * 0.7f, size)
        val inside = path.inside == true
        val paint = paint(text.font, value, scale, null).apply { color = d.color(text.color); textAlign = android.graphics.Paint.Align.CENTER }
        val advances = value.map { paint.measureText(it.toString()) + ((text.tracking ?: 0.0) * scale).toFloat() }
        val total = advances.sum()
        val degreesPerUnit = 180.0 / (Math.PI * maxOf(radius, 1f))
        val sign = if (inside) -1 else 1
        val start = (path.start ?: 0.0) - total * degreesPerUnit / 2 * sign
        val cx = rect.centerX()
        val cy = rect.centerY()
        var before = 0f
        value.forEachIndexed { index, character ->
            val angle = start + (before + advances[index] / 2) * degreesPerUnit * sign
            before += advances[index]
            val radians = Math.toRadians(angle)
            val x = cx + (Math.sin(radians) * radius).toFloat()
            val y = cy - (Math.cos(radians) * radius).toFloat()
            canvas.save()
            canvas.rotate((if (inside) angle + 180 else angle).toFloat(), x, y)
            val metrics = paint.fontMetrics
            canvas.drawText(character.toString(), x, y - (metrics.ascent + metrics.descent) / 2, paint)
            canvas.restore()
        }
    }

    /** "12m", "2h 5m", "3d 4h": two units at most, like DateComponentsFormatter (abbreviated). */
    private fun frozen(duration: Duration): String {
        val arabic = d.context.isArabic
        val parts = listOf(
            duration.toDays() / 30 to if (arabic) " شهر" else "mo",
            duration.toDays() % 30 to if (arabic) " ي" else "d",
            duration.toHours() % 24 to if (arabic) " س" else "h",
            duration.toMinutes() % 60 to if (arabic) " د" else "m",
        ).dropWhile { it.first == 0L }.take(2).filter { it.first > 0 }
        return if (parts.isEmpty()) (if (arabic) "0 د" else "0m") else parts.joinToString(" ") { "${it.first}${it.second}" }
    }

    fun paint(font: FontSpec, value: String, scale: Float, tracking: Double?): TextPaint {
        val arabic = Fonts.containsArabic(value)
        val size = ((font.size + if (arabic && font.family != "arabic") 1 else 0) * scale).toFloat()
        return TextPaint(TextPaint.ANTI_ALIAS_FLAG).apply {
            typeface = d.renderer.fonts.typeface(font, value)
            textSize = size
            // Letter spacing breaks Arabic letter joining, so tracking applies to Latin text only.
            if (!arabic && tracking != null && size > 0) letterSpacing = (tracking * scale / size).toFloat()
        }
    }

    /** Dot text draws "°" in the system font at 0.8 size. */
    fun styled(font: FontSpec, value: String, paint: TextPaint): CharSequence {
        if (Fonts.effectiveFamily(font, value) != "dot" || !value.contains('°')) return value
        val builder = SpannableStringBuilder(value)
        val system = d.renderer.fonts.system(font.weight ?: "regular")
        var index = value.indexOf('°')
        while (index >= 0) {
            builder.setSpan(TypefaceSpanCompat(system), index, index + 1, 0)
            builder.setSpan(AbsoluteSizeSpan((paint.textSize * 0.8f).toInt()), index, index + 1, 0)
            index = value.indexOf('°', index + 1)
        }
        return builder
    }

    fun draw(canvas: Canvas, text: LayerContent.Text, rect: RectF, scale: Float, mirrored: Boolean, stackAlign: String?, fillWidth: Boolean) {
        val value = value(text)
        if (text.path != null && text.liveKind == null) return drawArc(canvas, text, value, rect, scale)
        var align = text.align ?: stackAlign ?: "leading"
        if (mirrored) align = when (align) {
            "leading" -> "trailing"
            "trailing" -> "leading"
            else -> align
        }
        val minimum = (text.minScale ?: 0.5).coerceIn(0.3, 1.0).toFloat()
        if (!text.spans.isNullOrEmpty() && text.liveKind == null) {
            // Runs: laid out as one paragraph, shrunk together until they fit.
            var factor = 1f
            while (true) {
                val styled = spans(text, scale * factor)
                val paint = paint(text.font, value, scale * factor, text.tracking).apply { color = d.color(text.color) }
                val lines = maxOf(text.maxLines ?: 1, value.count { it == '\n' } + 1)
                val layout = layout(styled, paint, rect.width(), lines, align, ellipsize = factor <= minimum)
                val wide = lines == 1 && Layout.getDesiredWidth(styled, paint) > rect.width() + 0.5f
                if ((!wide && layout.height <= rect.height() + 0.5f && layout.lineCount <= lines) || factor <= minimum) {
                    canvas.save()
                    canvas.translate(rect.left, rect.top + (rect.height() - layout.height) / 2)
                    layout.draw(canvas)
                    canvas.restore()
                    return
                }
                factor = maxOf(minimum, factor - 0.05f)
            }
        }
        drawFitted(canvas, value, text.font, d.color(text.color), align, text.maxLines, text.tracking, rect, scale, minimum)
    }

    /** Lays out [value] in [rect], shrinking to 50 % before truncating, vertically centered. */
    fun drawFitted(
        canvas: Canvas, value: String, font: FontSpec, color: Int, align: String, maxLines: Int?, tracking: Double?,
        rect: RectF, scale: Float, minimumScale: Float = 0.5f,
    ) {
        if (value.isEmpty() || rect.width() <= 0) return
        val lines = maxOf(maxLines ?: 1, value.count { it == '\n' } + 1)
        val layout = fit(value, font, tracking, scale, rect.width(), rect.height(), lines, align, minimumScale) { it.color = color }
        val top = rect.top + (rect.height() - layout.height) / 2
        canvas.save()
        canvas.translate(rect.left, top)
        layout.draw(canvas)
        canvas.restore()
    }

    /** The largest size (down to [minimumScale]) whose layout fits [width]×[height] in [lines] lines. */
    fun fit(
        value: String, font: FontSpec, tracking: Double?, scale: Float, width: Float, height: Float, lines: Int, align: String,
        minimumScale: Float = 0.5f, style: (TextPaint) -> Unit = {},
    ): StaticLayout {
        var factor = 1f
        while (true) {
            val paint = paint(font, value, scale * factor, tracking).also(style)
            val layout = layout(styled(font, value, paint), paint, width, lines, align, ellipsize = factor <= minimumScale)
            val fitsWidth = lines > 1 || naturalWidth(value, font, tracking, scale * factor) <= width + 0.5f
            val fitsLines = layout.lineCount <= lines && (lines > 1 || !overflowsLines(value, paint, width, lines))
            if ((fitsWidth && fitsLines && layout.height <= height + 0.5f) || factor <= minimumScale) return layout
            factor = maxOf(minimumScale, factor - 0.05f)
        }
    }

    private fun overflowsLines(value: String, paint: TextPaint, width: Float, lines: Int): Boolean =
        StaticLayout.Builder.obtain(value, 0, value.length, paint, ceil(width).toInt().coerceAtLeast(1)).build().lineCount > lines

    /** One-line width at [scale] (stacks size texts by it). */
    fun naturalWidth(value: String, font: FontSpec, tracking: Double?, scale: Float): Float {
        val paint = paint(font, value, scale, tracking)
        return value.split('\n').maxOf { line -> Layout.getDesiredWidth(styled(font, line, paint), paint) }
    }

    /** The height [value] takes at [width] in at most [lines] lines. */
    fun naturalHeight(value: String, font: FontSpec, tracking: Double?, scale: Float, width: Float, lines: Int): Float {
        val paint = paint(font, value, scale, tracking)
        return layout(styled(font, value, paint), paint, width, maxOf(lines, value.count { it == '\n' } + 1), "leading", true).height.toFloat()
    }

    fun layout(text: CharSequence, paint: TextPaint, width: Float, lines: Int, align: String, ellipsize: Boolean): StaticLayout {
        // The paragraph's own direction decides what "normal" means; map the canvas's left and right onto it.
        val rtl = firstStrongIsRtl(text)
        val alignment = when (align) {
            "center" -> Layout.Alignment.ALIGN_CENTER
            "trailing" -> if (rtl) Layout.Alignment.ALIGN_NORMAL else Layout.Alignment.ALIGN_OPPOSITE
            else -> if (rtl) Layout.Alignment.ALIGN_OPPOSITE else Layout.Alignment.ALIGN_NORMAL
        }
        return StaticLayout.Builder.obtain(text, 0, text.length, paint, ceil(width).toInt().coerceAtLeast(1))
            .setAlignment(alignment)
            .setMaxLines(lines)
            .setEllipsize(if (ellipsize) TextUtils.TruncateAt.END else null)
            .setIncludePad(false)
            .build()
    }

    private fun firstStrongIsRtl(text: CharSequence): Boolean {
        for (c in text) {
            when (Character.getDirectionality(c)) {
                Character.DIRECTIONALITY_RIGHT_TO_LEFT, Character.DIRECTIONALITY_RIGHT_TO_LEFT_ARABIC -> return true
                Character.DIRECTIONALITY_LEFT_TO_RIGHT -> return false
            }
        }
        return false
    }
}

/** Raises a run by a fixed amount (a superscript "AM"). */
private class BaselineSpan(private val shift: Float) : MetricAffectingSpan() {
    override fun updateDrawState(paint: TextPaint) {
        paint.baselineShift -= shift.toInt()
    }

    override fun updateMeasureState(paint: TextPaint) {
        paint.baselineShift -= shift.toInt()
    }
}

/** Letter spacing for one run, in pixels. */
private class TrackingSpan(private val pixels: Float) : MetricAffectingSpan() {
    override fun updateDrawState(paint: TextPaint) {
        if (paint.textSize > 0) paint.letterSpacing = pixels / paint.textSize
    }

    override fun updateMeasureState(paint: TextPaint) {
        if (paint.textSize > 0) paint.letterSpacing = pixels / paint.textSize
    }
}

/** A typeface span that works on API 26-27 (TypefaceSpan(Typeface) needs 28). */
private class TypefaceSpanCompat(private val typeface: Typeface) : MetricAffectingSpan() {
    override fun updateDrawState(paint: TextPaint) {
        paint.typeface = typeface
    }

    override fun updateMeasureState(paint: TextPaint) {
        paint.typeface = typeface
    }
}

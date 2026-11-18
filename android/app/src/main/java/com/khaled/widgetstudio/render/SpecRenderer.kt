package com.khaled.widgetstudio.render

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import com.khaled.widgetstudio.spec.Background
import com.khaled.widgetstudio.spec.BindingResolver
import com.khaled.widgetstudio.spec.Bindings
import com.khaled.widgetstudio.spec.Layer
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.RenderContext
import com.khaled.widgetstudio.spec.SpecTokens
import com.khaled.widgetstudio.spec.Theme
import com.khaled.widgetstudio.spec.WidgetSpec
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/** A button's tap area in bitmap pixels (brief §4.4). */
data class HitArea(val rect: RectF, val action: String, val arg: String?)

data class RenderResult(val bitmap: Bitmap, val buttons: List<HitArea>)

/**
 * Draws a spec into a bitmap with Android Canvas (ADR-025), the counterpart of SpecView.swift: the
 * canvas is laid out left to right and scaled uniformly into the bitmap, centered; in Arabic a
 * layer with `mirror: true` moves to the mirrored frame and swaps its own alignment and item order,
 * and nothing is ever flipped like an image (ADR-010). Every spec change must update both renderers.
 */
class SpecRenderer(context: Context) {
    val fonts = Fonts(context.assets)
    val icons = Icons(context.assets)

    /** [cornerRadius] clips the bitmap (in pixels); 0 leaves it square. */
    fun render(
        spec: WidgetSpec, context: RenderContext, width: Int, height: Int,
        drawsBackground: Boolean = true, cornerRadius: Float = 0f,
    ): RenderResult {
        val bitmap = Bitmap.createBitmap(width.coerceAtLeast(1), height.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val full = RectF(0f, 0f, width.toFloat(), height.toFloat())
        if (cornerRadius > 0f) canvas.clipPath(Path().apply { addRoundRect(full, cornerRadius, cornerRadius, Path.Direction.CW) })
        val draw = Drawing(this, spec, context)
        if (drawsBackground) draw.background(canvas, spec.background, full)
        val scale = min(width / spec.family.width, height / spec.family.height).toFloat()
        // ADR-029: layers live in the card's own canvas, placed where the card sits in the widget.
        val card = spec.cardFrame
        val ox = (width - spec.family.width.toFloat() * scale) / 2 + (card.x * scale).toFloat()
        val oy = (height - spec.family.height.toFloat() * scale) / 2 + (card.y * scale).toFloat()
        canvas.translate(ox, oy)
        val buttons = mutableListOf<HitArea>()
        for (layer in spec.layers) {
            if (layer.condition != null && !draw.resolver.isSatisfied(layer.condition)) continue
            val mirrored = context.isArabic && layer.mirror == true
            val frame = if (mirrored) layer.frame.mirrored(spec.canvasWidth) else layer.frame
            val rect = RectF(frame.x.toFloat() * scale, frame.y.toFloat() * scale, (frame.x + frame.w).toFloat() * scale, (frame.y + frame.h).toFloat() * scale)
            val content = layer.content
            if (content is LayerContent.Button) {
                buttons += HitArea(RectF(rect).apply { offset(ox, oy) }, content.action, content.arg?.let(draw.resolver::render))
                continue
            }
            draw.layer(canvas, layer, rect, scale, mirrored)
        }
        return RenderResult(bitmap, buttons)
    }
}

/** One render: the resolver, the theme's colors and every layer type. */
internal class Drawing(val renderer: SpecRenderer, val spec: WidgetSpec, val context: RenderContext) {
    val resolver = BindingResolver(spec, context)
    val theme: Theme = context.theme ?: spec.theme
    val text = TextDrawer(this)
    val charts = ChartDrawer(this)
    val chartPainter = ChartPainter(this)

    /** A spec color: `#RRGGBB(AA)` or a theme token; anything else is transparent. */
    fun color(value: String?, fallback: Int = Color.TRANSPARENT): Int {
        if (value == null) return fallback
        val hex = if (value.startsWith("@")) {
            val name = value.drop(1)
            context.tokenOverrides[name]?.takeIf { parseHex(it) != null } ?: SpecTokens.hex(name, theme) ?: return fallback
        } else value
        return parseHex(hex) ?: fallback
    }

    fun paint(color: Int, style: Paint.Style = Paint.Style.FILL) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color
        this.style = style
    }

    fun withAlpha(color: Int, alpha: Double) = Color.argb((Color.alpha(color) * alpha).toInt().coerceIn(0, 255), Color.red(color), Color.green(color), Color.blue(color))

    // MARK: Background

    fun background(canvas: Canvas, background: Background, rect: RectF) {
        val outer = background.outerColor
        val card = spec.card
        if (card != null && card.shape == "none") {
            fill(canvas, background, rect)
        } else if (card != null && card.hasOuter) {
            // ADR-029: the widget in the outer color, the card's fill clipped to its outline.
            canvas.drawRect(rect, paint(color(card.outerColor ?: outer ?: "@outer", android.graphics.Color.BLACK)))
            val scale = min(rect.width() / spec.family.width.toFloat(), rect.height() / spec.family.height.toFloat())
            val ox = rect.left + (rect.width() - spec.family.width.toFloat() * scale) / 2
            val oy = rect.top + (rect.height() - spec.family.height.toFloat() * scale) / 2
            val f = spec.cardFrame
            val cardRect = RectF(ox + (f.x * scale).toFloat(), oy + (f.y * scale).toFloat(), ox + ((f.x + f.w) * scale).toFloat(), oy + ((f.y + f.h) * scale).toFloat())
            canvas.save()
            canvas.clipPath(ShapeGeometry.card(card, cardRect, scale))
            fill(canvas, background, cardRect)
            canvas.restore()
        } else if (outer != null) {
            canvas.drawRect(rect, paint(color(outer)))
            val side = min(rect.width(), rect.height())
            val card = if (background.cardShape == "capsule") {
                // A pill card, inset a little so its round ends show (ADR-024).
                RectF(rect).apply { inset(side * 0.04f, side * 0.04f) }
            } else {
                RectF(rect.centerX() - side / 2, rect.centerY() - side / 2, rect.centerX() + side / 2, rect.centerY() + side / 2)
            }
            canvas.save()
            val radius = min(card.width(), card.height()) / 2
            canvas.clipPath(Path().apply { addRoundRect(card, radius, radius, Path.Direction.CW) })
            fill(canvas, background, card)
            canvas.restore()
        } else {
            fill(canvas, background, rect)
        }
    }

    private fun fill(canvas: Canvas, background: Background, rect: RectF) {
        when (background.type) {
            "gradient" -> {
                val angle = Math.toRadians(background.angle ?: 90.0)
                val dx = (cos(angle) / 2).toFloat()
                val dy = (sin(angle) / 2).toFloat()
                val colors = (background.colors ?: emptyList()).map { color(it) }.toIntArray()
                if (colors.size < 2) return
                val shader = LinearGradient(
                    rect.left + rect.width() * (0.5f - dx), rect.top + rect.height() * (0.5f - dy),
                    rect.left + rect.width() * (0.5f + dx), rect.top + rect.height() * (0.5f + dy), colors, null, Shader.TileMode.CLAMP,
                )
                canvas.drawRect(rect, Paint(Paint.ANTI_ALIAS_FLAG).apply { this.shader = shader })
            }
            "glass" -> {
                // A frosted panel (ADR-023): neutral base, translucent tint, sheen, thin light border.
                canvas.drawRect(rect, paint(parseHex(if (theme == Theme.DARK) "#1C1F24" else "#E4E7EB") ?: Color.DKGRAY))
                canvas.drawRect(rect, paint(color(background.color ?: "#FFFFFF2E")))
                sheen(canvas, rect, null, 0.22)
                canvas.drawRect(RectF(rect).apply { inset(0.5f, 0.5f) }, paint(Color.argb(71, 255, 255, 255), Paint.Style.STROKE).apply { strokeWidth = 1f })
            }
            else -> canvas.drawRect(rect, paint(color(background.color, Color.BLACK)))
        }
    }

    /** White fading out from the top leading corner to the center. */
    fun sheen(canvas: Canvas, rect: RectF, clip: Path?, alpha: Double) {
        val shader = LinearGradient(rect.left, rect.top, rect.centerX(), rect.centerY(), Color.argb((alpha * 255).toInt(), 255, 255, 255), Color.TRANSPARENT, Shader.TileMode.CLAMP)
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.shader = shader }
        if (clip != null) canvas.drawPath(clip, p) else canvas.drawRect(rect, p)
    }

    // MARK: Layers

    /** Draws one layer into [rect] (canvas pixels), with its rotation and opacity. */
    fun layer(canvas: Canvas, layer: Layer, rect: RectF, scale: Float, mirrored: Boolean, stackTextAlign: String? = null, fillWidth: Boolean = true) {
        val degrees = layer.rotation?.let(resolver::number)
        val opacity = layer.opacity ?: 1.0
        val saved = if (opacity < 1.0) canvas.saveLayerAlpha(null, (opacity * 255).toInt()) else canvas.save()
        if (degrees != null) canvas.rotate(degrees.toFloat(), rect.centerX(), rect.centerY())
        when (val content = layer.content) {
            is LayerContent.Text -> text.draw(canvas, content, rect, scale, mirrored, stackTextAlign, fillWidth)
            is LayerContent.Image -> image(canvas, content, rect, scale)
            is LayerContent.Shape -> shape(canvas, content, rect, scale)
            is LayerContent.Chart -> chartPainter.draw(canvas, content, rect, scale, mirrored)
            is LayerContent.Icon -> icon(canvas, content, rect, scale)
            is LayerContent.AnalogClock -> charts.analogClock(canvas, content, rect)
            is LayerContent.DotGrid -> charts.dotGrid(canvas, content, rect, scale, mirrored)
            is LayerContent.DotBars -> charts.dotBars(canvas, content, rect, scale, mirrored)
            is LayerContent.Ring -> charts.ring(canvas, content, rect, scale)
            is LayerContent.ForecastRow -> charts.forecast(canvas, content, rect, scale, mirrored)
            is LayerContent.CalendarMonth -> charts.calendar(canvas, content, rect, scale, mirrored)
            is LayerContent.ListL -> charts.list(canvas, content, rect, scale, mirrored)
            is LayerContent.ProgressBar -> charts.progress(canvas, content, rect, scale, mirrored)
            is LayerContent.Stack -> StackLayout(this).draw(canvas, content, rect, scale, mirrored)
            is LayerContent.States -> states(canvas, content, layer, rect)
            is LayerContent.Button, is LayerContent.Spacer, is LayerContent.Unknown -> Unit
        }
        canvas.restoreToCount(saved)
    }

    /** A state layer (ADR-028): the variant real data picks, fitted into [rect] by the same layer code. */
    private fun states(canvas: Canvas, states: LayerContent.States, layer: Layer, rect: RectF) {
        val variant = resolver.variant(states) ?: return
        val (boxWidth, boxHeight) = states.boxSize(layer.frame)
        val fitted = min(rect.width() / boxWidth.toFloat(), rect.height() / boxHeight.toFloat())
        val left = rect.left + (rect.width() - boxWidth.toFloat() * fitted) / 2
        val top = rect.top + (rect.height() - boxHeight.toFloat() * fitted) / 2
        for (child in variant.layers) {
            if (child.condition != null && !resolver.isSatisfied(child.condition)) continue
            val frame = child.frame
            val area = RectF(left + frame.x.toFloat() * fitted, top + frame.y.toFloat() * fitted, left + (frame.x + frame.w).toFloat() * fitted, top + (frame.y + frame.h).toFloat() * fitted)
            layer(canvas, child, area, fitted, false)
        }
    }

    fun shapePath(kind: String, rect: RectF, cornerRadius: Float): Path = Path().apply {
        when (kind) {
            "circle" -> {
                val r = min(rect.width(), rect.height()) / 2
                addCircle(rect.centerX(), rect.centerY(), r, Path.Direction.CW)
            }
            "capsule" -> {
                val r = min(rect.width(), rect.height()) / 2
                addRoundRect(rect, r, r, Path.Direction.CW)
            }
            "roundedRect" -> addRoundRect(rect, cornerRadius, cornerRadius, Path.Direction.CW)
            else -> addRect(rect, Path.Direction.CW)
        }
    }

    private fun shape(canvas: Canvas, shape: LayerContent.Shape, rect: RectF, scale: Float) {
        val glass = shape.glass == true
        val progress = shape.progress?.let(resolver::number)
        val path = ShapeGeometry.path(shape, rect, progress) ?: shapePath(shape.kind, rect, ((shape.cornerRadius ?: 16.0) * scale).toFloat())
        val fill = shape.fill ?: if (glass) "#FFFFFF26" else null
        if (shape.kind == "line") {
            // A line is drawn with its stroke, else with its fill color as a stroke.
            val stroke = shape.stroke
            canvas.drawPath(path, paint(color(stroke?.color ?: fill ?: "#FFFFFF"), Paint.Style.STROKE).apply {
                strokeWidth = ((stroke?.width ?: 2.0) * scale).toFloat()
                strokeCap = Paint.Cap.ROUND
                stroke?.dash?.takeIf { it.isNotEmpty() }?.let { dash -> pathEffect = DashPathEffect(dash.map { (it * scale).toFloat() }.toFloatArray(), 0f) }
            })
            return
        }
        if (shape.gradient != null) canvas.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = shader(shape.gradient, rect) })
        else if (fill != null) canvas.drawPath(path, paint(color(fill)))
        if (glass) {
            canvas.save()
            canvas.clipPath(path)
            sheen(canvas, rect, path, 0.2)
            canvas.restore()
        }
        val stroke = shape.stroke
        if (stroke != null) {
            val p = paint(color(stroke.color), Paint.Style.STROKE).apply {
                strokeWidth = (stroke.width * scale).toFloat()
                stroke.dash?.takeIf { it.isNotEmpty() }?.let { dash -> pathEffect = DashPathEffect(dash.map { (it * scale).toFloat() }.toFloatArray(), 0f) }
            }
            canvas.drawPath(path, p)
        } else if (glass) {
            canvas.drawPath(path, paint(Color.argb(77, 255, 255, 255), Paint.Style.STROKE).apply { strokeWidth = maxOf(0.5f, scale) })
        }
    }

    fun icon(canvas: Canvas, icon: LayerContent.Icon, rect: RectF, scale: Float) {
        val raw = resolver.soleValue(icon.symbol)?.let(resolver::display) ?: icon.symbol
        // ADR-029: any SF Symbol name maps to a Material symbol; outline draws the unfilled font.
        val outline = icon.style == "outline" || (icon.style == null && !raw.contains(".fill") && renderer.icons.isAllowed(raw.replace(Regex("$"), ".fill")))
        drawSymbol(canvas, renderer.icons.material(raw), rect.centerX(), rect.centerY(), (icon.size * scale).toFloat(), color(icon.color), outline)
    }

    /** A Material Symbols glyph by ligature, centered on (cx, cy), about [size] px tall; [outline] uses the unfilled font. */
    fun drawSymbol(canvas: Canvas, name: String, cx: Float, cy: Float, size: Float, color: Int, outline: Boolean = false) {
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = if (outline) renderer.fonts.symbolsOutline else renderer.fonts.symbols
            textSize = size * 1.1f
            this.color = color
            textAlign = Paint.Align.CENTER
        }
        val metrics = p.fontMetrics
        canvas.drawText(name, cx, cy - (metrics.ascent + metrics.descent) / 2, p)
    }

    private fun image(canvas: Canvas, image: LayerContent.Image, rect: RectF, scale: Float) {
        val path = when (image.mask) {
            "circle" -> shapePath("circle", rect, 0f)
            "roundedRect" -> shapePath("roundedRect", rect, ((image.cornerRadius ?: 16.0) * scale).toFloat())
            else -> shapePath("rect", rect, 0f)
        }
        canvas.save()
        canvas.clipPath(path)
        val binding = Bindings.soleBinding(image.source)?.trim()
        val photo = when {
            binding == null -> context.userImage
            binding == "media.artwork" -> context.mediaArtwork
            binding.startsWith("app.") && binding.endsWith(".icon") ->
                resolver.fieldValue(binding.drop(4).dropLast(5))?.let { context.images["app.$it.icon"] } ?: context.images[binding]
            else -> context.images[binding]
        }
        if (photo != null) {
            val fit = image.fit == "fit"
            val ratio = if (fit) min(rect.width() / photo.width, rect.height() / photo.height) else maxOf(rect.width() / photo.width, rect.height() / photo.height)
            val w = photo.width * ratio
            val h = photo.height * ratio
            canvas.drawBitmap(photo, null, RectF(rect.centerX() - w / 2, rect.centerY() - h / 2, rect.centerX() + w / 2, rect.centerY() + h / 2), Paint(Paint.FILTER_BITMAP_FLAG))
        } else {
            // No photo yet: a neutral placeholder, as on iOS.
            canvas.drawRect(rect, paint(Color.argb(64, 128, 128, 128)))
            drawSymbol(canvas, "image", rect.centerX(), rect.centerY(), 18 * scale, Color.argb(150, 128, 128, 128))
        }
        canvas.restore()
    }

    companion object {
        /** `#RRGGBB` or `#RRGGBBAA` (the spec's order) → Android ARGB. */
        fun parseHex(hex: String): Int? {
            if (!hex.startsWith("#")) return null
            val digits = hex.drop(1)
            if (digits.length != 6 && digits.length != 8) return null
            val value = digits.toLongOrNull(16) ?: return null
            return if (digits.length == 6) (0xFF000000 or value).toInt()
            else (((value and 0xFF) shl 24) or (value shr 8)).toInt()
        }
    }
}

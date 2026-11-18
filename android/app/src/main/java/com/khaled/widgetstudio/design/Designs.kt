package com.khaled.widgetstudio.design

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.text.format.DateFormat
import com.khaled.widgetstudio.spec.DataSnapshot
import com.khaled.widgetstudio.spec.Frame
import com.khaled.widgetstudio.spec.LText
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.RenderContext
import com.khaled.widgetstudio.spec.SpecParser
import com.khaled.widgetstudio.spec.SpecWriter
import com.khaled.widgetstudio.spec.Theme
import com.khaled.widgetstudio.spec.WidgetSpec
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.util.UUID
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/** 12/24-hour choice (ClockFormat.swift); `device` follows the phone's setting. */
enum class ClockFormat {
    DEVICE, H12, H24;

    fun uses24Hour(context: Context): Boolean = when (this) {
        H12 -> false
        H24 -> true
        DEVICE -> DateFormat.is24HourFormat(context)
    }

    companion object {
        fun of(raw: String?) = entries.firstOrNull { it.name.equals(raw, ignoreCase = true) }
    }
}

/**
 * A design the user saved (SavedDesign.swift, M3): a template's spec (edited freely in the layer
 * editor), field values, theme, color overrides, clock choice and a processed photo.
 */
data class SavedDesign(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val templateId: String,
    val spec: WidgetSpec,
    val fieldValues: Map<String, LText> = emptyMap(),
    val theme: Theme? = null,
    val colors: Map<String, String> = emptyMap(),
    val imageFile: String? = null,
    val clockFormat: ClockFormat? = null,
    val created: Long = System.currentTimeMillis(),
    val updated: Long = created,
) {
    val effectiveTheme: Theme get() = theme ?: spec.theme

    /** The image layer the photo is processed for, if the design has one. */
    val imageLayer: Pair<Frame, LayerContent.Image>?
        get() = spec.layers.firstNotNullOfOrNull { layer ->
            (layer.content as? LayerContent.Image)?.takeIf { it.source == "user_image" }?.let { layer.frame to it }
        }

    fun renderContext(context: Context, now: Instant, language: String, data: DataSnapshot, image: Bitmap?, defaultClock: ClockFormat) =
        RenderContext(
            now = now, language = language, zone = ZoneId.systemDefault(), fieldValues = fieldValues, data = data, userImage = image,
            freezesLiveText = true, uses24Hour = (clockFormat ?: defaultClock).uses24Hour(context), theme = theme, tokenOverrides = colors,
        )

    fun toJson(): JsonObject = buildJsonObject {
        put("id", id)
        put("name", name)
        put("templateID", templateId)
        put("spec", SpecWriter.write(spec))
        put("fieldValues", JsonObject(fieldValues.mapValues { SpecWriter.ltext(it.value) }))
        theme?.let { put("theme", it.name.lowercase()) }
        put("colors", JsonObject(colors.mapValues { JsonPrimitive(it.value) }))
        imageFile?.let { put("imageFile", it) }
        clockFormat?.let { put("clockFormat", it.name.lowercase()) }
        put("created", created)
        put("updated", updated)
    }

    companion object {
        const val MAX_NAME_LENGTH = 60
        val editableColors = listOf("accent", "bg", "fg", "muted", "outer")

        fun new(template: WidgetSpec, language: String) = SavedDesign(name = template.name.resolved(language), templateId = template.id, spec = template)

        fun fromJson(o: JsonObject): SavedDesign {
            val fields = (o["fieldValues"] as? JsonObject)?.mapNotNull { (key, value) ->
                when (value) {
                    is JsonPrimitive -> key to LText.Plain(value.content)
                    is JsonObject -> key to LText.Localized(value["en"]?.jsonPrimitive?.content ?: "", value["ar"]?.jsonPrimitive?.content ?: "")
                    else -> null
                }
            }?.toMap() ?: emptyMap()
            return SavedDesign(
                id = o["id"]!!.jsonPrimitive.content,
                name = o["name"]?.jsonPrimitive?.content ?: "",
                templateId = o["templateID"]?.jsonPrimitive?.content ?: "",
                spec = SpecParser.spec(o["spec"]!!.jsonObject),
                fieldValues = fields,
                theme = when (o["theme"]?.jsonPrimitive?.content) { "light" -> Theme.LIGHT; "dark" -> Theme.DARK; else -> null },
                colors = (o["colors"] as? JsonObject)?.mapValues { it.value.jsonPrimitive.content } ?: emptyMap(),
                imageFile = o["imageFile"]?.jsonPrimitive?.content,
                clockFormat = ClockFormat.of(o["clockFormat"]?.jsonPrimitive?.content),
                created = o["created"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
                updated = o["updated"]?.jsonPrimitive?.content?.toLongOrNull() ?: 0,
            )
        }
    }
}

/**
 * The only storage for designs and photos (SharedStore.swift): JSON files and PNGs in the app's
 * private files folder. Android has no App Group problem: the widget reads the same files.
 */
class DesignStore private constructor(private val root: File) {
    private val json = Json { prettyPrint = false }
    private val designsDir = File(root, "designs").apply { mkdirs() }
    private val imagesDir = File(root, "images").apply { mkdirs() }
    private val state = MutableStateFlow(load())

    /** Newest first. */
    val designs: StateFlow<List<SavedDesign>> = state

    fun design(id: String): SavedDesign? = state.value.firstOrNull { it.id == id }

    private fun load(): List<SavedDesign> = designsDir.listFiles { f -> f.extension == "json" }.orEmpty()
        .mapNotNull { runCatching { SavedDesign.fromJson(json.parseToJsonElement(it.readText()).jsonObject) }.getOrNull() }
        .sortedByDescending { it.updated }

    /** Saves the design (and a new processed photo), stamping `updated`. Returns the stored design. */
    fun save(design: SavedDesign, newPhoto: Bitmap? = null): SavedDesign {
        var stored = design.copy(updated = System.currentTimeMillis())
        if (newPhoto != null) {
            val file = "${design.id}.png"
            File(imagesDir, file).outputStream().use { newPhoto.compress(Bitmap.CompressFormat.PNG, 100, it) }
            stored = stored.copy(imageFile = file)
        }
        File(designsDir, "${stored.id}.json").writeText(json.encodeToString(JsonObject.serializer(), stored.toJson()))
        state.value = load()
        return stored
    }

    /** The bytes of a design's photo, kept while a delete can still be undone. */
    fun imageBytes(design: SavedDesign): ByteArray? = design.imageFile?.let { File(imagesDir, it) }?.takeIf { it.exists() }?.readBytes()

    /** Puts a deleted design back, with its photo (Undo, ADR-028). */
    fun restore(design: SavedDesign, image: ByteArray?) {
        val file = design.imageFile
        if (file != null && image != null) File(imagesDir, file).writeBytes(image)
        save(design)
    }

    fun delete(id: String) {
        design(id)?.imageFile?.let { File(imagesDir, it).delete() }
        File(designsDir, "$id.json").delete()
        state.value = load()
    }

    fun duplicate(design: SavedDesign, copySuffix: String): SavedDesign {
        val id = UUID.randomUUID().toString()
        val image = design.imageFile?.let { old ->
            val file = "$id.png"
            runCatching { File(imagesDir, old).copyTo(File(imagesDir, file), overwrite = true) }.getOrNull()?.let { file }
        }
        val now = System.currentTimeMillis()
        return save(design.copy(id = id, name = (design.name + copySuffix).take(SavedDesign.MAX_NAME_LENGTH), imageFile = image, created = now, updated = now))
    }

    fun image(design: SavedDesign): Bitmap? = design.imageFile?.let { BitmapFactory.decodeFile(File(imagesDir, it).path) }

    companion object {
        @Volatile private var shared: DesignStore? = null
        fun get(context: Context): DesignStore = shared ?: synchronized(this) {
            shared ?: DesignStore(context.applicationContext.filesDir).also { shared = it }
        }

        /** For tests: a store in any folder. */
        fun at(folder: File) = DesignStore(folder)
    }
}

/** Rules for what the editor may save (DesignEditing.swift). Empty list = saveable. */
object DesignEditing {
    const val MAX_TEXT_LENGTH = 200

    fun issues(design: SavedDesign): List<String> {
        val issues = mutableListOf<String>()
        val name = design.name.trim()
        if (name.isEmpty()) issues += "name: a name is required"
        if (name.length > SavedDesign.MAX_NAME_LENGTH) issues += "name: at most ${SavedDesign.MAX_NAME_LENGTH} characters"
        for ((token, hex) in design.colors) {
            if (token !in SavedDesign.editableColors) issues += "colors.$token: not an editable color"
            if (com.khaled.widgetstudio.render.Drawing.parseHex(hex) == null) issues += "colors.$token: color must be #RRGGBB"
        }
        for ((key, value) in design.fieldValues) {
            val field = design.spec.field(key)
            if (field == null) {
                issues += "fields.$key: the template has no field \"$key\""
                continue
            }
            for (text in value.allValues) issues += fieldIssues(text, field.type).map { "fields.$key: $it" }
        }
        issues += SpecValidator(ai = false).validate(design.spec).map { "spec.$it" }
        return issues
    }

    fun fieldIssues(value: String, type: String): List<String> {
        if (value.length > MAX_TEXT_LENGTH) return listOf("at most $MAX_TEXT_LENGTH characters")
        return when (type) {
            "text", "city" -> if (containsUrl(value)) listOf("links are only allowed in link fields") else emptyList()
            "shortcut" -> if (value.contains("://")) listOf("enter the shortcut's name, not a link") else emptyList()
            "url" -> if (value.isEmpty() || value.startsWith("https://") || value.startsWith("http://")) emptyList() else listOf("must be a web link starting with https://")
            "number" -> if (value.toDoubleOrNull() == null) listOf("must be a number") else emptyList()
            "timezone" -> if (value.isEmpty() || runCatching { ZoneId.of(value) }.isSuccess) emptyList() else listOf("unknown time zone")
            "color" -> if (com.khaled.widgetstudio.render.Drawing.parseHex(value) == null) listOf("color must be #RRGGBB") else emptyList()
            else -> emptyList()
        }
    }

    fun containsUrl(value: String): Boolean {
        val lower = value.lowercase()
        return lower.contains("://") || lower.startsWith("www.") || lower.contains(" www.")
    }
}

/**
 * The photo for an image layer (ImageProcessing.swift): cropped to fill (or fitted) at the layer's
 * pixel size (3× the frame, longest side at most 1024 px), then mono or halftone once, here.
 */
object ImageProcessing {
    private const val SCALE = 3.0
    private const val MAX_SIDE = 1024

    fun prepare(image: Bitmap, frame: Frame, layer: LayerContent.Image): Bitmap {
        var width = max(1.0, frame.w * SCALE)
        var height = max(1.0, frame.h * SCALE)
        val longest = max(width, height)
        if (longest > MAX_SIDE) {
            width *= MAX_SIDE / longest
            height *= MAX_SIDE / longest
        }
        val sized = if (layer.fit == "fit") fit(image, width.roundToInt(), height.roundToInt()) else fill(image, width.roundToInt(), height.roundToInt())
        return when (layer.filter) {
            "mono" -> mono(sized)
            "halftone" -> halftone(sized)
            else -> sized
        }
    }

    fun fill(image: Bitmap, width: Int, height: Int): Bitmap {
        val ratio = max(width.toFloat() / image.width, height.toFloat() / image.height)
        val w = image.width * ratio
        val h = image.height * ratio
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        Canvas(out).drawBitmap(image, null, RectF((width - w) / 2, (height - h) / 2, (width + w) / 2, (height + h) / 2), Paint(Paint.FILTER_BITMAP_FLAG))
        return out
    }

    fun fit(image: Bitmap, width: Int, height: Int): Bitmap {
        val ratio = min(min(width.toFloat() / image.width, height.toFloat() / image.height), 1f)
        return Bitmap.createScaledBitmap(image, max(1, (image.width * ratio).roundToInt()), max(1, (image.height * ratio).roundToInt()), true)
    }

    private fun luminance(image: Bitmap): DoubleArray {
        val pixels = IntArray(image.width * image.height)
        image.getPixels(pixels, 0, image.width, 0, 0, image.width, image.height)
        return DoubleArray(pixels.size) { (0.2126 * Color.red(pixels[it]) + 0.7152 * Color.green(pixels[it]) + 0.0722 * Color.blue(pixels[it])) / 255 }
    }

    fun mono(image: Bitmap): Bitmap {
        val gray = luminance(image)
        val pixels = IntArray(gray.size) { val v = (gray[it] * 255).roundToInt().coerceIn(0, 255); Color.rgb(v, v, v) }
        return Bitmap.createBitmap(pixels, image.width, image.height, Bitmap.Config.ARGB_8888)
    }

    /** Black dots on white, one per cell, area following the cell's darkness. */
    fun halftone(image: Bitmap, cellsAcross: Int = 44): Bitmap {
        val gray = luminance(image)
        val width = image.width
        val height = image.height
        val cell = max(3, width / cellsAcross)
        val out = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.BLACK }
        for (top in 0 until height step cell) for (left in 0 until width step cell) {
            var sum = 0.0
            var count = 0
            for (y in top until min(top + cell, height)) for (x in left until min(left + cell, width)) {
                sum += gray[y * width + x]
                count++
            }
            val darkness = 1 - sum / max(count, 1)
            if (darkness <= 0.04) continue
            val radius = cell / 2f * min(1.15, sqrt(darkness * 1.3)).toFloat()
            canvas.drawCircle(left + cell / 2f, top + cell / 2f, radius, paint)
        }
        return out
    }
}

package com.khaled.widgetstudio.spec

import android.content.res.AssetManager
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** One live value or tap action of `spec/capabilities.json`, the single source of truth (ADR-027), same as Capabilities.swift. */
data class Capability(
    val id: String,
    val group: String,
    val type: String?,
    val title: LText,
    val description: String,
    val example: String?,
    val keywords: List<String>,
    val icons: List<String>,
    val glyphs: List<String>,
    val layers: List<String>,
    val parametric: Boolean,
    val ai: Boolean,
    val arg: String?,
    val state: String?,
    val hint: LText?,
    val panel: String?,
    val supportIos: String,
    val supportAndroid: String,
    val permissionIos: String?,
    val permissionAndroid: String?,
    val noteAndroid: String?,
) {
    val prefix: String get() = id.substringBefore('.')

    /** A share 0…1 that reads as a whole percent in text: what a level, ring or dots can show. */
    val isShare: Boolean get() = type == "number" && "ring" in layers

    /** The field type an action's `arg` must point to; null when it needs no field. */
    val argFieldType: String? get() = arg?.takeIf { it == "url" || it == "shortcut" || it == "text" }

    /** The hint for a tap Android doesn't allow: the catalog's, or a generic one. */
    fun hintText(language: String): String {
        hint?.let { return it.resolved(language) }
        val name = title.resolved(language)
        return if (language.startsWith("ar")) "لا يسمح Android بـ«$name» من الويدجت." else "Android doesn't allow $name from a widget."
    }
}

data class Named(val id: String, val title: LText)

/** One built-in state set of the catalog (ADR-028). */
data class StateSet(
    val id: String, val title: LText, val description: String, val box: List<Double>, val value: String?, val topic: String?,
    val needs: List<String>, val keywords: List<String>, val glyphs: List<String>, val variantsJson: String,
) {
    val variants: List<StateVariant> by lazy { StateSets.parse(variantsJson) }
}

object StateSets {
    private val cache = java.util.concurrent.ConcurrentHashMap<String, List<StateVariant>>()

    fun parse(json: String): List<StateVariant> = Json.parseToJsonElement(json).jsonArray.map { SpecParser.variant(it.jsonObject) }

    /** A set's variants with its placeholders filled in; cached, like StateSets.swift. */
    fun variants(id: String, value: String, color: String, accent: String, dim: String): List<StateVariant> = cache.getOrPut(listOf(id, value, color, accent, dim).joinToString("|")) {
        val set = Capabilities.stateSet(id) ?: return emptyList()
        parse(
            set.variantsJson.replace("\"\$color\"", "\"$color\"").replace("\"\$accent\"", "\"$accent\"").replace("\"\$dim\"", "\"$dim\"")
                .replace("\$value", value),
        )
    }
}

/** What kind of weather a condition icon shows (`{{weather.kind}}`), so conditions never compare translated text. */
object WeatherKind {
    fun of(symbol: String): String = when (symbol) {
        "sun.max.fill", "moon.fill", "moon.stars.fill" -> "clear"
        "cloud.sun.fill", "cloud.moon.fill" -> "partlyCloudy"
        "cloud.fog.fill" -> "fog"
        "cloud.drizzle.fill", "cloud.rain.fill", "cloud.heavyrain.fill" -> "rain"
        "cloud.snow.fill" -> "snow"
        "cloud.bolt.rain.fill" -> "storm"
        else -> "cloudy"
    }
}

object Capabilities {
    private class Catalog(val bindings: List<Capability>, val actions: List<Capability>, val groups: List<Named>, val permissions: List<Named>, val stateSets: List<StateSet>)

    @Volatile private var catalog = Catalog(emptyList(), emptyList(), emptyList(), emptyList(), emptyList())

    val bindings: List<Capability> get() = catalog.bindings
    val actions: List<Capability> get() = catalog.actions
    val groups: List<Named> get() = catalog.groups
    val permissions: List<Named> get() = catalog.permissions

    /** Built-in state sets (ADR-028): the AI, the post-pass and the editor reuse them. */
    val stateSets: List<StateSet> get() = catalog.stateSets

    fun stateSet(id: String): StateSet? = catalog.stateSets.firstOrNull { it.id == id }

    /** Reads the catalog once (the Application, or a test's setup). */
    fun load(assets: AssetManager) {
        if (catalog.bindings.isEmpty()) install(assets.open("spec/capabilities.json").bufferedReader().readText())
    }

    fun install(text: String) {
        val root = Json.parseToJsonElement(text).jsonObject
        fun named(key: String) = (root[key] as? JsonArray)?.map { item ->
            val o = item.jsonObject
            Named(o.str("id") ?: "", o.ltext("title") ?: LText.Plain(""))
        } ?: emptyList()
        fun capabilities(key: String) = (root[key] as? JsonArray)?.map { capability(it.jsonObject) } ?: emptyList()
        val sets = (root["stateSets"] as? JsonArray)?.map { item ->
            val o = item.jsonObject
            StateSet(
                o.str("id") ?: "", o.ltext("title") ?: LText.Plain(""), o.str("description") ?: "",
                (o["box"] as? JsonArray)?.mapNotNull { it.jsonPrimitive.content.toDoubleOrNull() } ?: emptyList(),
                o.str("value"), o.str("topic"), o.list("needs"), o.list("keywords"), o.list("glyphs"), o["variants"].toString(),
            )
        } ?: emptyList()
        catalog = Catalog(capabilities("bindings"), capabilities("actions"), named("groups"), named("permissions"), sets)
    }

    private fun capability(o: JsonObject) = Capability(
        id = o.str("id") ?: "",
        group = o.str("group") ?: "",
        type = o.str("type"),
        title = o.ltext("title") ?: LText.Plain(""),
        description = o.str("description") ?: "",
        example = o.str("example"),
        keywords = o.list("keywords"),
        icons = o.list("icons"),
        glyphs = o.list("glyphs"),
        layers = o.list("layers"),
        parametric = o.bool("parametric") ?: false,
        ai = o.bool("ai") ?: true,
        arg = o.str("arg"),
        state = o.str("state"),
        hint = o.ltext("hint"),
        panel = o.str("panel"),
        supportIos = o.platform("support", "ios") ?: "native",
        supportAndroid = o.platform("support", "android") ?: "native",
        permissionIos = o.platform("permission", "ios"),
        permissionAndroid = o.platform("permission", "android"),
        noteAndroid = o.platform("note", "android"),
    )

    private fun JsonObject.str(key: String) = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
    private fun JsonObject.bool(key: String) = (this[key] as? JsonPrimitive)?.booleanOrNull
    private fun JsonObject.list(key: String) = (this[key] as? JsonArray)?.map { it.jsonPrimitive.content } ?: emptyList()
    private fun JsonObject.ltext(key: String): LText? {
        val o = this[key] as? JsonObject ?: return null
        val en = o.str("en") ?: return null
        val ar = o.str("ar") ?: return null
        return LText.Localized(en, ar)
    }

    /** One string for both platforms, or `{ios, android}`. */
    private fun JsonObject.platform(key: String, platform: String): String? = when (val value: JsonElement? = this[key]) {
        is JsonPrimitive -> value.takeIf { it.isString }?.content
        is JsonObject -> value.str(platform)
        else -> null
    }

    fun binding(id: String): Capability? = bindings.firstOrNull { it.id == id.trim() }
    fun action(id: String): Capability? = actions.firstOrNull { it.id == id }

    /** Permissions a spec needs on Android, in catalog order. */
    fun permissions(spec: WidgetSpec): List<Named> {
        val ids = mutableSetOf<String>()
        for (name in BindingNames.names(spec)) binding(name)?.permissionAndroid?.let { ids += it }
        for (layer in spec.layers.flatMap { it.flattened }) {
            (layer.content as? LayerContent.Button)?.let { button -> action(button.action)?.permissionAndroid?.let { ids += it } }
        }
        return permissions.filter { it.id in ids }
    }
}

/** Every binding name in a spec's layers (DataRequirements.bindingNames in Swift). */
object BindingNames {
    fun names(spec: WidgetSpec): List<String> = spec.layers.flatMap { it.flattened }.flatMap { layer ->
        val texts = when (val c = layer.content) {
            is LayerContent.Text -> c.value.allValues + listOfNotNull(c.liveTarget)
            is LayerContent.Icon -> listOf(c.symbol)
            is LayerContent.Ring -> listOf(c.progress)
            is LayerContent.ProgressBar -> listOf(c.progress)
            is LayerContent.DotGrid -> listOf(c.values)
            is LayerContent.DotBars -> listOf(c.values) + (c.labels?.allValues ?: emptyList())
            is LayerContent.ListL -> c.items.flatMap { it.title.allValues + (it.detail?.allValues ?: emptyList()) + listOfNotNull(it.done) }
            is LayerContent.Button -> listOfNotNull(c.arg)
            is LayerContent.AnalogClock -> listOfNotNull(c.timezone)
            is LayerContent.Image -> listOf(c.source)
            is LayerContent.States -> c.expanded.mapNotNull { it.condition } + listOfNotNull(c.value)
            else -> emptyList()
        } + listOfNotNull(layer.condition, layer.rotation)
        texts.flatMap { text -> Bindings.tokenize(text).filterIsInstance<Bindings.Token.Binding>().map { it.name.trim() } }
    }
}

/** How much of a design is wired (WiringScore.swift). */
object WiringScore {
    fun ids(spec: WidgetSpec): Set<String> =
        BindingNames.names(spec).toSet() + spec.layers.flatMap { it.flattened }.mapNotNull {
            (it.content as? LayerContent.Button)?.action ?: if (it.content is LayerContent.AnalogClock) "clock" else null
        }

    fun hits(spec: WidgetSpec, expected: List<String>): List<String> {
        val present = ids(spec)
        return expected.filter { entry -> entry.split("|").any { it in present } }
    }
}

package com.khaled.widgetstudio.spec

import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.time.DayOfWeek
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters
import java.time.temporal.WeekFields
import java.util.Locale

/** Data the bindings read (brief §4.5); every part optional, a missing value renders "--". */
data class DataSnapshot(
    val weather: Weather? = null,
    val stepsToday: Double? = null,
    val stepsStreak: Double? = null,
    val stepsMonth: Double? = null,
    val stepsMonthGrid: List<Double>? = null,
    val sleepLastNight: LText? = null,
    val sleepWeek: List<Double>? = null,
    val counter: Double? = null,
    val dhikr: String? = null,
    val stopwatchStart: Instant? = null,
    val focusToday: LText? = null,
    val focusWeek: List<Double>? = null,
    val prayer: Prayer? = null,
    val qiblaBearing: Double? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val altitude: Double? = null,
    val batteryLevel: Double? = null,
    /** The place name of the last location fix (`location.city`). */
    val place: LText? = null,
    /** What is playing, with its position (ADR-027). */
    val media: MediaPlayback? = null,
    val timer: TimerValues? = null,
    /** Every other catalog binding by id: a provider fills this, so a new capability needs no field here and no case in the resolver. */
    val live: Map<String, BindingResolver.Value> = emptyMap(),
) {
    data class DayForecast(val date: LocalDate, val symbol: String, val high: Double, val low: Double)
    /** One hour of the forecast (ADR-029): chance of rain in percent, rain in mm. */
    data class HourForecast(val time: Instant, val symbol: String, val temperature: Double, val rainChance: Double, val rain: Double)
    data class Weather(
        val temperature: Double, val high: Double, val low: Double, val condition: LText, val symbol: String,
        val city: LText, val forecast: List<DayForecast>,
        val hourly: List<HourForecast> = emptyList(), val uv: Double? = null, val aqi: Double? = null,
    )
    data class Prayer(val times: Map<String, Instant>, val nextName: LText, val nextKey: String, val nextTime: Instant)

    companion object {
        /** The same plausible values as DataSnapshot.sample on iOS (Cairo; weeks start on Saturday, as in Egypt and the iOS snapshots). */
        fun sample(now: Instant, zone: ZoneId, firstDay: DayOfWeek = DayOfWeek.SATURDAY): DataSnapshot {
            val today = now.atZone(zone).toLocalDate()
            val symbols = listOf("sun.max.fill", "cloud.sun.fill", "cloud.fill", "sun.max.fill", "cloud.rain.fill", "sun.max.fill", "cloud.sun.fill")
            val weather = Weather(
                30.0, 33.0, 21.0, LText.Localized("Partly cloudy", "غائم جزئيًا"), "cloud.sun.fill", LText.Localized("Cairo", "القاهرة"),
                (0 until 7).map { DayForecast(today.plusDays(it.toLong()), symbols[it], (33 - it % 3).toDouble(), (21 - it % 2).toDouble()) },
            )
            val day = today.dayOfMonth
            val perDay = (1..31).map { d -> if (d > day) 0.0 else if (d == day) 2.0 else listOf(0.25, 1.0, 0.6, 0.9, 0.4, 1.0, 0.75)[(d * 5) % 7] }
            fun at(hour: Int, minute: Int): Instant = today.atTime(hour, minute).atZone(zone).toInstant()
            val times = linkedMapOf("fajr" to at(4, 32), "dhuhr" to at(11, 42), "asr" to at(14, 58), "maghrib" to at(17, 21), "isha" to at(18, 38))
            val names = listOf(
                "fajr" to LText.Localized("Fajr", "الفجر"), "dhuhr" to LText.Localized("Dhuhr", "الظهر"), "asr" to LText.Localized("Asr", "العصر"),
                "maghrib" to LText.Localized("Maghrib", "المغرب"), "isha" to LText.Localized("Isha", "العشاء"),
            )
            val next = names.firstOrNull { (times[it.first] ?: now) > now } ?: names[0]
            val nextTime = times.getValue(next.first).let { if (it > now) it else it.plus(1, ChronoUnit.DAYS) }
            return DataSnapshot(
                weather = weather, stepsToday = 5543.0, stepsStreak = 3.0, stepsMonth = 128430.0,
                stepsMonthGrid = MonthGrid.levels(perDay, today, firstDay),
                sleepLastNight = LText.Localized("7h 20m", "7س 20د"), sleepWeek = listOf(0.7, 0.85, 0.6, 0.9, 0.75, 0.5, 0.8),
                counter = 33.0, dhikr = "سبحان الله", stopwatchStart = now.minusSeconds(754),
                focusToday = LText.Localized("6h 20m", "6س 20د"), focusWeek = listOf(0.4, 0.8, 0.6, 1.0, 0.3, 0.0, 0.5),
                prayer = Prayer(times, next.second, next.first, nextTime), qiblaBearing = 136.0, latitude = 30.04, longitude = 31.24,
                altitude = 23.0, batteryLevel = 0.87, live = sampleLive(today, zone),
            )
        }

        /** The catalog's examples for bindings without a field above: previews show every capability. */
        fun sampleLive(today: LocalDate, zone: ZoneId): Map<String, BindingResolver.Value> {
            val live = mutableMapOf<String, BindingResolver.Value>()
            for (binding in Capabilities.bindings) {
                val example = binding.example?.takeIf { it.isNotEmpty() } ?: continue
                if (binding.parametric) continue
                live[binding.id] = when (binding.type) {
                    "number" -> {
                        val value = example.replace(",", "").toDoubleOrNull() ?: 0.0
                        val share = example.startsWith("0.") || "ring" in binding.layers
                        BindingResolver.Value.Number(value, if (share) Math.round(value * 100).toString() else example)
                    }
                    "date" -> {
                        val parts = example.split(":").mapNotNull { it.toIntOrNull() }
                        BindingResolver.Value.Date((if (parts.size == 2) today.atTime(parts[0], parts[1]) else today.atStartOfDay()).atZone(zone).toInstant())
                    }
                    "levels", "series" -> BindingResolver.Value.Levels(example.split(",").mapNotNull { it.trim().toDoubleOrNull() })
                    else -> BindingResolver.Value.Text(example)
                }
            }
            return live
        }
    }
}

/** What is playing and where (Activity.swift). */
data class MediaPlayback(val elapsed: Double, val duration: Double, val playing: Boolean, val at: Instant) {
    fun position(date: Instant): Double {
        val moved = if (playing) maxOf(java.time.Duration.between(at, date).toMillis() / 1000.0, 0.0) else 0.0
        return if (duration > 0) minOf(elapsed + moved, duration) else elapsed + moved
    }

    companion object {
        /** "4:23" or "1:02:03". */
        fun clock(seconds: Double): String {
            val total = Math.round(maxOf(seconds, 0.0)).toInt()
            val hours = total / 3600
            return if (hours > 0) "%d:%02d:%02d".format(Locale.US, hours, total % 3600 / 60, total % 60) else "%d:%02d".format(Locale.US, total / 60, total % 60)
        }
    }
}

/** The timer as the resolver reads it; the state itself is `TimerState` in LiveData.kt. */
interface TimerValues {
    val end: Instant?
    fun isRunning(date: Instant): Boolean
    fun remaining(date: Instant): Double
    fun progress(date: Instant): Double
}

/** Per-day values laid out as a month for dotGrid (MonthGrid.swift): -1 pads before day 1 and after the last day. */
object MonthGrid {
    const val HIGHLIGHT = 2.0

    fun levels(perDay: List<Double>, date: LocalDate, firstDay: DayOfWeek): List<Double> {
        val first = date.withDayOfMonth(1)
        val leading = (first.dayOfWeek.value - firstDay.value + 7) % 7
        val cells = MutableList(leading) { -1.0 }
        for (i in 0 until date.lengthOfMonth()) cells += if (i < perDay.size) perDay[i].coerceIn(0.0, HIGHLIGHT) else 0.0
        repeat((7 - cells.size % 7) % 7) { cells += -1.0 }
        return cells
    }
}

/** Everything one render needs (RenderContext.swift). */
data class RenderContext(
    val now: Instant,
    val language: String = "ar",
    val zone: ZoneId = ZoneId.systemDefault(),
    val fieldValues: Map<String, LText> = emptyMap(),
    val data: DataSnapshot = DataSnapshot(),
    val userImage: android.graphics.Bitmap? = null,
    /** The album art of what is playing (`{{media.artwork}}`). */
    val mediaArtwork: android.graphics.Bitmap? = null,
    /** Other image bindings (ADR-029): `media.appIcon`, `app.<package>.icon`. */
    val images: Map<String, android.graphics.Bitmap> = emptyMap(),
    /** Live texts (relative, timer) as fixed text measured from [now]: snapshots and previews. */
    val freezesLiveText: Boolean = true,
    /** 24-hour (true) or 12-hour (false); null keeps "HH". */
    val uses24Hour: Boolean? = null,
    val theme: Theme? = null,
    val tokenOverrides: Map<String, String> = emptyMap(),
    /** Tinted/Clear home screens: Android has no accented mode, kept for parity with iOS. */
    val accented: Boolean = false,
    /** Which variant a state layer shows, by its key: the editor's preview and the renders of every state (ADR-028). */
    val forcedStates: Map<String, String> = emptyMap(),
    /** Binding values that replace the real ones, as a state's `sample` writes them. */
    val overrides: Map<String, String> = emptyMap(),
) {
    val isArabic get() = language.startsWith("ar")
    /** Words in the render language, digits Latin (ar-EG with Latin numbers). */
    val locale: Locale get() = if (isArabic) Locale.forLanguageTag("ar-EG-u-nu-latn") else Locale.US
    val timePattern get() = if (uses24Hour == false) "h:mm" else "HH:mm"
}

/** `{{name}}` tokens (Bindings.swift). */
object Bindings {
    sealed class Token {
        data class Literal(val text: String) : Token()
        data class Binding(val name: String) : Token()
    }

    fun tokenize(text: String): List<Token> {
        val tokens = mutableListOf<Token>()
        var rest = text
        while (true) {
            val open = rest.indexOf("{{")
            if (open < 0) break
            val close = rest.indexOf("}}", open + 2)
            if (close < 0) break
            if (open > 0) tokens += Token.Literal(rest.substring(0, open))
            tokens += Token.Binding(rest.substring(open + 2, close))
            rest = rest.substring(close + 2)
        }
        if (rest.isNotEmpty()) tokens += Token.Literal(rest)
        return tokens
    }

    fun soleBinding(text: String): String? = tokenize(text.trim()).singleOrNull()?.let { (it as? Token.Binding)?.name }
}

/**
 * One condition of a `when` (ADR-011, ADR-028): `{{b}}`, `!{{b}}`, `{{b}} == value`, `{{b}} != value`,
 * `{{b}} >= 0.9` (also `<=`, `>`, `<`), `{{b}} in 0.5..0.89` or `{{b}} in rain,storm`.
 */
data class SpecCondition(
    val binding: String, val negated: Boolean, val equals: String?, val notEquals: String? = null, val compare: Pair<String, Double>? = null,
    val range: Pair<Double, Double>? = null, val anyOf: List<String>? = null,
) {
    companion object {
        fun parse(text: String): SpecCondition? {
            var rest = text.trim()
            var negated = false
            if (rest.startsWith("!")) {
                negated = true
                rest = rest.drop(1).trim()
            }
            if (!rest.startsWith("{{")) return null
            val close = rest.indexOf("}}").takeIf { it > 0 } ?: return null
            val binding = rest.substring(2, close).trim()
            val tail = rest.substring(close + 2).trim()
            if (binding.isEmpty()) return null
            if (tail.isEmpty()) return SpecCondition(binding, negated, null)
            if (negated) return null
            if (tail.startsWith("==") || tail.startsWith("!=")) {
                val value = tail.drop(2).trim()
                if (value.isEmpty()) return null
                return if (tail.startsWith("==")) SpecCondition(binding, false, value) else SpecCondition(binding, false, null, notEquals = value)
            }
            listOf(">=", "<=", ">", "<").firstOrNull { tail.startsWith(it) }?.let { symbol ->
                val number = tail.drop(symbol.length).trim().toDoubleOrNull() ?: return null
                return SpecCondition(binding, false, null, compare = symbol to number)
            }
            if (tail.startsWith("in ")) {
                val list = tail.drop(3).trim()
                val bounds = list.split("..").map { it.trim().toDoubleOrNull() }
                val low = bounds.getOrNull(0)
                val high = bounds.getOrNull(1)
                if (bounds.size == 2 && low != null && high != null) return SpecCondition(binding, false, null, range = low to high)
                val items = list.split(",").map { it.trim() }.filter { it.isNotEmpty() }
                return if (items.isEmpty()) null else SpecCondition(binding, false, null, anyOf = items)
            }
            return null
        }
    }
}

/** A whole `when`: conditions joined by `&&` and `||` (`&&` binds tighter, no parentheses, ADR-028). */
data class SpecExpression(val groups: List<List<SpecCondition>>) {
    val bindings: List<String> get() = groups.flatten().map { it.binding }

    companion object {
        fun parse(text: String): SpecExpression? {
            val groups = text.split("||").map { group ->
                group.split("&&").map { SpecCondition.parse(it) ?: return null }
            }
            return SpecExpression(groups)
        }
    }
}

/** Turns bindings into values for one render (BindingResolver.swift). Digits are always Latin. */
class BindingResolver(val spec: WidgetSpec, val context: RenderContext) {
    sealed class Value {
        data class Text(val text: String) : Value()
        data class Number(val value: Double, val display: String) : Value()
        data class Levels(val levels: List<Double>) : Value()
        data class Date(val instant: Instant) : Value()
    }

    private val zoned: ZonedDateTime = context.now.atZone(context.zone)

    fun render(template: String): String = Bindings.tokenize(template).joinToString("") { token ->
        when (token) {
            is Bindings.Token.Literal -> token.text
            is Bindings.Token.Binding -> value(token.name)?.let(::display) ?: MISSING
        }
    }

    fun display(value: Value): String = when (value) {
        is Value.Text -> value.text
        is Value.Number -> value.display
        is Value.Levels -> value.levels.joinToString(",") { "%.2f".format(Locale.US, it) }
        is Value.Date -> DateTimeFormatter.ofPattern(context.timePattern, Locale.US).format(value.instant.atZone(context.zone))
    }

    fun soleValue(text: String): Value? = Bindings.soleBinding(text)?.let(::value)

    fun number(text: String): Double? = text.trim().toDoubleOrNull() ?: (soleValue(text) as? Value.Number)?.value

    fun levels(text: String): List<Double> {
        (soleValue(text) as? Value.Levels)?.let { return it.levels }
        val parts = text.split(",").map { it.trim().toDoubleOrNull() }
        if (parts.isNotEmpty() && parts.size <= 31 && parts.all { it != null && it in 0.0..1.0 }) return parts.filterNotNull()
        // Digits row by row: 0/1, or levels 0…9 when any digit is above 1 (ADR-029).
        val digits = text.filter { it != ' ' }
        if (digits.isNotEmpty() && digits.length <= 1600 && digits.all { it in '0'..'9' }) {
            val binary = digits.all { it == '0' || it == '1' }
            return digits.map { (it - '0').toDouble() / if (binary) 1.0 else 9.0 }
        }
        return emptyList()
    }

    /** `dotGrid` values: levels, or a number 0…1 that lights that share of the cells. */
    fun gridLevels(text: String, cells: Int): List<Double> {
        (soleValue(text) as? Value.Number)?.let { share ->
            val lit = Math.round(share.value.coerceIn(0.0, 1.0) * cells).toInt()
            return List(maxOf(cells, 0)) { if (it < lit) 1.0 else 0.0 }
        }
        return levels(text)
    }

    fun date(text: String): Instant? = (soleValue(text) as? Value.Date)?.instant

    fun fieldValue(key: String): String? = (context.fieldValues[key] ?: spec.field(key)?.default)?.resolved(context.language)

    /** Unknown or missing values are falsy, so no comparison can pass on data that isn't there. */
    fun isSatisfied(text: String): Boolean {
        val expression = SpecExpression.parse(text) ?: return true
        return expression.groups.any { group -> group.all(::holds) }
    }

    private fun holds(condition: SpecCondition): Boolean {
        val value = value(condition.binding)
        val shown = value?.let(::display)
        val number = when (value) {
            is Value.Number -> value.value
            is Value.Text -> value.text.toDoubleOrNull()
            else -> null
        }
        return when {
            condition.equals != null -> shown == condition.equals
            condition.notEquals != null -> shown != null && shown != condition.notEquals
            condition.anyOf != null -> shown != null && shown in condition.anyOf
            condition.range != null -> number != null && number >= condition.range.first && number <= condition.range.second
            condition.compare != null -> number != null && when (condition.compare.first) {
                ">=" -> number >= condition.compare.second
                "<=" -> number <= condition.compare.second
                ">" -> number > condition.compare.second
                else -> number < condition.compare.second
            }
            condition.negated -> !isTruthy(value)
            else -> isTruthy(value)
        }
    }

    /** The variant to draw now: the one the render forces, else the first whose `when` holds. */
    fun variant(states: LayerContent.States): StateVariant? {
        val variants = states.expanded
        context.forcedStates[states.key]?.let { forced -> variants.firstOrNull { it.id == forced }?.let { return it } }
        return variants.firstOrNull { variant -> variant.condition?.let(::isSatisfied) ?: true }
    }

    /** The overrides that put a widget in [variant]; a set's `$value` key arrives as the layer's own binding. */
    fun overrides(variant: StateVariant): Map<String, String> = (variant.sample ?: emptyMap()).mapKeys { (key, _) -> (Bindings.soleBinding(key) ?: key).trim() }

    /** A value forced by `RenderContext.overrides`, typed by the catalog. */
    private fun overridden(name: String): Value? {
        val raw = context.overrides[name] ?: return null
        val capability = Capabilities.binding(name)
        val number = raw.toDoubleOrNull()
        if (capability?.type != "number" || number == null) return Value.Text(raw)
        return Value.Number(number, if (capability.isShare) Math.round(number * 100).toString() else raw)
    }

    private fun isTruthy(value: Value?): Boolean = when (value) {
        is Value.Text -> value.text.isNotEmpty() && value.text != "0"
        is Value.Number -> value.value != 0.0
        is Value.Levels -> value.levels.isNotEmpty()
        is Value.Date -> true
        null -> false
    }

    fun value(raw: String): Value? {
        val name = raw.trim()
        if (context.overrides.isNotEmpty()) overridden(name)?.let { return it }
        when {
            name.startsWith("field.") -> {
                val key = name.removePrefix("field.")
                val field = spec.field(key) ?: return null
                val value = fieldValue(key) ?: return null
                return when (field.type) {
                    "date" -> parseDate(value)?.let { Value.Date(it) }
                    "number" -> value.toDoubleOrNull()?.let { Value.Number(it, value) }
                    else -> Value.Text(value)
                }
            }
            name.startsWith("days.") -> {
                val target = fieldValue(name.removePrefix("days."))?.let(::parseDate) ?: return null
                val days = ChronoUnit.DAYS.between(zoned.toLocalDate(), target.atZone(context.zone).toLocalDate())
                return number(maxOf(days, 0).toDouble(), 0)
            }
            name.startsWith("stock.") -> {
                val parts = name.split(".")
                if (parts.size != 3) return null
                val ticker = fieldValue(parts[1])?.trim()?.lowercase()?.takeIf { it.isNotEmpty() } ?: return null
                return context.data.live["stock.$ticker.${parts[2]}"] ?: context.data.live["stock.<tickerField>.${parts[2]}"]
            }
            name.startsWith("tz.") && name.endsWith(".time") -> {
                val zone = fieldValue(name.drop(3).dropLast(5))?.let { runCatching { ZoneId.of(it) }.getOrNull() } ?: return null
                return Value.Text(DateTimeFormatter.ofPattern(context.timePattern, Locale.US).format(context.now.atZone(zone)))
            }
        }
        return builtin(name)
    }

    fun parseDate(value: String): Instant? {
        runCatching { return Instant.parse(value) }
        runCatching { return ZonedDateTime.parse(value).toInstant() }
        for (pattern in listOf("yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm")) {
            runCatching { return LocalDateTime.parse(value, DateTimeFormatter.ofPattern(pattern)).atZone(context.zone).toInstant() }
        }
        runCatching { return LocalDate.parse(value).atStartOfDay(context.zone).toInstant() }
        return null
    }

    /** The hours from the current one on. */
    private fun upcoming(hours: List<DataSnapshot.HourForecast>): List<DataSnapshot.HourForecast> =
        hours.filter { it.time.plusSeconds(3600) > context.now }

    /** `hourly.N.time|symbol|temp` and `week.dN.EEE|d|isToday` (ADR-029). */
    private fun indexed(name: String): Value? {
        val parts = name.split(".")
        if (parts.size != 3) return null
        if (parts[0] == "hourly") {
            val n = parts[1].toIntOrNull() ?: return null
            val hours = context.data.weather?.hourly?.let(::upcoming)?.takeIf { it.isNotEmpty() } ?: return context.data.live[name]
            // Hour 1 is the next full hour.
            val hour = hours.filter { it.time > context.now }.getOrNull(n - 1) ?: return null
            return when (parts[2]) {
                "time" -> Value.Text(DateTimeFormatter.ofPattern(if (context.uses24Hour == false) "h a" else "HH:mm", context.locale).format(hour.time.atZone(context.zone)))
                "symbol" -> Value.Text(hour.symbol)
                "temp" -> number(hour.temperature, 0)
                else -> null
            }
        }
        if (parts[0] == "week" && parts[1].startsWith("d")) {
            val n = parts[1].drop(1).toIntOrNull()?.takeIf { it in 1..7 } ?: return null
            val first = zoned.toLocalDate().with(TemporalAdjusters.previousOrSame(WeekFields.of(context.locale).firstDayOfWeek))
            val day = first.plusDays((n - 1).toLong())
            return when (parts[2]) {
                "EEE" -> Value.Text(DateTimeFormatter.ofPattern("EEE", context.locale).format(day))
                "d" -> Value.Text(day.dayOfMonth.toString())
                "isToday" -> Value.Text(if (day == zoned.toLocalDate()) "1" else "0")
                else -> null
            }
        }
        return null
    }

    private fun builtin(name: String): Value? {
        val data = context.data
        val language = context.language
        if (name.startsWith("hourly.") || name.startsWith("week.d")) indexed(name)?.let { return it }
        return when (name) {
            "time.h" -> Value.Text(format("h"))
            "time.hh" -> Value.Text(format(if (context.uses24Hour == false) "h" else "HH"))
            "time.mm" -> Value.Text(format("mm"))
            "time.ampm" -> Value.Text(localized("a"))
            "time.ss" -> Value.Text(format("ss"))
            "time.words" -> Value.Text(TimeWords.words(zoned.hour, zoned.minute, context.isArabic))
            "date.EE" -> Value.Text(localized("EEE").let { if (context.isArabic) it else it.take(2) })
            "year.progress" -> progress(ChronoUnit.YEARS)
            "month.progress" -> progress(ChronoUnit.MONTHS)
            "week.progress" -> progress(ChronoUnit.WEEKS)
            "day.progress" -> progress(ChronoUnit.DAYS)
            "year.day" -> number(zoned.dayOfYear.toDouble(), 0)
            "year.daysLeft" -> daysLeft(ChronoUnit.YEARS)
            "month.daysLeft" -> daysLeft(ChronoUnit.MONTHS)
            "week.daysLeft" -> daysLeft(ChronoUnit.WEEKS)
            "time.isDay" -> Value.Text(if (isDay()) "1" else "0")
            "weather.kind" -> data.weather?.let { Value.Text(WeatherKind.of(it.symbol)) }
            "weather.rainChance" -> data.weather?.hourly?.let(::upcoming)?.takeIf { it.isNotEmpty() }?.let { hours -> number(hours.take(3).maxOf { it.rainChance }, 0) }
                ?: data.live[name]
            "weather.rainNext" -> data.weather?.hourly?.let(::upcoming)?.takeIf { it.isNotEmpty() }?.let { Value.Text(TimeWords.rainNext(it, context)) } ?: data.live[name]
            "weather.uv" -> data.weather?.uv?.let { number(it, 0) } ?: data.live[name]
            "weather.aqi" -> data.weather?.aqi?.let { number(it, 0) } ?: data.live[name]
            "hourly.temps" -> data.weather?.hourly?.let(::upcoming)?.takeIf { it.isNotEmpty() }?.let { hours -> Value.Levels(hours.take(24).map { it.temperature }) }
                ?: data.live[name]
            "date.d" -> Value.Text(format("d"))
            "date.EEEE" -> Value.Text(localized("EEEE"))
            "date.MMM" -> Value.Text(localized("MMM"))
            "date.dd" -> Value.Text(format("dd"))
            "date.EEE" -> Value.Text(localized("EEE"))
            "date.MMMM" -> Value.Text(localized("MMMM"))
            "date.M" -> Value.Text(format("M"))
            "date.yyyy" -> Value.Text(format("yyyy"))
            "date.hijri" -> Value.Text(hijri())
            "tz.offset" -> Value.Text(offset())
            "weather.temp" -> data.weather?.let { number(it.temperature, 0) }
            "weather.hi" -> data.weather?.let { number(it.high, 0) }
            "weather.lo" -> data.weather?.let { number(it.low, 0) }
            "weather.cond" -> data.weather?.let { Value.Text(it.condition.resolved(language)) }
            "weather.symbol" -> data.weather?.let { Value.Text(it.symbol) }
            "weather.city" -> data.weather?.let { w -> Value.Text(spec.fields.firstOrNull { it.type == "city" }?.let { fieldValue(it.key) } ?: w.city.resolved(language)) }
            "steps.today" -> data.stepsToday?.let { number(it, 0, grouped = true) }
            "steps.streak" -> data.stepsStreak?.let { number(it, 0) }
            "steps.monthGrid" -> data.stepsMonthGrid?.let { Value.Levels(it) }
            "steps.month" -> data.stepsMonth?.let { number(it, 0, grouped = true) }
            "sleep.lastNight" -> data.sleepLastNight?.let { Value.Text(it.resolved(language)) }
            "sleep.week" -> data.sleepWeek?.let { Value.Levels(it) }
            "counter.value" -> data.counter?.let { number(it, 0) }
            "counter.dhikr" -> data.dhikr?.let { Value.Text(it) }
            "counter.progress" -> {
                val count = data.counter ?: return null
                val target = fieldValue("target")?.toDoubleOrNull()?.takeIf { it > 0 } ?: return null
                number(minOf(count / target, 1.0), 2)
            }
            "stopwatch.running" -> Value.Text(if (data.stopwatchStart == null) "0" else "1")
            "stopwatch.start" -> data.stopwatchStart?.let { Value.Date(it) }
            "focus.today" -> data.focusToday?.let { Value.Text(it.resolved(language)) }
            "focus.week" -> data.focusWeek?.let { Value.Levels(it) }
            "prayer.next.name" -> data.prayer?.let { Value.Text(it.nextName.resolved(language)) }
            "prayer.next.time" -> data.prayer?.let { Value.Date(it.nextTime) }
            "prayer.next.key" -> data.prayer?.let { Value.Text(it.nextKey) }
            "qibla.bearing" -> data.qiblaBearing?.let { number(it, 0) }
            "location.city" -> data.place?.let { Value.Text(it.resolved(language)) } ?: data.live[name]
            "media.playing", "media.symbol", "media.elapsed", "media.duration", "media.remaining", "media.progress" -> data.media?.let { media(name, it) } ?: data.live[name]
            "timer.running", "timer.remaining", "timer.progress", "timer.end" -> data.timer?.let { timer(name, it) } ?: data.live[name]
            "location.lat" -> data.latitude?.let { number(it, 2) }
            "location.lon" -> data.longitude?.let { number(it, 2) }
            "location.alt" -> data.altitude?.let { number(it, 0) }
            "battery.level" -> data.batteryLevel?.let { Value.Number(it, Math.round(it * 100).toString()) }
            else -> if (name.startsWith("forecast.")) forecast(name) else data.live[name] ?: if (name.startsWith("prayer.")) data.prayer?.times?.get(name.removePrefix("prayer."))?.let { Value.Date(it) } else null
        }
    }

    // MARK: Time as a share (ADR-028)

    private fun periodStart(unit: ChronoUnit): ZonedDateTime {
        val day = zoned.toLocalDate()
        val first = when (unit) {
            ChronoUnit.YEARS -> day.withDayOfYear(1)
            ChronoUnit.MONTHS -> day.withDayOfMonth(1)
            ChronoUnit.WEEKS -> day.with(TemporalAdjusters.previousOrSame(WeekFields.of(context.locale).firstDayOfWeek))
            else -> day
        }
        return first.atStartOfDay(zoned.zone)
    }

    /** Share of the period gone: value 0…1, whole percent in text, like `battery.level`. */
    private fun progress(unit: ChronoUnit): Value {
        val start = periodStart(unit)
        val end = start.plus(1, unit)
        val share = (Duration.between(start, zoned).seconds.toDouble() / Duration.between(start, end).seconds.coerceAtLeast(1)).coerceIn(0.0, 1.0)
        return Value.Number(share, Math.round(share * 100).toString())
    }

    /** Days after today in the period. */
    private fun daysLeft(unit: ChronoUnit): Value {
        val end = periodStart(unit).plus(1, unit).toLocalDate()
        return number((ChronoUnit.DAYS.between(zoned.toLocalDate(), end) - 1).coerceAtLeast(0).toDouble(), 0)
    }

    /** Between today's sunrise and sunset when the weather gave them, else 6:00 to 18:00. */
    private fun isDay(): Boolean {
        val now = zoned.hour * 60 + zoned.minute
        fun minutes(value: Value.Date): Int = value.instant.atZone(zoned.zone).let { it.hour * 60 + it.minute }
        val rise = context.data.live["weather.sunrise"] as? Value.Date
        val set = context.data.live["weather.sunset"] as? Value.Date
        return if (rise != null && set != null) now >= minutes(rise) && now < minutes(set) else now >= 6 * 60 && now < 18 * 60
    }

    /** `forecast.<day>.<part>`: day 1 is tomorrow. */
    private fun forecast(name: String): Value? {
        val parts = name.split(".")
        val day = parts.getOrNull(1)?.toIntOrNull() ?: return null
        val item = context.data.weather?.forecast?.getOrNull(day) ?: return null
        return when (parts.getOrNull(2)) {
            "symbol" -> Value.Text(item.symbol)
            "hi" -> number(item.high, 0)
            "lo" -> number(item.low, 0)
            else -> Value.Text(DateTimeFormatter.ofPattern("EEE", context.locale).format(item.date))
        }
    }

    /** Playback values at this render's date. */
    private fun media(name: String, playback: MediaPlayback): Value {
        val position = playback.position(context.now)
        return when (name) {
            "media.playing" -> Value.Text(if (playback.playing) "1" else "0")
            "media.symbol" -> Value.Text(if (playback.playing) "pause.fill" else "play.fill")
            "media.elapsed" -> Value.Text(MediaPlayback.clock(position))
            "media.duration" -> Value.Text(MediaPlayback.clock(playback.duration))
            "media.remaining" -> Value.Text("-" + MediaPlayback.clock(playback.duration - position))
            else -> share(if (playback.duration > 0) minOf(position / playback.duration, 1.0) else 0.0)
        }
    }

    private fun timer(name: String, timer: TimerValues): Value? = when (name) {
        "timer.running" -> Value.Text(if (timer.isRunning(context.now)) "1" else "0")
        "timer.remaining" -> Value.Text(MediaPlayback.clock(timer.remaining(context.now)))
        "timer.end" -> timer.end?.let { Value.Date(it) }
        else -> share(timer.progress(context.now))
    }

    private fun share(value: Double) = Value.Number(value, Math.round(value * 100).toString())

    /** "23 Jumada I 1448" in the render language, digits Latin (Umm al-Qura). */
    private fun hijri(): String {
        val date = java.time.chrono.HijrahDate.from(zoned)
        return DateTimeFormatter.ofPattern("d MMMM yyyy", context.locale).withChronology(java.time.chrono.HijrahChronology.INSTANCE).format(date)
    }

    private fun number(value: Double, digits: Int, grouped: Boolean = false): Value {
        val symbols = DecimalFormatSymbols(Locale.US)
        val pattern = (if (grouped) "#,##0" else "0") + if (digits > 0) "." + "0".repeat(digits) else ""
        return Value.Number(value, DecimalFormat(pattern, symbols).format(value))
    }

    private fun format(pattern: String): String = DateTimeFormatter.ofPattern(pattern, Locale.US).format(zoned)

    private fun localized(pattern: String): String = DateTimeFormatter.ofPattern(pattern, context.locale).format(zoned)

    private fun offset(): String {
        val seconds = zoned.offset.totalSeconds
        if (seconds == 0) return "GMT"
        val sign = if (seconds > 0) "+" else "-"
        val hours = Math.abs(seconds) / 3600
        val minutes = Math.abs(seconds) % 3600 / 60
        return if (minutes == 0) "GMT$sign$hours" else "GMT$sign$hours:%02d".format(minutes)
    }

    companion object {
        const val MISSING = "--"
    }
}

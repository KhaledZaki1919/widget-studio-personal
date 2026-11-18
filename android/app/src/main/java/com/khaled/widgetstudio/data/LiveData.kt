package com.khaled.widgetstudio.data

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.os.BatteryManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.batoulapps.adhan.CalculationMethod
import com.batoulapps.adhan.Coordinates
import com.batoulapps.adhan.Madhab
import com.batoulapps.adhan.PrayerTimes
import com.batoulapps.adhan.Qibla
import com.batoulapps.adhan.data.DateComponents
import com.khaled.widgetstudio.design.ClockFormat
import com.khaled.widgetstudio.spec.Bindings
import com.khaled.widgetstudio.spec.BindingResolver
import com.khaled.widgetstudio.spec.DataSnapshot
import com.khaled.widgetstudio.spec.LText
import com.khaled.widgetstudio.spec.LayerContent
import com.khaled.widgetstudio.spec.MonthGrid
import com.khaled.widgetstudio.spec.TimerValues
import com.khaled.widgetstudio.spec.WidgetSpec
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.Period
import java.time.ZoneId
import java.util.Locale
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.math.roundToInt

/** App settings (AppSettings in DataCache.swift). */
class AppSettings(private val prefs: SharedPreferences) {
    var clockFormat: ClockFormat
        get() = ClockFormat.of(prefs.getString("clockFormat", null)) ?: ClockFormat.DEVICE
        set(value) = prefs.edit().putString("clockFormat", value.name).apply()
    var fahrenheit: Boolean
        get() = prefs.getBoolean("fahrenheit", false)
        set(value) = prefs.edit().putBoolean("fahrenheit", value).apply()
    var stepGoal: Int
        get() = prefs.getInt("stepGoal", 8000)
        set(value) = prefs.edit().putInt("stepGoal", value).apply()
    var dhikrs: List<String>
        get() = prefs.getString("dhikrs", null)?.split("\n")?.filter { it.isNotBlank() }?.takeIf { it.isNotEmpty() } ?: CounterState.defaultDhikrs
        set(value) = prefs.edit().putString("dhikrs", value.joinToString("\n")).apply()
    var onboardingDone: Boolean
        get() = prefs.getBoolean("onboardingDone", false)
        set(value) = prefs.edit().putBoolean("onboardingDone", value).apply()
}

/** The tasbeeh (CounterState.swift): a count per dhikr, cycling through the list. */
data class CounterState(val counts: Map<String, Int> = emptyMap(), val index: Int = 0) {
    fun dhikr(list: List<String>): String {
        val usable = usable(list)
        return usable[((index % usable.size) + usable.size) % usable.size]
    }

    fun count(list: List<String>) = counts[dhikr(list)] ?: 0

    /** +1; with a target, a tap after reaching it moves to the next dhikr from 0 (auto-advance at 33). */
    fun increment(list: List<String>, target: Int? = TARGET): CounterState {
        var state = this
        if (target != null && target > 0 && count(list) >= target) {
            val next = (index + 1) % usable(list).size
            state = CounterState(counts - usable(list)[next], next)
        }
        val dhikr = state.dhikr(list)
        return state.copy(counts = state.counts + (dhikr to (state.counts[dhikr] ?: 0) + 1))
    }

    fun next(list: List<String>) = copy(index = (index + 1) % usable(list).size)
    fun reset(list: List<String>) = copy(counts = counts - dhikr(list))

    companion object {
        const val TARGET = 33
        val defaultDhikrs = listOf("سبحان الله", "الحمد لله", "الله أكبر", "لا إله إلا الله")
        fun usable(list: List<String>) = list.map { it.trim() }.filter { it.isNotEmpty() }.ifEmpty { defaultDhikrs }
    }
}

/** The in-widget timer (Activity.swift): running until [endMillis], or paused with [left] seconds to go. */
data class TimerState(val endMillis: Long = 0, val left: Double = 0.0, val total: Double = 0.0) : TimerValues {
    override val end: Instant? get() = endMillis.takeIf { it > 0 }?.let { Instant.ofEpochMilli(it) }
    override fun isRunning(date: Instant) = endMillis > date.toEpochMilli()
    override fun remaining(date: Instant) = if (endMillis > 0) maxOf((endMillis - date.toEpochMilli()) / 1000.0, 0.0) else left
    override fun progress(date: Instant) = if (total > 0) (1 - remaining(date) / total).coerceIn(0.0, 1.0) else 0.0

    /** Starts ([minutes] when idle or finished), pauses, or resumes. */
    fun toggle(minutes: Int?, now: Instant = Instant.now()): TimerState = when {
        isRunning(now) -> TimerState(0, remaining(now), total)
        left > 0 -> TimerState(now.toEpochMilli() + (left * 1000).toLong(), 0.0, total)
        else -> {
            val seconds = maxOf(minutes ?: DEFAULT_MINUTES, 1) * 60.0
            TimerState(now.toEpochMilli() + (seconds * 1000).toLong(), 0.0, seconds)
        }
    }

    fun add(minutes: Int, now: Instant = Instant.now()): TimerState {
        val extra = minutes * 60.0
        return when {
            isRunning(now) -> copy(endMillis = endMillis + (extra * 1000).toLong(), total = total + extra)
            left > 0 -> copy(left = left + extra, total = total + extra)
            else -> TimerState(now.toEpochMilli() + (extra * 1000).toLong(), 0.0, extra)
        }
    }

    fun reset() = TimerState()

    companion object { const val DEFAULT_MINUTES = 25 }
}

/** A cached location (rounded to ~1 km before it leaves the device, ADR-020). */
data class StoredLocation(val latitude: Double, val longitude: Double, val altitude: Double?, val city: String?, val time: Long)

data class PrayerDay(val times: Map<String, Instant>, val qibla: Double)

/**
 * The real data for widgets and previews (LiveData.swift, ADR-016): location, Open-Meteo weather,
 * prayer times and Qibla (adhan, Egyptian method), Health Connect steps and sleep, battery, the
 * tasbeeh and the stopwatch. Values are cached in preferences, so widgets render instantly and
 * a refresh (app start, every 30 minutes in the background) only fills them in.
 */
class LiveRepository(private val context: Context) {
    private val prefs = context.getSharedPreferences("live", Context.MODE_PRIVATE)
    val settings = AppSettings(context.getSharedPreferences("settings", Context.MODE_PRIVATE))

    // MARK: Cached state

    var location: StoredLocation?
        get() = prefs.getString("location", null)?.let { runCatching { JSONObject(it) }.getOrNull() }?.let {
            StoredLocation(it.getDouble("lat"), it.getDouble("lon"), it.optDouble("alt").takeIf { a -> !a.isNaN() }, it.optString("city").ifEmpty { null }, it.getLong("time"))
        }
        private set(value) {
            prefs.edit().putString("location", value?.let {
                JSONObject().put("lat", it.latitude).put("lon", it.longitude).put("alt", it.altitude ?: Double.NaN).put("city", it.city ?: "").put("time", it.time).toString()
            }).apply()
        }

    var counter: CounterState
        get() = prefs.getString("counter", null)?.let { raw ->
            runCatching {
                val o = JSONObject(raw)
                val counts = o.getJSONObject("counts").let { c -> c.keys().asSequence().associateWith { c.getInt(it) } }
                CounterState(counts, o.getInt("index"))
            }.getOrNull()
        } ?: CounterState()
        set(value) {
            prefs.edit().putString("counter", JSONObject().put("counts", JSONObject(value.counts)).put("index", value.index).toString()).apply()
        }

    /** When the stopwatch started (epoch ms), or null when stopped. */
    var stopwatchStart: Long?
        get() = prefs.getLong("stopwatch", 0L).takeIf { it > 0 }
        set(value) = prefs.edit().putLong("stopwatch", value ?: 0L).apply()

    var timer: TimerState
        get() = prefs.getString("timer", null)?.let { raw ->
            runCatching { JSONObject(raw).let { TimerState(it.getLong("end"), it.getDouble("left"), it.getDouble("total")) } }.getOrNull()
        } ?: TimerState()
        set(value) {
            prefs.edit().putString("timer", JSONObject().put("end", value.endMillis).put("left", value.left).put("total", value.total).toString()).apply()
        }

    private var weatherJson: String?
        get() = prefs.getString("weather", null)
        set(value) = prefs.edit().putString("weather", value).apply()

    private var healthJson: String?
        get() = prefs.getString("health", null)
        set(value) = prefs.edit().putString("health", value).apply()

    var healthIssue: String?
        get() = prefs.getString("healthIssue", null)
        private set(value) = prefs.edit().putString("healthIssue", value).apply()

    // MARK: Snapshots

    /** Only real values; missing parts stay null (widgets). */
    fun snapshot(now: Instant = Instant.now(), language: String = "ar"): DataSnapshot {
        val zone = ZoneId.systemDefault()
        val location = location
        val prayer = location?.let { prayerDay(it, now.atZone(zone).toLocalDate(), zone) }
        val counter = counter
        val list = settings.dhikrs
        val health = healthJson?.let { runCatching { JSONObject(it) }.getOrNull() }
        return DataSnapshot(
            weather = weather(),
            stepsToday = health?.let { steps(it, now, zone)[now.atZone(zone).toLocalDate()] ?: 0.0 },
            stepsStreak = health?.let { streak(steps(it, now, zone), now, zone).toDouble() },
            stepsMonth = health?.let { h -> val s = steps(h, now, zone); s.filterKeys { it.month == now.atZone(zone).month && it.year == now.atZone(zone).year }.values.sum() },
            stepsMonthGrid = health?.let { monthLevels(steps(it, now, zone), now, zone) },
            sleepLastNight = health?.let { h -> sleep(h)[now.atZone(zone).toLocalDate()]?.let(::duration) },
            sleepWeek = health?.let { h -> sleepWeek(sleep(h), now, zone) },
            counter = counter.count(list).toDouble(),
            dhikr = counter.dhikr(list),
            stopwatchStart = stopwatchStart?.let { Instant.ofEpochMilli(it) },
            prayer = prayer?.let { day -> nextPrayer(day, location, now, zone) },
            qiblaBearing = prayer?.qibla,
            latitude = location?.latitude,
            longitude = location?.longitude,
            altitude = location?.altitude,
            batteryLevel = battery(),
            place = location?.city?.let { LText.Plain(it) },
            media = MediaHub.playback(context, now),
            timer = timer,
            live = DeviceState.read(context, now, language) + weatherExtras(now, zone) + healthExtras(health, now, zone),
        )
    }

    /** Humidity, wind, felt temperature, sunrise and sunset as catalog bindings (ADR-027). */
    private fun weatherExtras(now: Instant, zone: ZoneId): Map<String, BindingResolver.Value> {
        val body = weatherJson?.let { runCatching { JSONObject(it).getJSONObject("body") }.getOrNull() } ?: return emptyMap()
        val live = mutableMapOf<String, BindingResolver.Value>()
        val current = body.optJSONObject("current")
        fun number(key: String, id: String) {
            val value = current?.optDouble(key, Double.NaN) ?: Double.NaN
            if (!value.isNaN()) live[id] = BindingResolver.Value.Number(value, Math.round(value).toString())
        }
        number("relative_humidity_2m", "weather.humidity")
        number("wind_speed_10m", "weather.wind")
        number("apparent_temperature", "weather.feels")
        val daily = body.optJSONObject("daily")
        val today = now.atZone(zone).toLocalDate().toString()
        fun time(key: String, id: String) {
            val list = daily?.optJSONArray(key) ?: return
            val text = (0 until list.length()).map { list.getString(it) }.firstOrNull { it.startsWith(today) } ?: return
            runCatching { live[id] = BindingResolver.Value.Date(LocalDateTime.parse(text).atZone(zone).toInstant()) }
        }
        time("sunrise", "weather.sunrise")
        time("sunset", "weather.sunset")
        return live
    }

    private fun healthExtras(health: JSONObject?, now: Instant, zone: ZoneId): Map<String, BindingResolver.Value> {
        health ?: return emptyMap()
        val live = mutableMapOf<String, BindingResolver.Value>()
        val day = now.atZone(zone).toLocalDate()
        val goal = settings.stepGoal.toDouble()
        if (goal > 0) {
            val share = minOf((steps(health, now, zone)[day] ?: 0.0) / goal, 1.0)
            live["steps.progress"] = BindingResolver.Value.Number(share, Math.round(share * 100).toString())
        }
        health.optJSONObject("windows")?.optJSONArray(day.toString())?.let { window ->
            live["sleep.bedtime"] = BindingResolver.Value.Date(Instant.ofEpochMilli(window.getLong(0)))
            live["sleep.wake"] = BindingResolver.Value.Date(Instant.ofEpochMilli(window.getLong(1)))
        }
        sleep(health)[day]?.let { minutes ->
            val total = minutes.roundToInt()
            live["sleep.time"] = BindingResolver.Value.Text("${total / 60}:%02d".format(Locale.US, total % 60))
        }
        health.optJSONObject("extra")?.let { live += Extras.healthValues(it, sleep(health)[day], now, zone) }
        return live
    }

    /** Real values where known, sample values for the rest (editor and library previews). */
    fun previewSnapshot(now: Instant = Instant.now()): DataSnapshot {
        val real = snapshot(now, if (context.resources.configuration.locales[0].language == "en") "en" else "ar")
        val sample = DataSnapshot.sample(now, ZoneId.systemDefault())
        return DataSnapshot(
            weather = real.weather ?: sample.weather, stepsToday = real.stepsToday ?: sample.stepsToday,
            stepsStreak = real.stepsStreak ?: sample.stepsStreak, stepsMonth = real.stepsMonth ?: sample.stepsMonth,
            stepsMonthGrid = real.stepsMonthGrid ?: sample.stepsMonthGrid, sleepLastNight = real.sleepLastNight ?: sample.sleepLastNight,
            sleepWeek = real.sleepWeek ?: sample.sleepWeek, counter = real.counter, dhikr = real.dhikr, stopwatchStart = real.stopwatchStart,
            focusToday = sample.focusToday, focusWeek = sample.focusWeek, prayer = real.prayer ?: sample.prayer,
            qiblaBearing = real.qiblaBearing ?: sample.qiblaBearing, latitude = real.latitude ?: sample.latitude,
            longitude = real.longitude ?: sample.longitude, altitude = real.altitude ?: sample.altitude, batteryLevel = real.batteryLevel ?: sample.batteryLevel,
            place = real.place, media = real.media, timer = real.timer, live = sample.live + real.live,
        )
    }

    // MARK: Refresh

    /** Location, weather and health, each best effort; returns when done. */
    suspend fun refresh() = withContext(Dispatchers.IO) {
        refreshLocation()
        location?.let { runCatching { fetchWeather(it) } }
        runCatching { refreshHealth() }
        runCatching { Markets.refresh(context) }
    }

    fun hasLocationPermission() =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    suspend fun refreshLocation() {
        if (!hasLocationPermission()) return
        val manager = context.getSystemService(LocationManager::class.java) ?: return
        val providers = manager.getProviders(true)
        var best: Location? = providers.mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }.maxByOrNull { it.time }
        if (best == null || System.currentTimeMillis() - best.time > 30 * 60_000) {
            val provider = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER, LocationManager.PASSIVE_PROVIDER).firstOrNull { it in providers }
            if (provider != null && Build.VERSION.SDK_INT >= 30) {
                best = withTimeoutOrNull(15_000) {
                    suspendCancellableCoroutine { cont ->
                        manager.getCurrentLocation(provider, null, context.mainExecutor) { cont.resume(it) }
                    }
                } ?: best
            }
        }
        val found = best ?: return
        val city = runCatching {
            @Suppress("DEPRECATION")
            Geocoder(context, Locale.getDefault()).getFromLocation(found.latitude, found.longitude, 1)?.firstOrNull()?.let { it.locality ?: it.subAdminArea ?: it.adminArea }
        }.getOrNull()
        location = StoredLocation(found.latitude, found.longitude, if (found.hasAltitude()) found.altitude else null, city ?: location?.city, found.time)
    }

    // MARK: Weather (Open-Meteo, no key; coordinates rounded to two decimals ≈ 1 km)

    fun fetchWeather(at: StoredLocation) {
        val unit = if (settings.fahrenheit) "fahrenheit" else "celsius"
        val url = URL(
            "https://api.open-meteo.com/v1/forecast?latitude=%.2f&longitude=%.2f".format(Locale.US, at.latitude, at.longitude) +
                "&current=temperature_2m,weather_code,is_day,relative_humidity_2m,apparent_temperature,wind_speed_10m,uv_index&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset&timezone=auto&forecast_days=7&temperature_unit=$unit" +
                // ADR-029: the next hours (rain, icons, temperatures).
                "&hourly=temperature_2m,weather_code,precipitation_probability,precipitation,is_day&forecast_hours=30",
        )
        val connection = (url.openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 15_000
        }
        try {
            if (connection.responseCode !in 200..299) return
            val body = connection.inputStream.bufferedReader().readText()
            JSONObject(body).getJSONObject("current")
            val aqi = runCatching { Extras.airQuality(at.latitude, at.longitude) }.getOrNull()
            weatherJson = JSONObject().put("body", JSONObject(body)).put("city", at.city ?: "").put("fetched", System.currentTimeMillis()).put("aqi", aqi ?: Double.NaN).toString()
        } finally {
            connection.disconnect()
        }
    }

    fun weather(): DataSnapshot.Weather? {
        val stored = weatherJson?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return null
        return runCatching {
            val body = stored.getJSONObject("body")
            val current = body.getJSONObject("current")
            val daily = body.getJSONObject("daily")
            val isDay = current.optInt("is_day", 1) == 1
            val (symbol, text) = describe(current.getInt("weather_code"), isDay)
            val days = daily.getJSONArray("time")
            val forecast = (0 until days.length()).map { i ->
                DataSnapshot.DayForecast(
                    LocalDate.parse(days.getString(i)), describe(daily.getJSONArray("weather_code").getInt(i), true).first,
                    daily.getJSONArray("temperature_2m_max").getDouble(i), daily.getJSONArray("temperature_2m_min").getDouble(i),
                )
            }
            val city = stored.optString("city").ifEmpty { null }
            // Hours in the place's own offset (timezone=auto).
            val offset = java.time.ZoneOffset.ofTotalSeconds(body.optInt("utc_offset_seconds", 0))
            val hourly = body.optJSONObject("hourly")?.let { h ->
                val times = h.getJSONArray("time")
                (0 until times.length()).map { i ->
                    DataSnapshot.HourForecast(
                        LocalDateTime.parse(times.getString(i)).toInstant(offset),
                        describe(h.getJSONArray("weather_code").getInt(i), h.optJSONArray("is_day")?.optInt(i, 1) != 0).first,
                        h.getJSONArray("temperature_2m").getDouble(i), h.optJSONArray("precipitation_probability")?.optDouble(i, 0.0) ?: 0.0,
                        h.optJSONArray("precipitation")?.optDouble(i, 0.0) ?: 0.0,
                    )
                }
            } ?: emptyList()
            DataSnapshot.Weather(
                current.getDouble("temperature_2m"), forecast.firstOrNull()?.high ?: 0.0, forecast.firstOrNull()?.low ?: 0.0, text, symbol,
                LText.Plain(city ?: "--"), forecast, hourly, current.optDouble("uv_index", Double.NaN).takeIf { !it.isNaN() },
                stored.optDouble("aqi", Double.NaN).takeIf { !it.isNaN() },
            )
        }.getOrNull()
    }

    // MARK: Prayer and Qibla (adhan, Egyptian General Authority of Survey)

    fun prayerDay(at: StoredLocation, date: LocalDate, zone: ZoneId): PrayerDay {
        val coordinates = Coordinates(at.latitude, at.longitude)
        val parameters = CalculationMethod.EGYPTIAN.parameters.apply { madhab = Madhab.SHAFI }
        val times = PrayerTimes(coordinates, DateComponents(date.year, date.monthValue, date.dayOfMonth), parameters)
        return PrayerDay(
            mapOf("fajr" to times.fajr, "dhuhr" to times.dhuhr, "asr" to times.asr, "maghrib" to times.maghrib, "isha" to times.isha).mapValues { it.value.toInstant() },
            Qibla(coordinates).direction,
        )
    }

    private fun nextPrayer(day: PrayerDay, at: StoredLocation, now: Instant, zone: ZoneId): DataSnapshot.Prayer {
        val next = prayerNames.firstOrNull { (day.times[it.first] ?: now) > now }
        if (next != null) return DataSnapshot.Prayer(day.times, next.second, next.first, day.times.getValue(next.first))
        val tomorrow = prayerDay(at, now.atZone(zone).toLocalDate().plusDays(1), zone)
        return DataSnapshot.Prayer(day.times, prayerNames[0].second, "fajr", tomorrow.times.getValue("fajr"))
    }

    // MARK: Health Connect

    val healthPermissions = setOf(HealthPermission.getReadPermission(StepsRecord::class), HealthPermission.getReadPermission(SleepSessionRecord::class))
    /** ADR-029: heart, variability, exercise and calories; asked together, each read only when granted. */
    val extraHealthPermissions = Extras.healthPermissions
    val allHealthPermissions get() = healthPermissions + extraHealthPermissions

    fun healthAvailable() = HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE

    suspend fun refreshHealth() {
        if (!healthAvailable()) {
            healthIssue = "unavailable"
            return
        }
        val client = HealthConnectClient.getOrCreate(context)
        if (!client.permissionController.getGrantedPermissions().containsAll(healthPermissions)) {
            healthIssue = "permission"
            return
        }
        val zone = ZoneId.systemDefault()
        val today = LocalDate.now(zone)
        val start = today.minusDays(62).atStartOfDay()
        val steps = client.aggregateGroupByPeriod(
            AggregateGroupByPeriodRequest(setOf(StepsRecord.COUNT_TOTAL), TimeRangeFilter.between(start, LocalDateTime.now(zone)), Period.ofDays(1)),
        )
        val stepJson = JSONObject()
        for (bucket in steps) stepJson.put(bucket.startTime.toLocalDate().toString(), (bucket.result[StepsRecord.COUNT_TOTAL] ?: 0L).toDouble())
        // Sleep: minutes of each session, counted on the day it ended.
        val sessions = client.readRecords(ReadRecordsRequest(SleepSessionRecord::class, TimeRangeFilter.between(today.minusDays(8).atStartOfDay(), LocalDateTime.now(zone)))).records
        val sleepJson = JSONObject()
        val windows = JSONObject()
        for (session in sessions) {
            val day = session.endTime.atZone(zone).toLocalDate().toString()
            val minutes = (session.endTime.toEpochMilli() - session.startTime.toEpochMilli()) / 60_000.0
            sleepJson.put(day, sleepJson.optDouble(day, 0.0) + minutes)
            val known = windows.optJSONArray(day)
            windows.put(day, org.json.JSONArray().put(minOf(known?.optLong(0) ?: Long.MAX_VALUE, session.startTime.toEpochMilli())).put(maxOf(known?.optLong(1) ?: 0L, session.endTime.toEpochMilli())))
        }
        val extra = runCatching { Extras.readHealth(client, zone, sessions) }.getOrNull()
        healthJson = JSONObject().put("steps", stepJson).put("sleep", sleepJson).put("windows", windows).put("fetched", System.currentTimeMillis())
            .put("extra", extra ?: JSONObject()).toString()
        healthIssue = null
    }

    private fun steps(health: JSONObject, now: Instant, zone: ZoneId): Map<LocalDate, Double> {
        val o = health.optJSONObject("steps") ?: return emptyMap()
        return o.keys().asSequence().associate { LocalDate.parse(it) to o.getDouble(it) }
    }

    private fun sleep(health: JSONObject): Map<LocalDate, Double> {
        val o = health.optJSONObject("sleep") ?: return emptyMap()
        return o.keys().asSequence().associate { LocalDate.parse(it) to o.getDouble(it) }
    }

    private fun streak(steps: Map<LocalDate, Double>, now: Instant, zone: ZoneId): Int {
        val goal = settings.stepGoal.toDouble()
        var day = now.atZone(zone).toLocalDate()
        if ((steps[day] ?: 0.0) < goal) day = day.minusDays(1)
        var count = 0
        while ((steps[day] ?: 0.0) >= goal && count < 62) {
            count++
            day = day.minusDays(1)
        }
        return count
    }

    private fun monthLevels(steps: Map<LocalDate, Double>, now: Instant, zone: ZoneId): List<Double> {
        val today = now.atZone(zone).toLocalDate()
        val goal = maxOf(settings.stepGoal.toDouble(), 1.0)
        val perDay = (1..today.lengthOfMonth()).map { d ->
            when {
                d == today.dayOfMonth -> MonthGrid.HIGHLIGHT
                d < today.dayOfMonth -> minOf((steps[today.withDayOfMonth(d)] ?: 0.0) / goal, 1.0)
                else -> 0.0
            }
        }
        val firstDay = if (Locale.getDefault().language == "ar") DayOfWeek.SATURDAY else DayOfWeek.SUNDAY
        return MonthGrid.levels(perDay, today, firstDay)
    }

    private fun sleepWeek(sleep: Map<LocalDate, Double>, now: Instant, zone: ZoneId): List<Double> {
        val today = now.atZone(zone).toLocalDate()
        val weekday = today.dayOfWeek.value % 7 + 1 // 1 = Sunday, like Calendar
        return (1..7).map { day -> if (day > weekday) 0.0 else minOf((sleep[today.plusDays((day - weekday).toLong())] ?: 0.0) / (9 * 60), 1.0) }
    }

    // MARK: Battery

    fun battery(): Double? {
        val manager = context.getSystemService(BatteryManager::class.java) ?: return null
        val percent = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (percent in 0..100) percent / 100.0 else null
    }

    companion object {
        val prayerNames = listOf(
            "fajr" to LText.Localized("Fajr", "الفجر"), "dhuhr" to LText.Localized("Dhuhr", "الظهر"), "asr" to LText.Localized("Asr", "العصر"),
            "maghrib" to LText.Localized("Maghrib", "المغرب"), "isha" to LText.Localized("Isha", "العشاء"),
        )

        fun duration(minutes: Double): LText {
            val total = minutes.roundToInt()
            return LText.Localized("${total / 60}h ${total % 60}m", "${total / 60}س ${total % 60}د")
        }

        /** WMO weather code → SF Symbol name (drawn as its Material twin) and condition (OpenMeteo.swift). */
        fun describe(code: Int, isDay: Boolean): Pair<String, LText> = when (code) {
            0 -> (if (isDay) "sun.max.fill" else "moon.fill") to LText.Localized("Clear", "صافٍ")
            1 -> (if (isDay) "sun.max.fill" else "moon.stars.fill") to LText.Localized("Mainly clear", "صافٍ غالبًا")
            2 -> (if (isDay) "cloud.sun.fill" else "cloud.moon.fill") to LText.Localized("Partly cloudy", "غائم جزئيًا")
            3 -> "cloud.fill" to LText.Localized("Overcast", "غائم")
            45, 48 -> "cloud.fog.fill" to LText.Localized("Fog", "ضباب")
            51, 53, 55, 56, 57 -> "cloud.drizzle.fill" to LText.Localized("Drizzle", "رذاذ")
            61, 63, 66, 80, 81 -> "cloud.rain.fill" to LText.Localized("Rain", "مطر")
            65, 67, 82 -> "cloud.heavyrain.fill" to LText.Localized("Heavy rain", "مطر غزير")
            71, 73, 75, 77, 85, 86 -> "cloud.snow.fill" to LText.Localized("Snow", "ثلج")
            95, 96, 99 -> "cloud.bolt.rain.fill" to LText.Localized("Thunderstorm", "عاصفة رعدية")
            else -> "cloud.fill" to LText.Localized("Cloudy", "غائم")
        }
    }
}

/** Why a widget can't show its data yet (DataGap in LiveData.swift). */
enum class DataGap { NO_LOCATION, NO_WEATHER, NO_HEALTH, NO_BATTERY }

/** The data groups a spec reads (DataRequirements.swift). */
object DataRequirements {
    fun groups(spec: WidgetSpec): Set<String> {
        val names = mutableSetOf<String>()
        for (layer in spec.layers.flatMap { it.flattened }) {
            val texts = when (val c = layer.content) {
                is LayerContent.Text -> c.value.allValues + listOfNotNull(c.liveTarget)
                is LayerContent.Icon -> listOf(c.symbol)
                is LayerContent.Ring -> listOf(c.progress)
                is LayerContent.ProgressBar -> listOf(c.progress)
                is LayerContent.DotGrid -> listOf(c.values)
                is LayerContent.DotBars -> listOf(c.values) + (c.labels?.allValues ?: emptyList())
                is LayerContent.ListL -> c.items.flatMap { it.title.allValues + (it.detail?.allValues ?: emptyList()) }
                is LayerContent.ForecastRow -> listOf("{{weather.temp}}")
                is LayerContent.States -> c.expanded.mapNotNull { it.condition } + listOfNotNull(c.value)
                else -> emptyList()
            } + listOfNotNull(layer.condition, layer.rotation)
            texts.forEach { text -> Bindings.tokenize(text).filterIsInstance<Bindings.Token.Binding>().forEach { names += it.name.trim() } }
        }
        return names.mapNotNull { name ->
            when {
                name.startsWith("weather.") || name.startsWith("forecast.") -> "weather"
                name.startsWith("prayer.") || name.startsWith("qibla.") -> "prayer"
                name.startsWith("location.") -> "location"
                name.startsWith("steps.") || name.startsWith("sleep.") -> "health"
                name == "battery.level" -> "device"
                else -> null
            }
        }.toSet()
    }

    /** The catalog group of every binding a spec reads. */
    fun bindingGroups(spec: WidgetSpec): Set<String> = com.khaled.widgetstudio.spec.BindingNames.names(spec).mapNotNull { name -> com.khaled.widgetstudio.spec.Capabilities.binding(name)?.group }.toSet()

    fun gap(spec: WidgetSpec, live: LiveRepository, data: DataSnapshot): DataGap? {
        val groups = groups(spec)
        if ((groups intersect setOf("weather", "prayer", "location")).isNotEmpty() && live.location == null) return DataGap.NO_LOCATION
        if ("weather" in groups && data.weather == null) return DataGap.NO_WEATHER
        if ("health" in groups && data.stepsToday == null && data.sleepWeek == null) return DataGap.NO_HEALTH
        if ("device" in groups && data.batteryLevel == null) return DataGap.NO_BATTERY
        return null
    }
}

/** Every 30 minutes: location, weather and health, then every widget is redrawn. */
class RefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        com.khaled.widgetstudio.widget.WidgetEnvironment.live(applicationContext).refresh()
        com.khaled.widgetstudio.widget.UpdateLatency.changed(applicationContext, com.khaled.widgetstudio.widget.LiveUpdates.Source.WORKER)
        com.khaled.widgetstudio.widget.Widgets.updateAll(applicationContext)
        return Result.success()
    }

    companion object {
        fun schedule(context: Context) {
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                "refresh", ExistingPeriodicWorkPolicy.UPDATE, PeriodicWorkRequestBuilder<RefreshWorker>(15, TimeUnit.MINUTES).build(),
            )
        }
    }
}

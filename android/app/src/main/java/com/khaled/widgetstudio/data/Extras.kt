package com.khaled.widgetstudio.data

import android.Manifest
import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Build
import android.os.Process
import androidx.core.content.ContextCompat
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateGroupByDurationRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.khaled.widgetstudio.design.DesignStore
import com.khaled.widgetstudio.spec.BindingResolver.Value
import com.khaled.widgetstudio.spec.WidgetSpec
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale
import kotlin.math.roundToInt

/**
 * The live values ADR-029 added on Android: heart, stress, energy, activity, sleep stages and hourly
 * steps (Health Connect), air quality (Open-Meteo), screen time (usage access), earbuds battery
 * (Bluetooth) and market prices (Yahoo Finance's public chart endpoint), plus app icons for image layers.
 */
object Extras {
    val healthPermissions = setOf(
        HealthPermission.getReadPermission(HeartRateRecord::class), HealthPermission.getReadPermission(RestingHeartRateRecord::class),
        HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class), HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
    )

    // MARK: Health

    /** Today's heart samples, resting rate, variability, exercise, calories, last night's stages and steps per hour. */
    suspend fun readHealth(client: HealthConnectClient, zone: ZoneId, sessions: List<SleepSessionRecord>): JSONObject {
        val granted = client.permissionController.getGrantedPermissions()
        val today = LocalDate.now(zone)
        val startOfDay = today.atStartOfDay()
        val now = LocalDateTime.now(zone)
        val range = TimeRangeFilter.between(startOfDay, now)
        val out = JSONObject()
        if (HealthPermission.getReadPermission(HeartRateRecord::class) in granted) {
            val samples = client.readRecords(ReadRecordsRequest(HeartRateRecord::class, range)).records.flatMap { it.samples }
            out.put("heart", JSONArray(samples.sortedBy { it.time }.map { JSONArray().put(it.time.toEpochMilli()).put(it.beatsPerMinute) }.takeLast(600)))
        }
        if (HealthPermission.getReadPermission(RestingHeartRateRecord::class) in granted) {
            client.readRecords(ReadRecordsRequest(RestingHeartRateRecord::class, TimeRangeFilter.between(today.minusDays(1).atStartOfDay(), now))).records
                .maxByOrNull { it.time }?.let { out.put("resting", it.beatsPerMinute) }
        }
        if (HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class) in granted) {
            client.readRecords(ReadRecordsRequest(HeartRateVariabilityRmssdRecord::class, TimeRangeFilter.between(today.minusDays(1).atStartOfDay(), now))).records
                .maxByOrNull { it.time }?.let { out.put("rmssd", it.heartRateVariabilityMillis) }
        }
        if (HealthPermission.getReadPermission(ExerciseSessionRecord::class) in granted) {
            val minutes = client.readRecords(ReadRecordsRequest(ExerciseSessionRecord::class, range)).records.sumOf { Duration.between(it.startTime, it.endTime).toMinutes() }
            out.put("exercise", minutes)
        }
        if (HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class) in granted) {
            val result = client.aggregate(AggregateRequest(setOf(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL), range))
            result[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.let { out.put("kcal", it.inKilocalories) }
        }
        // Last night's stages every 10 minutes: 0 deep, 1 core or light, 2 REM, 3 awake.
        sessions.filter { it.endTime.atZone(zone).toLocalDate() == today }.maxByOrNull { it.endTime }?.let { night ->
            val bins = mutableListOf<Int>()
            var t = night.startTime
            while (t < night.endTime && bins.size < 120) {
                val stage = night.stages.firstOrNull { !t.isBefore(it.startTime) && t.isBefore(it.endTime) }?.stage
                bins += when (stage) {
                    SleepSessionRecord.STAGE_TYPE_DEEP -> 0
                    SleepSessionRecord.STAGE_TYPE_REM -> 2
                    SleepSessionRecord.STAGE_TYPE_AWAKE, SleepSessionRecord.STAGE_TYPE_AWAKE_IN_BED, SleepSessionRecord.STAGE_TYPE_OUT_OF_BED -> 3
                    else -> 1
                }
                t = t.plusSeconds(600)
            }
            out.put("stages", JSONArray(bins))
        }
        val hourly = client.aggregateGroupByDuration(AggregateGroupByDurationRequest(setOf(StepsRecord.COUNT_TOTAL), range, Duration.ofHours(1)))
        val perHour = DoubleArray(24)
        for (bucket in hourly) perHour[bucket.startTime.atZone(zone).hour] += (bucket.result[StepsRecord.COUNT_TOTAL] ?: 0L).toDouble()
        out.put("stepsHourly", JSONArray(perHour.toList()))
        return out
    }

    /** The catalog values from what [readHealth] stored. */
    fun healthValues(extra: JSONObject, sleepMinutes: Double?, now: Instant, zone: ZoneId): Map<String, Value> {
        val live = mutableMapOf<String, Value>()
        fun number(id: String, value: Double) { live[id] = Value.Number(value, value.roundToInt().toString()) }
        val heart = extra.optJSONArray("heart")?.let { list -> (0 until list.length()).map { list.getJSONArray(it).let { p -> p.getLong(0) to p.getDouble(1) } } } ?: emptyList()
        heart.lastOrNull()?.let { number("heart.rate", it.second) }
        if (heart.isNotEmpty()) {
            // 20-minute averages from midnight to now.
            val start = now.atZone(zone).toLocalDate().atStartOfDay(zone).toInstant().toEpochMilli()
            val bins = heart.groupBy { ((it.first - start) / 1_200_000L).toInt() }.toSortedMap().values.map { group -> group.map { it.second }.average() }
            live["heart.today"] = Value.Levels(bins)
        }
        val resting = extra.optDouble("resting", Double.NaN).takeIf { !it.isNaN() } ?: heart.minOfOrNull { it.second }
        resting?.let { number("heart.resting", it) }
        extra.optDouble("rmssd", Double.NaN).takeIf { !it.isNaN() }?.let { number("stress.level", stress(it)) }
        val exercise = extra.optDouble("exercise", Double.NaN).takeIf { !it.isNaN() }
        exercise?.let { number("activity.minutes", it) }
        extra.optDouble("kcal", Double.NaN).takeIf { !it.isNaN() }?.let { number("activity.kcal", it) }
        energy(sleepMinutes, exercise, now, zone)?.let { number("energy.level", it) }
        extra.optJSONArray("stages")?.let { list -> live["sleep.stages"] = Value.Levels((0 until list.length()).map { list.getDouble(it) }) }
        extra.optJSONArray("stepsHourly")?.let { list -> live["steps.hourly"] = Value.Levels((0 until list.length()).map { list.getDouble(it) }) }
        return live
    }

    /** Stress 0…100 from RMSSD: 80 ms or more is calm (0), 20 ms or less is high (100). An estimate. */
    fun stress(rmssd: Double): Double = ((80 - rmssd) / 60 * 100).coerceIn(0.0, 100.0)

    /** Energy 0…100: last night's sleep against 8 hours, drained through the day and by exercise. An estimate. */
    fun energy(sleepMinutes: Double?, exercise: Double?, now: Instant, zone: ZoneId): Double? {
        sleepMinutes ?: return null
        val rested = (sleepMinutes / 480).coerceIn(0.0, 1.0) * 100
        val hour = now.atZone(zone).let { it.hour + it.minute / 60.0 }
        val drain = ((hour - 7).coerceIn(0.0, 16.0) / 16) * 35 + (exercise ?: 0.0) * 0.2
        return (rested - drain).coerceIn(5.0, 100.0)
    }

    // MARK: Air quality

    /** The current European AQI (Open-Meteo, no key). */
    fun airQuality(latitude: Double, longitude: Double): Double? {
        val body = get("https://air-quality-api.open-meteo.com/v1/air-quality?latitude=%.2f&longitude=%.2f&current=european_aqi".format(Locale.US, latitude, longitude)) ?: return null
        return JSONObject(body).optJSONObject("current")?.optDouble("european_aqi", Double.NaN)?.takeIf { !it.isNaN() }
    }

    // MARK: Device values

    fun read(context: Context, now: Instant): Map<String, Value> {
        val live = mutableMapOf<String, Value>()
        screenTime(context, now)?.let { minutes ->
            live["screenTime.today"] = Value.Text(if (minutes >= 60) "${minutes / 60}h ${minutes % 60}m" else "${minutes}m")
        }
        earbuds(context)?.let { live["earbuds.level"] = Value.Number(it, (it * 100).roundToInt().toString()) }
        live += Markets.values(context)
        return live
    }

    fun hasUsageAccess(context: Context): Boolean {
        val ops = context.getSystemService(AppOpsManager::class.java) ?: return false
        @Suppress("DEPRECATION")
        val mode = if (Build.VERSION.SDK_INT >= 29) ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        else ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Minutes of foreground use today, or null without usage access. */
    fun screenTime(context: Context, now: Instant): Int? {
        if (!hasUsageAccess(context)) return null
        val manager = context.getSystemService(UsageStatsManager::class.java) ?: return null
        val start = now.atZone(ZoneId.systemDefault()).toLocalDate().atStartOfDay(ZoneId.systemDefault()).toInstant().toEpochMilli()
        val stats = runCatching { manager.queryAndAggregateUsageStats(start, now.toEpochMilli()) }.getOrNull() ?: return null
        return (stats.values.sumOf { it.totalTimeInForeground } / 60_000L).toInt()
    }

    /** The battery of a connected headset 0…1 (Android shares one level per device), or null. */
    @android.annotation.SuppressLint("MissingPermission")
    fun earbuds(context: Context): Double? {
        if (Build.VERSION.SDK_INT >= 31 && ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) return null
        val adapter = context.getSystemService(BluetoothManager::class.java)?.adapter ?: return null
        return runCatching {
            adapter.bondedDevices.orEmpty().firstNotNullOfOrNull { device ->
                val connected = device.javaClass.getMethod("isConnected").invoke(device) as? Boolean ?: false
                val level = device.javaClass.getMethod("getBatteryLevel").invoke(device) as? Int ?: -1
                if (connected && level in 0..100) level / 100.0 else null
            }
        }.getOrNull()
    }

    // MARK: App icons

    /** Image bindings for a render: the playing app's icon and the icons of the spec's app fields (by package). */
    fun images(context: Context, spec: WidgetSpec, fieldValue: (String) -> String?): Map<String, Bitmap> {
        val images = mutableMapOf<String, Bitmap>()
        val names = com.khaled.widgetstudio.spec.BindingNames.names(spec)
        if ("media.appIcon" in names) MediaHub.playingPackage(context)?.let { icon(context, it) }?.let { images["media.appIcon"] = it }
        for (field in spec.fields.filter { it.type == "app" }) {
            val pkg = fieldValue(field.key)?.trim()?.takeIf { it.isNotEmpty() } ?: continue
            icon(context, pkg)?.let { images["app.$pkg.icon"] = it }
        }
        return images
    }

    fun icon(context: Context, packageName: String, size: Int = 192): Bitmap? = runCatching {
        val drawable = context.packageManager.getApplicationIcon(packageName)
        Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888).also { bitmap ->
            drawable.setBounds(0, 0, size, size)
            drawable.draw(Canvas(bitmap))
        }
    }.getOrNull()

    fun get(url: String): String? {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 15_000
            setRequestProperty("User-Agent", "WidgetStudio")
        }
        return try {
            if (connection.responseCode in 200..299) connection.inputStream.bufferedReader().readText() else null
        } finally {
            connection.disconnect()
        }
    }

    fun encode(text: String): String = URLEncoder.encode(text, "UTF-8")
}

/** Prices of the tickers in saved designs (ADR-029): fetched by the refresh worker, cached, read by widgets. */
object Markets {
    private val coins = mapOf("bitcoin" to "BTC-USD", "btc" to "BTC-USD", "ethereum" to "ETH-USD", "eth" to "ETH-USD", "solana" to "SOL-USD", "sol" to "SOL-USD")

    /** The provider's symbol for a ticker field value: TSLA, AMZN, BTC-USD; coin names map to their pair. */
    fun symbol(ticker: String): String = coins[ticker.trim().lowercase()] ?: ticker.trim().uppercase()

    /** Every ticker in the saved designs. */
    fun tickers(context: Context): Set<String> = DesignStore.get(context).designs.value.flatMap { design ->
        design.spec.fields.filter { it.type == "ticker" }.mapNotNull { field ->
            (design.fieldValues[field.key] ?: field.default)?.resolved("en")?.trim()?.lowercase()?.takeIf { it.isNotEmpty() }
        }
    }.toSet()

    fun refresh(context: Context) {
        val prefs = context.getSharedPreferences("markets", Context.MODE_PRIVATE)
        for (ticker in tickers(context)) {
            val body = runCatching { Extras.get("https://query1.finance.yahoo.com/v8/finance/chart/${Extras.encode(symbol(ticker))}?range=1mo&interval=1d") }.getOrNull() ?: continue
            val result = runCatching { JSONObject(body).getJSONObject("chart").getJSONArray("result").getJSONObject(0) }.getOrNull() ?: continue
            val meta = result.getJSONObject("meta")
            val closes = result.optJSONObject("indicators")?.optJSONArray("quote")?.optJSONObject(0)?.optJSONArray("close")
            val series = closes?.let { list -> (0 until list.length()).mapNotNull { i -> list.optDouble(i, Double.NaN).takeIf { !it.isNaN() } } } ?: emptyList()
            val price = meta.optDouble("regularMarketPrice", series.lastOrNull() ?: Double.NaN)
            val previous = meta.optDouble("chartPreviousClose", Double.NaN).let { if (series.size >= 2) series[series.size - 2] else it }
            if (price.isNaN()) continue
            prefs.edit().putString(ticker, JSONObject().put("price", price).put("previous", previous).put("series", JSONArray(series)).put("fetched", System.currentTimeMillis()).toString()).apply()
        }
    }

    /** `stock.<ticker>.<part>` for every cached ticker. */
    fun values(context: Context): Map<String, Value> {
        val prefs = context.getSharedPreferences("markets", Context.MODE_PRIVATE)
        val live = mutableMapOf<String, Value>()
        for ((ticker, raw) in prefs.all) {
            val o = runCatching { JSONObject(raw as String) }.getOrNull() ?: continue
            val price = o.optDouble("price", Double.NaN).takeIf { !it.isNaN() } ?: continue
            live["stock.$ticker.price"] = Value.Number(price, "%.2f".format(Locale.US, price))
            o.optDouble("previous", Double.NaN).takeIf { !it.isNaN() && it != 0.0 }?.let { previous ->
                val change = price - previous
                live["stock.$ticker.change"] = Value.Number(change, (if (change >= 0) "+" else "") + "%.2f".format(Locale.US, change))
                val pct = change / previous * 100
                live["stock.$ticker.changePct"] = Value.Number(pct, (if (pct >= 0) "+" else "") + "%.2f".format(Locale.US, pct))
            }
            o.optJSONArray("series")?.let { list -> live["stock.$ticker.series"] = Value.Levels((0 until list.length()).map { list.getDouble(it) }) }
        }
        return live
    }
}

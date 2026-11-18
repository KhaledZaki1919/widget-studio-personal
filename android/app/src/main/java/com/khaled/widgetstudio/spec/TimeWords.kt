package com.khaled.widgetstudio.spec

import java.time.format.DateTimeFormatter

/** Words for the time and the rain (BindingResolver.swift's TimeWords, ADR-029). */
object TimeWords {
    private val english = listOf("O'CLOCK", "FIVE PAST", "TEN PAST", "QUARTER PAST", "TWENTY PAST", "TWENTY-FIVE PAST", "HALF PAST",
        "TWENTY-FIVE TO", "TWENTY TO", "QUARTER TO", "TEN TO", "FIVE TO")
    private val arabic = listOf("تمامًا", "وخمسة", "وعشرة", "والربع", "والثلث", "ونصف إلا خمسة", "والنصف", "ونصف وخمسة", "إلا ثلث", "إلا ربع", "إلا عشرة", "إلا خمسة")

    /** "HALF PAST 12", "QUARTER TO 3", "12 O'CLOCK"; Arabic "12 والنصف". Five-minute steps, 12-hour digits. */
    fun words(hour24: Int, minute: Int, isArabic: Boolean): String {
        val step = ((minute + 2) / 5) % 12
        val carry = if (minute >= 58) 1 else 0
        val base = (hour24 + carry) % 12
        val hour = if (step >= 7) (base + 1) % 12 else base
        val shown = if (hour == 0) 12 else hour
        return if (isArabic) "$shown ${arabic[step]}" else if (step == 0) "$shown ${english[0]}" else "${english[step]} $shown"
    }

    /** "No rain in the next 2 hours", "Rain expected within 2 hours" or "Rain expected at 4 PM". */
    fun rainNext(hours: List<DataSnapshot.HourForecast>, context: RenderContext): String {
        fun wet(h: DataSnapshot.HourForecast) = h.rainChance >= 50 || h.rain >= 0.2
        val soon = hours.take(2).any(::wet)
        val later = hours.drop(2).take(10).firstOrNull(::wet)
        return when {
            soon -> if (context.isArabic) "مطر متوقع خلال ساعتين" else "Rain expected within 2 hours"
            later != null -> {
                val at = DateTimeFormatter.ofPattern(if (context.uses24Hour == false) "h a" else "HH:mm", context.locale).format(later.time.atZone(context.zone))
                if (context.isArabic) "مطر متوقع الساعة $at" else "Rain expected at $at"
            }
            else -> if (context.isArabic) "لا مطر في الساعتين القادمتين" else "No rain in the next 2 hours"
        }
    }
}

import Foundation

/// Words for the time and the rain (ADR-029); twin of TimeWords.kt.
public enum TimeWords {
    static let english = ["O'CLOCK", "FIVE PAST", "TEN PAST", "QUARTER PAST", "TWENTY PAST", "TWENTY-FIVE PAST", "HALF PAST",
                          "TWENTY-FIVE TO", "TWENTY TO", "QUARTER TO", "TEN TO", "FIVE TO"]
    static let arabic = ["تمامًا", "وخمسة", "وعشرة", "والربع", "والثلث", "ونصف إلا خمسة", "والنصف", "ونصف وخمسة", "إلا ثلث", "إلا ربع",
                         "إلا عشرة", "إلا خمسة"]

    /// "HALF PAST 12", "QUARTER TO 3", "12 O'CLOCK"; Arabic "12 والنصف". Five-minute steps, 12-hour digits.
    public static func words(hour: Int, minute: Int, arabic isArabic: Bool) -> String {
        let step = ((minute + 2) / 5) % 12
        let carry = minute >= 58 ? 1 : 0
        let base = (hour + carry) % 12
        let shown12 = step >= 7 ? (base + 1) % 12 : base
        let shown = shown12 == 0 ? 12 : shown12
        if isArabic { return "\(shown) \(arabic[step])" }
        return step == 0 ? "\(shown) \(english[0])" : "\(english[step]) \(shown)"
    }

    /// "No rain in the next 2 hours", "Rain expected within 2 hours" or "Rain expected at 4 PM".
    static func rainNext(_ hours: [DataSnapshot.HourForecast], context: RenderContext) -> String {
        func wet(_ hour: DataSnapshot.HourForecast) -> Bool { hour.rainChance >= 50 || hour.rain >= 0.2 }
        if hours.prefix(2).contains(where: wet) {
            return context.isArabic ? "مطر متوقع خلال ساعتين" : "Rain expected within 2 hours"
        }
        if let later = hours.dropFirst(2).prefix(10).first(where: wet) {
            let at = FormatterCache.date(context.uses24Hour == false ? "h a" : "HH:mm", locale: context.localeIdentifier, zone: context.timeZone)
                .string(from: later.date)
            return context.isArabic ? "مطر متوقع الساعة \(at)" : "Rain expected at \(at)"
        }
        return context.isArabic ? "لا مطر في الساعتين القادمتين" : "No rain in the next 2 hours"
    }
}

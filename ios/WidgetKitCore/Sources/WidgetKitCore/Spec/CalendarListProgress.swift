import Foundation

/// The current month as a calendar (ADR-019): a title, a weekday row and the day numbers in a
/// 7-column grid, with weekend days and today styled. Uses the render date and time zone; month
/// and weekday names follow the render language. With `mirror`, columns run right to left.
public struct CalendarMonthLayer: Codable, Sendable, Equatable {
    public enum TitleFormat: String, Codable, Sendable, CaseIterable {
        case none, short = "MMM", long = "MMMM", shortYear = "MMM yyyy", longYear = "MMMM yyyy"
    }

    public enum TitleCase: String, Codable, Sendable, CaseIterable {
        /// "AUG"
        case upper
        /// "aug"
        case lower
        /// As the language writes it: "Aug"
        case natural
    }

    public enum WeekdayStyle: String, Codable, Sendable, CaseIterable {
        case none
        /// "M T W"
        case narrow
        /// "Mon Tue"
        case short
        /// "Mo Tu" (ADR-029)
        case two
    }
    /// ADR-029: the whole month, the current week, or this week and the next.
    public enum Rows: String, Codable, Sendable, CaseIterable {
        case month, week
        case twoWeeks = "2weeks"
    }

    public enum WeekStart: String, Codable, Sendable, CaseIterable {
        /// The render language's own (Saturday in Arabic, Sunday in English).
        case locale, saturday, sunday, monday
    }

    public enum TodayStyle: String, Codable, Sendable, CaseIterable {
        /// A filled rounded square behind the number.
        case filled
        case circle, ring, dot, none
    }

    public enum OtherDays: String, Codable, Sendable, CaseIterable {
        case hidden, dimmed
    }

    /// Weekday keys for `weekendDays`, in `Calendar` weekday order (1 = Sunday).
    public static let weekdayKeys = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

    /// Day numbers.
    public var font: FontSpec
    public var color: String
    public var titleFormat: TitleFormat?
    public var titleCase: TitleCase?
    /// Defaults to `font`, bold, 1.6× larger.
    public var titleFont: FontSpec?
    public var titleColor: String?
    public var titleAlign: TextAlign?
    public var weekdays: WeekdayStyle?
    /// Defaults to `font`, semibold.
    public var weekdayFont: FontSpec?
    public var weekdayColor: String?
    public var weekStart: WeekStart?
    /// Columns drawn in `weekendColor` (numbers and their weekday letter), e.g. ["fri", "sat"].
    public var weekendDays: [String]?
    public var weekendColor: String?
    public var todayStyle: TodayStyle?
    /// Fill, ring or dot color; defaults to `color`.
    public var todayColor: String?
    /// The number on a filled square or circle; defaults to white.
    public var todayTextColor: String?
    public var otherDays: OtherDays?
    public var rows: Rows?

    public init(font: FontSpec, color: String, titleFormat: TitleFormat? = nil, titleCase: TitleCase? = nil,
                titleFont: FontSpec? = nil, titleColor: String? = nil, titleAlign: TextAlign? = nil,
                weekdays: WeekdayStyle? = nil, weekdayFont: FontSpec? = nil, weekdayColor: String? = nil,
                weekStart: WeekStart? = nil, weekendDays: [String]? = nil, weekendColor: String? = nil,
                todayStyle: TodayStyle? = nil, todayColor: String? = nil, todayTextColor: String? = nil,
                otherDays: OtherDays? = nil) {
        self.font = font
        self.color = color
        self.titleFormat = titleFormat
        self.titleCase = titleCase
        self.titleFont = titleFont
        self.titleColor = titleColor
        self.titleAlign = titleAlign
        self.weekdays = weekdays
        self.weekdayFont = weekdayFont
        self.weekdayColor = weekdayColor
        self.weekStart = weekStart
        self.weekendDays = weekendDays
        self.weekendColor = weekendColor
        self.todayStyle = todayStyle
        self.todayColor = todayColor
        self.todayTextColor = todayTextColor
        self.otherDays = otherDays
    }

    /// The title font in effect.
    public var effectiveTitleFont: FontSpec {
        titleFont ?? FontSpec(family: font.family, size: font.size * 1.6, weight: .bold)
    }

    /// The weekday row font in effect.
    public var effectiveWeekdayFont: FontSpec {
        weekdayFont ?? FontSpec(family: font.family, size: font.size, weight: .semibold)
    }
}

/// Rows of text (ADR-019): events, reminders, prayer times. Each row has a title, an optional
/// detail on the trailing side (a time, a count) and an optional marker. Texts may hold bindings
/// (`{{prayer.fajr}}`). Rows share the frame's height equally.
public struct ListLayer: Codable, Sendable, Equatable {
    public enum Marker: String, Codable, Sendable, CaseIterable {
        case none, dot, circle, check, icon, bar
    }

    public struct Item: Codable, Sendable, Equatable {
        public var title: LocalizedText
        public var detail: LocalizedText?
        /// For `marker: icon`: a whitelisted SF Symbol.
        public var icon: String?
        /// Overrides the marker color for this row.
        public var color: String?
        /// A condition: the row is a checkbox, ticked and faded while it holds (`{{tasks.1.done}}`, ADR-028).
        public var done: String?
        /// ADR-029: a smaller line under the title (a calendar name), and a second detail under the first
        /// (an end time). Both may hold bindings.
        public var subtitle: LocalizedText?
        public var detail2: LocalizedText?

        public init(title: LocalizedText, detail: LocalizedText? = nil, icon: String? = nil, color: String? = nil) {
            self.title = title
            self.detail = detail
            self.icon = icon
            self.color = color
        }
    }

    public static let maxItems = 8

    public var items: [Item]
    public var font: FontSpec
    public var color: String
    public var detailColor: String?
    public var marker: Marker?
    public var markerColor: String?
    /// A thin line between rows.
    public var dividerColor: String?

    public init(items: [Item], font: FontSpec, color: String, detailColor: String? = nil, marker: Marker? = nil,
                markerColor: String? = nil, dividerColor: String? = nil) {
        self.items = items
        self.font = font
        self.color = color
        self.detailColor = detailColor
        self.marker = marker
        self.markerColor = markerColor
        self.dividerColor = dividerColor
    }
}

/// A horizontal progress bar (ADR-019), continuous or in segments. With `mirror` it fills from
/// the right.
public struct ProgressBarLayer: Codable, Sendable, Equatable {
    /// A number 0…1 or a binding to one (`{{battery.level}}`).
    public var progress: String
    public var color: String
    public var trackColor: String?
    /// 2…20 separate segments; nil or 1 = one continuous bar.
    public var segments: Int?
    /// Defaults to half the bar's height (pill ends).
    public var cornerRadius: Double?
    /// Fills from the bottom up: a volume or brightness slider (ADR-027).
    public var vertical: Bool?
    /// A round knob at the fill's end (ADR-029).
    public var knob: ProgressKnob?

    public init(progress: String, color: String, trackColor: String? = nil, segments: Int? = nil, cornerRadius: Double? = nil,
                vertical: Bool? = nil) {
        self.vertical = vertical
        self.progress = progress
        self.color = color
        self.trackColor = trackColor
        self.segments = segments
        self.cornerRadius = cornerRadius
    }
}

// MARK: - Calendar layout

/// The month grid a `calendarMonth` draws, computed without SwiftUI so it can be tested.
public struct CalendarMonthLayout: Equatable, Sendable {
    public struct Cell: Equatable, Sendable {
        /// Day of the month; nil for an empty cell.
        public let day: Int?
        /// A day of the previous or next month (`otherDays: dimmed`).
        public let isOtherMonth: Bool
        public let isToday: Bool
        public let isWeekend: Bool
    }

    public let title: String
    /// Weekday labels in column order (left to right before mirroring).
    public let weekdays: [String]
    /// Which columns are weekend days.
    public let weekendColumns: [Bool]
    /// Rows of 7 cells.
    public let rows: [[Cell]]

    public init(layer: CalendarMonthLayer, date: Date, timeZone: TimeZone, localeIdentifier: String) {
        let locale = Locale(identifier: localeIdentifier)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        switch layer.weekStart ?? .locale {
        case .locale: break   // the locale sets it (Saturday for ar_EG, Sunday for en_US)
        case .saturday: calendar.firstWeekday = 7
        case .sunday: calendar.firstWeekday = 1
        case .monday: calendar.firstWeekday = 2
        }

        // Title.
        let format = layer.titleFormat ?? .short
        if format == .none {
            title = ""
        } else {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.calendar = calendar
            formatter.setLocalizedDateFormatFromTemplate(format.rawValue)
            let text = formatter.string(from: date)
            switch layer.titleCase ?? .upper {
            case .upper: title = text.uppercased(with: locale)
            case .lower: title = text.lowercased(with: locale)
            case .natural: title = text
            }
        }

        // Weekday columns.
        let symbols: [String]
        switch layer.weekdays ?? .narrow {
        case .short: symbols = calendar.shortStandaloneWeekdaySymbols
        // "Mo Tu": the short name cut to two letters (Arabic keeps its short name).
        case .two: symbols = calendar.shortStandaloneWeekdaySymbols.map { localeIdentifier.hasPrefix("ar") ? $0 : String($0.prefix(2)) }
        default: symbols = calendar.veryShortStandaloneWeekdaySymbols
        }
        let weekend = Set((layer.weekendDays ?? []).compactMap { CalendarMonthLayer.weekdayKeys.firstIndex(of: $0.lowercased()) })
        let columns = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }   // 0 = Sunday
        weekdays = (layer.weekdays ?? .narrow) == .none ? [] : columns.map { symbols[$0] }
        weekendColumns = columns.map { weekend.contains($0) }

        // Days.
        var cells: [Cell] = []
        guard let month = calendar.dateInterval(of: .month, for: date),
              let count = calendar.range(of: .day, in: .month, for: date)?.count else {
            rows = []
            return
        }
        let today = calendar.component(.day, from: date)
        let leading = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
        let dimmed = (layer.otherDays ?? .hidden) == .dimmed
        let previousCount = calendar.date(byAdding: .day, value: -1, to: month.start)
            .flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 30
        for index in 0..<leading {
            let day = previousCount - leading + 1 + index
            cells.append(Cell(day: dimmed ? day : nil, isOtherMonth: true, isToday: false, isWeekend: weekendColumns[index]))
        }
        for day in 1...count {
            cells.append(Cell(day: day, isOtherMonth: false, isToday: day == today, isWeekend: weekendColumns[cells.count % 7]))
        }
        var next = 1
        while cells.count % 7 != 0 {
            cells.append(Cell(day: dimmed ? next : nil, isOtherMonth: true, isToday: false, isWeekend: weekendColumns[cells.count % 7]))
            next += 1
        }
        let all = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
        // ADR-029: a week strip shows the week holding today (and the next for two weeks), with the
        // neighboring months' days, since a week crosses months.
        switch layer.rows ?? .month {
        case .month:
            rows = all
        case .week, .twoWeeks:
            rows = Self.weekRows(count: layer.rows == .week ? 1 : 2, calendar: calendar, date: date, weekend: weekendColumns)
        }
    }

    /// `count` weeks from the one holding `date`.
    static func weekRows(count: Int, calendar: Calendar, date: Date, weekend: [Bool]) -> [[Cell]] {
        let today = calendar.startOfDay(for: date)
        let offset = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        let firstOfWeek = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
        return (0..<count).map { row in
            (0..<7).map { column in
                let day = calendar.date(byAdding: .day, value: row * 7 + column, to: firstOfWeek) ?? firstOfWeek
                let sameMonth = calendar.isDate(day, equalTo: date, toGranularity: .month)
                return Cell(day: calendar.component(.day, from: day), isOtherMonth: !sameMonth,
                            isToday: calendar.isDate(day, inSameDayAs: today), isWeekend: weekend[column])
            }
        }
    }
}

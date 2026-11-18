import Foundation
#if os(iOS)
import EventKit
#endif

/// One task of the Tasks tab (ADR-028). On iOS it is a reminder in the "Widget Studio" list, so the
/// widget extension reads and completes it itself, with no App Group. On Android it is a row of a
/// local database. `list` is the user's own category: EventKit has no field for it, so it travels
/// in the reminder's `location`.
public struct TaskItem: Codable, Sendable, Equatable, Identifiable {
    public enum Priority: Int, Codable, CaseIterable, Sendable {
        case none, low, medium, high
    }

    public var id: String
    public var title: String
    public var due: Date?
    /// The due date has a time of day.
    public var hasTime: Bool
    /// Notify at the due time.
    public var reminds: Bool
    public var priority: Priority
    public var list: String?
    public var done: Bool
    public var doneAt: Date?

    public init(id: String = UUID().uuidString, title: String, due: Date? = nil, hasTime: Bool = false, reminds: Bool = false,
                priority: Priority = .none, list: String? = nil, done: Bool = false, doneAt: Date? = nil) {
        self.id = id
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.reminds = reminds
        self.priority = priority
        self.list = list
        self.done = done
        self.doneAt = doneAt
    }
}

/// Pure logic of tasks; `TaskFormat` in `Tasks.kt` must behave the same.
public enum TaskFormat {
    public enum Filter: String, CaseIterable, Sendable {
        case today, upcoming, done
    }

    /// Rows a widget can show.
    public static let rows = 6

    /// Open tasks: by due date, undated last, then the highest priority, then the title.
    public static func sorted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { first, second in
            switch (first.due, second.due) {
            case (let a?, let b?) where a != b: return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            if first.priority != second.priority { return first.priority.rawValue > second.priority.rawValue }
            return first.title < second.title
        }
    }

    /// Open and due today or overdue.
    static func isDueToday(_ task: TaskItem, now: Date, calendar: Calendar) -> Bool {
        guard !task.done, let due = task.due else { return false }
        return due < calendar.startOfDay(for: now) || calendar.isDate(due, inSameDayAs: now)
    }

    public static func filter(_ tasks: [TaskItem], _ filter: Filter, now: Date, calendar: Calendar = .current) -> [TaskItem] {
        switch filter {
        case .today: sorted(tasks.filter { isDueToday($0, now: now, calendar: calendar) })
        case .upcoming: sorted(tasks.filter { !$0.done && !isDueToday($0, now: now, calendar: calendar) })
        case .done: tasks.filter(\.done).sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
        }
    }

    /// "Today 14:30", "Tomorrow", "Nov 7"; digits Latin, like every other value.
    public static func dueText(_ task: TaskItem, now: Date, calendar: Calendar, language: String) -> String {
        guard let due = task.due else { return "" }
        let arabic = language.hasPrefix("ar")
        var parts: [String] = []
        let day = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: due)).day ?? 0
        switch day {
        case 0: parts.append(arabic ? "اليوم" : "Today")
        case 1: parts.append(arabic ? "غدًا" : "Tomorrow")
        case ..<0: parts.append(arabic ? "متأخرة" : "Overdue")
        default:
            let locale = arabic ? "ar_EG@numbers=latn" : "en_US"
            parts.append(FormatterCache.date("d MMM", locale: locale, zone: calendar.timeZone).string(from: due))
        }
        if task.hasTime, day >= 0 { parts.append(FormatterCache.date("HH:mm", locale: "en_US_POSIX", zone: calendar.timeZone).string(from: due)) }
        return parts.joined(separator: " ")
    }

    private static func count(_ value: Int) -> BindingResolver.Value { .number(Double(value), display: String(value)) }

    /// The catalog's `tasks.*` values. Rows hold the open tasks, then today's done ones, so a ticked
    /// box stays ticked on the widget until the day ends. Empty rows are empty, never "--".
    public static func values(_ tasks: [TaskItem], now: Date, calendar: Calendar, language: String) -> [String: BindingResolver.Value] {
        let open = sorted(tasks.filter { !$0.done })
        let dueToday = open.filter { isDueToday($0, now: now, calendar: calendar) }
        let doneToday = tasks.filter { task in task.done && task.doneAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
            .sorted { ($0.doneAt ?? .distantPast) < ($1.doneAt ?? .distantPast) }
        var live: [String: BindingResolver.Value] = [
            "tasks.list": .text(open.map(\.title).joined(separator: "\n")),
            "tasks.today.count": count(dueToday.count),
            "tasks.open.count": count(open.count),
            "tasks.done.count": count(doneToday.count),
        ]
        let total = doneToday.count + dueToday.count
        let share = total == 0 ? 0 : Double(doneToday.count) / Double(total)
        live["tasks.progress"] = .number(share, display: String(Int((share * 100).rounded())))
        live["tasks.next.title"] = .text(open.first?.title ?? (language.hasPrefix("ar") ? "لا مهام" : "No tasks"))
        live["tasks.next.due"] = .text(open.first.map { dueText($0, now: now, calendar: calendar, language: language) } ?? "")
        live["tasks.next.id"] = .text(open.first?.id ?? "")
        let shown = Array((open + doneToday).prefix(rows))
        for row in 1...rows {
            let task = row <= shown.count ? shown[row - 1] : nil
            live["tasks.\(row).title"] = .text(task?.title ?? "")
            live["tasks.\(row).due"] = .text(task.map { dueText($0, now: now, calendar: calendar, language: language) } ?? "")
            live["tasks.\(row).done"] = .text(task?.done == true ? "1" : "0")
            live["tasks.\(row).id"] = .text(task?.id ?? "")
        }
        return live
    }
}

#if os(iOS)
/// Tasks in Apple Reminders, in a list called "Widget Studio" (ADR-028). The app and the widget
/// extension both use it: Reminders is the one store they share without an App Group.
public final class TaskStore: @unchecked Sendable {
    public static let listName = "Widget Studio"

    private let store = EKEventStore()

    public init() {}

    public static var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    /// Asked already and refused: only Settings can change it now.
    public static var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        return status == .denied || status == .restricted || status == .writeOnly
    }

    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    /// The app's list; created once, in the account new reminders go to.
    private func list(creating: Bool) throws -> EKCalendar? {
        if let found = store.calendars(for: .reminder).first(where: { $0.title == Self.listName }) { return found }
        guard creating else { return nil }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = Self.listName
        guard let source = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .local }) else { throw CocoaError(.fileWriteUnknown) }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    public func load() async -> [TaskItem] {
        guard Self.isAuthorized, let list = try? list(creating: false) else { return [] }
        let predicate = store.predicateForReminders(in: [list])
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.item))
            }
        }
    }

    private static func item(_ reminder: EKReminder) -> TaskItem {
        let components = reminder.dueDateComponents
        let priority: TaskItem.Priority = switch reminder.priority {
        case 1...4: .high
        case 5: .medium
        case 6...9: .low
        default: .none
        }
        return TaskItem(id: reminder.calendarItemIdentifier, title: reminder.title ?? "",
                        due: components.flatMap { Calendar.current.date(from: $0) }, hasTime: components?.hour != nil,
                        reminds: !(reminder.alarms ?? []).isEmpty, priority: priority, list: reminder.location,
                        done: reminder.isCompleted, doneAt: reminder.completionDate)
    }

    /// Inserts or updates; returns the saved task, with the id Reminders gave a new one.
    @discardableResult
    public func save(_ task: TaskItem) throws -> TaskItem {
        let reminder = (store.calendarItem(withIdentifier: task.id) as? EKReminder) ?? EKReminder(eventStore: store)
        if reminder.calendar == nil { reminder.calendar = try list(creating: true) }
        reminder.title = task.title
        reminder.location = task.list
        reminder.priority = switch task.priority {
        case .high: 1
        case .medium: 5
        case .low: 9
        case .none: 0
        }
        if let due = task.due {
            let fields: Set<Calendar.Component> = task.hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
            reminder.dueDateComponents = Calendar.current.dateComponents(fields, from: due)
        } else {
            reminder.dueDateComponents = nil
        }
        for alarm in reminder.alarms ?? [] { reminder.removeAlarm(alarm) }
        // Reminders itself delivers the notification, so the app needs no notification permission.
        if task.reminds, let due = task.due { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
        reminder.isCompleted = task.done
        try store.save(reminder, commit: true)
        return Self.item(reminder)
    }

    public func delete(id: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        try store.remove(reminder, commit: true)
    }

    /// Ticks or unticks a task; what the widget's checkbox runs, in the extension.
    public func toggle(id: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        reminder.isCompleted.toggle()
        try store.save(reminder, commit: true)
    }
}
#endif

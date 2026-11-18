/// One type per template, so the widget extension can declare one `StaticConfiguration`
/// widget per template (`TemplateWidget<ID>`, ADR-013): a `Widget` must have `init()`, so the
/// template can't be an instance property. `TemplateIDs.all` must list every template in the
/// library (unit-tested), in library order.
public protocol TemplateIdentity {
    static var id: String { get }
}

public enum TemplateIDs {
    // Time
    public enum ClockAnalog: TemplateIdentity { public static let id = "mono.clock.analog" }
    public enum ClockDotAnalog: TemplateIdentity { public static let id = "mono.clock.dotAnalog" }
    public enum ClockDigital: TemplateIdentity { public static let id = "mono.clock.digital" }
    public enum DateBig: TemplateIdentity { public static let id = "mono.date.big" }
    public enum DateDayZone: TemplateIdentity { public static let id = "mono.date.dayZone" }
    public enum YearDots: TemplateIdentity { public static let id = "mono.year.dots" }
    // Weather
    public enum WeatherHiLo: TemplateIdentity { public static let id = "mono.weather.hiLo" }
    public enum WeatherTemp: TemplateIdentity { public static let id = "mono.weather.temp" }
    public enum WeatherForecast: TemplateIdentity { public static let id = "mono.weather.forecast" }
    public enum WeatherArt: TemplateIdentity { public static let id = "mono.weather.art" }
    public enum LocationCoords: TemplateIdentity { public static let id = "mono.location.coords" }
    // Health
    public enum StepsStreak: TemplateIdentity { public static let id = "mono.steps.streak" }
    public enum StepsMonth: TemplateIdentity { public static let id = "mono.steps.month" }
    public enum SleepWeek: TemplateIdentity { public static let id = "mono.sleep.week" }
    // Prayer
    public enum PrayerNext: TemplateIdentity { public static let id = "mono.prayer.next" }
    public enum PrayerDay: TemplateIdentity { public static let id = "mono.prayer.day" }
    public enum Qibla: TemplateIdentity { public static let id = "mono.qibla" }
    // Countdown
    public enum FocusToday: TemplateIdentity { public static let id = "mono.focus.today" }
    public enum CountdownRed: TemplateIdentity { public static let id = "mono.countdown.red" }
    public enum CountdownTrip: TemplateIdentity { public static let id = "mono.countdown.trip" }
    public enum Stopwatch: TemplateIdentity { public static let id = "mono.stopwatch" }
    // Photo
    public enum PhotoSquare: TemplateIdentity { public static let id = "mono.photo.square" }
    public enum PhotoCircle: TemplateIdentity { public static let id = "mono.photo.circle" }
    public enum PhotoHalftone: TemplateIdentity { public static let id = "mono.photo.halftone" }
    public enum MusicCard: TemplateIdentity { public static let id = "mono.music.card" }
    // Tiles
    public enum TilesPills2: TemplateIdentity { public static let id = "mono.tiles.pills2" }
    public enum TilesPills4: TemplateIdentity { public static let id = "mono.tiles.pills4" }
    public enum TilesRound: TemplateIdentity { public static let id = "mono.tiles.round" }
    public enum TilesHero: TemplateIdentity { public static let id = "mono.tiles.hero" }
    // Live controls (ADR-027): fixed widgets, so they also reach the home screen without an App Group.
    public enum MediaPlayer: TemplateIdentity { public static let id = "mono.media.player" }
    public enum ControlCenter: TemplateIdentity { public static let id = "mono.control.center" }
    public enum BatteryMood: TemplateIdentity { public static let id = "mono.battery.mood" }
    // Counters
    public enum CounterTasbeeh: TemplateIdentity { public static let id = "mono.counter.tasbeeh" }
    public enum TimerFocus: TemplateIdentity { public static let id = "mono.timer.focus" }
    // Tasks (ADR-028)
    public enum TasksSmall: TemplateIdentity { public static let id = "mono.tasks.small" }
    public enum TasksMedium: TemplateIdentity { public static let id = "mono.tasks.medium" }
    public enum TasksLarge: TemplateIdentity { public static let id = "mono.tasks.large" }

    /// Every identity, in library order. The extension's widget bundles use the same order.
    public static let all: [any TemplateIdentity.Type] = [
        ClockAnalog.self, ClockDotAnalog.self, ClockDigital.self, DateBig.self, DateDayZone.self, YearDots.self,
        WeatherHiLo.self, WeatherTemp.self, WeatherForecast.self, WeatherArt.self, LocationCoords.self,
        StepsStreak.self, StepsMonth.self, SleepWeek.self,
        PrayerNext.self, PrayerDay.self, Qibla.self,
        FocusToday.self, CountdownRed.self, CountdownTrip.self, Stopwatch.self,
        PhotoSquare.self, PhotoCircle.self, PhotoHalftone.self, MusicCard.self,
        TilesPills2.self, TilesPills4.self, TilesRound.self, TilesHero.self, MediaPlayer.self, ControlCenter.self, BatteryMood.self,
        CounterTasbeeh.self, TimerFocus.self,
        TasksSmall.self, TasksMedium.self, TasksLarge.self,
    ]
}

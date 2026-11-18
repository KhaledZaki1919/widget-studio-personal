/// SF Symbols a spec may use (brief §4.4), each with the Material Symbols name the Android
/// renderer will use later (M7). Keep entries sorted by area.
public enum Icons {
    public static let whitelist: [String: String] = [
        // Weather
        "sun.max.fill": "sunny", "moon.fill": "dark_mode", "moon.stars.fill": "bedtime",
        "cloud.fill": "cloud", "cloud.sun.fill": "partly_cloudy_day", "cloud.moon.fill": "partly_cloudy_night",
        "cloud.rain.fill": "rainy", "cloud.drizzle.fill": "rainy_light", "cloud.heavyrain.fill": "rainy_heavy",
        "cloud.bolt.rain.fill": "thunderstorm", "cloud.snow.fill": "weather_snowy", "cloud.fog.fill": "foggy",
        "wind": "air", "sunrise.fill": "wb_twilight", "sunset.fill": "wb_twilight", "thermometer.medium": "thermostat",
        "humidity.fill": "humidity_percentage", "sun.haze.fill": "wb_sunny",
        // Time
        "clock": "schedule", "clock.fill": "schedule", "alarm.fill": "alarm", "timer": "timer",
        "stopwatch": "timer", "hourglass": "hourglass_empty", "calendar": "calendar_today", "globe": "public",
        // Health and focus
        "figure.walk": "directions_walk", "figure.run": "directions_run", "heart.fill": "favorite",
        "bed.double.fill": "bed", "flame.fill": "local_fire_department", "brain.head.profile": "psychology",
        "drop.fill": "water_drop",
        // Prayer and location
        "location.fill": "location_on", "location.north.fill": "navigation", "safari.fill": "explore",
        "moon.haze.fill": "nights_stay", "building.columns.fill": "mosque", "map.fill": "map",
        "mountain.2.fill": "landscape", "arrow.up.and.down": "height",
        // Device and tiles
        "battery.100": "battery_full", "battery.75": "battery_5_bar", "battery.50": "battery_3_bar",
        "battery.25": "battery_2_bar", "bolt.fill": "bolt", "wifi": "wifi", "antenna.radiowaves.left.and.right": "cell_tower",
        "airplane": "flight", "flashlight.on.fill": "flashlight_on", "moon.circle.fill": "dark_mode",
        "personalhotspot": "wifi_tethering", "circle.lefthalf.filled": "contrast", "lock.rotation": "screen_lock_rotation",
        "plus.forwardslash.minus": "calculate", "tv.fill": "tv", "wave.3.right": "nfc",
        "qrcode": "qr_code", "camera.fill": "photo_camera", "mic.fill": "mic",
        "mic.slash.fill": "mic_off", "record.circle": "radio_button_checked", "rotate.right": "screen_rotation",
        "house.fill": "home", "music.note": "music_note", "play.fill": "play_arrow", "pause.fill": "pause",
        "headphones": "headphones", "phone.fill": "call", "message.fill": "chat", "link": "link",
        "app.fill": "apps", "square.grid.2x2.fill": "grid_view", "bolt.horizontal.fill": "electric_bolt",
        "dot.radiowaves.left.and.right": "bluetooth", "leaf.fill": "eco", "lightbulb.fill": "lightbulb", "lock.fill": "lock",
        "power": "power_settings_new", "fan.fill": "mode_fan", "list.bullet": "format_list_bulleted",
        // Media and sound (ADR-027)
        "stop.fill": "stop", "forward.end.fill": "skip_next", "backward.end.fill": "skip_previous",
        "forward.fill": "fast_forward", "backward.fill": "fast_rewind", "repeat": "repeat", "shuffle": "shuffle",
        "speaker.fill": "volume_mute", "speaker.wave.2.fill": "volume_down", "speaker.wave.3.fill": "volume_up",
        "speaker.slash.fill": "volume_off", "bell.fill": "notifications", "bell.slash.fill": "notifications_off",
        "sun.min.fill": "brightness_low", "minus.circle.fill": "do_not_disturb_on",
        "chevron.up": "keyboard_arrow_up", "chevron.down": "keyboard_arrow_down",
        // Counters and actions
        "plus": "add", "minus": "remove", "plus.circle.fill": "add_circle", "arrow.counterclockwise": "replay",
        "arrow.triangle.2.circlepath": "sync",
        "arrow.up": "arrow_upward", "arrow.down": "arrow_downward",
        "checkmark": "check", "checkmark.circle.fill": "check_circle", "star.fill": "star", "circle.fill": "circle",
        "circle": "radio_button_unchecked", "hand.tap.fill": "touch_app", "sparkles": "auto_awesome",
        // ADR-029: the symbols image-to-widget needed (PDF "icons and actions")
        "magnifyingglass": "search", "cart.fill": "shopping_cart", "bag.fill": "shopping_bag", "wallet.pass.fill": "wallet",
        "creditcard.fill": "credit_card", "dollarsign.circle.fill": "paid", "chart.line.uptrend.xyaxis": "trending_up",
        "chart.bar.fill": "bar_chart", "arrow.right": "arrow_forward", "arrow.left": "arrow_back", "arrow.up.right": "north_east",
        "arrow.down.right": "south_east", "chevron.right": "chevron_right", "chevron.left": "chevron_left",
        "airpods": "earbuds", "airpodspro": "earbuds", "faceid": "face", "iphone": "smartphone", "applewatch": "watch",
        "bluetooth": "bluetooth", "shoeprints.fill": "footprint", "waveform.path.ecg": "ecg_heart", "heart": "favorite",
        "bell.badge.fill": "notifications_active", "envelope.fill": "mail", "rectangle.dashed.badge.record": "screen_record",
        "captions.bubble": "closed_caption", "captions.bubble.fill": "closed_caption", "sparkle": "auto_awesome",
        "mic.circle.fill": "mic", "waveform": "graphic_eq", "music.note.list": "queue_music", "speaker.wave.1.fill": "volume_down",
        "gearshape.fill": "settings", "person.fill": "person", "car.fill": "directions_car", "photo": "image",
        "photo.fill": "image", "xmark": "close", "ellipsis": "more_horiz", "info.circle": "info", "alarm": "alarm",
        "exclamationmark.triangle.fill": "warning", "umbrella.fill": "umbrella", "aqi.medium": "airwave",
        "wifi.slash": "wifi_off", "battery.0": "battery_0_bar",
        // Outline weather, for `style: outline` and the hourly forecast (ADR-029)
        "cloud": "cloud", "sun.max": "sunny", "moon": "dark_mode", "cloud.sun": "partly_cloudy_day",
        "cloud.moon": "partly_cloudy_night", "cloud.rain": "rainy", "cloud.drizzle": "rainy_light",
        "cloud.heavyrain": "rainy_heavy", "cloud.bolt.rain": "thunderstorm", "cloud.snow": "weather_snowy", "cloud.fog": "foggy",
    ]

    public static func isAllowed(_ symbol: String) -> Bool {
        whitelist[symbol] != nil
    }

    /// ADR-029: any SF Symbol name may be used: lower-case words and digits joined by dots, at most 60
    /// characters. Unknown names draw their closest known symbol (`IconRendering.symbol`); Android maps
    /// them to Material Symbols by their words (Icons.kt).
    public static func isSymbolName(_ symbol: String) -> Bool {
        guard !symbol.isEmpty, symbol.count <= 60, !symbol.hasPrefix("."), !symbol.hasSuffix("."), !symbol.contains("..") else { return false }
        return symbol.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "." }
    }

    /// The symbol for a style: `outline` drops `.fill`, `fill` adds it when that variant is known.
    public static func styled(_ symbol: String, _ style: IconStyle?) -> String {
        switch style {
        case .outline?:
            let parts = symbol.split(separator: ".").filter { $0 != "fill" }
            return parts.joined(separator: ".")
        case .fill?:
            if symbol.hasSuffix(".fill") { return symbol }
            let filled = symbol + ".fill"
            return whitelist[filled] != nil || !isAllowed(symbol) ? filled : symbol
        case nil:
            return symbol
        }
    }
}

import Foundation

/// A theme's colors as hex strings (Kit stays UI-free; the app maps to Color).
public struct ThemePalette: Codable, Sendable, Equatable {
    public var calmHex: String
    public var watchHex: String
    public var warningHex: String
    public var criticalHex: String
    public var accentHex: String

    public init(calmHex: String, watchHex: String, warningHex: String, criticalHex: String, accentHex: String) {
        self.calmHex = calmHex
        self.watchHex = watchHex
        self.warningHex = warningHex
        self.criticalHex = criticalHex
        self.accentHex = accentHex
    }
}

/// Curated theme set (theme-palette-redesign 2026-06-13) — 6 strong-identity 먹방 rooms + custom.
/// The *colors* (atmosphere + per-theme risk ramp) live app-side in `ThemeMood` (ADR-0015); this
/// enum + `presetPalette` carry the accent (for `.tint`) + representative risk hexes used by the
/// Settings threshold sliders. The dark-value accent is the canonical one.
public enum Theme: String, Codable, Sendable, CaseIterable, Identifiable {
    case charcoal   // 숯불 — grill ember, dark-first (default)
    case matcha     // 말차 — tea-ceremony calm green
    case hanji      // 한지 — light-first mulberry paper + 인주 seal
    case ganjang    // 간장 — fermented soy + 단청 jewel accents
    case obang      // 오방 — Korea's five cardinal colors
    case mono       // 흑백 — achromatic, instrument-grade
    case custom     // user accent

    public var id: String { rawValue }

    /// Legacy raw values from the old set map onto the nearest new room so persisted settings
    /// don't break (Codable decodes by rawValue; this maps the retired ones).
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "classic": self = .charcoal
        case "mint":    self = .matcha
        case "sunset":  self = .charcoal
        default:        self = Theme(rawValue: raw) ?? .charcoal
        }
    }

    /// User-facing names. The case names keep their 먹방/Korean-culture origin (숯불/말차/…),
    /// but the labels are descriptive English for global distribution — each maps to the room's
    /// visible identity (ember orange, matcha green, paper, jade, ocean blue, monochrome).
    public var label: String {
        switch self {
        case .charcoal: return "Ember"
        case .matcha:   return "Matcha"
        case .hanji:    return "Paper"
        case .ganjang:  return "Jade"
        case .obang:    return "Ocean"
        case .mono:     return "Mono"
        case .custom:   return "Custom"
        }
    }

    /// Preset palette — accent (canonical dark value) + representative risk hexes (dark) used by
    /// the Settings threshold sliders. The live UI risk ramp comes from `ThemeMood`, not here.
    public var presetPalette: ThemePalette {
        switch self {
        case .charcoal:
            return ThemePalette(calmHex: "#5BA88A", watchHex: "#D8A92E", warningHex: "#E08B3A", criticalHex: "#E0573F", accentHex: "#F76707")
        case .matcha:
            return ThemePalette(calmHex: "#7BC07F", watchHex: "#C4BC4A", warningHex: "#C99A52", criticalHex: "#C8525E", accentHex: "#8FCB6B")
        case .hanji:
            return ThemePalette(calmHex: "#7AAE8C", watchHex: "#C7A848", warningHex: "#CE9456", criticalHex: "#D04E50", accentHex: "#E85C44")
        case .ganjang:   // accent = 단청 jade (양록); risk stays its own warm scale (danger=red).
            return ThemePalette(calmHex: "#5C9A6E", watchHex: "#D8B042", warningHex: "#D89254", criticalHex: "#E0594A", accentHex: "#46C39A")
        case .obang:
            return ThemePalette(calmHex: "#5ABF93", watchHex: "#F0C840", warningHex: "#E89A48", criticalHex: "#E85560", accentHex: "#4FA0E0")
        case .mono:   // achromatic grey ramp, but critical = instrument-red danger zone (matches ThemeMood).
            return ThemePalette(calmHex: "#6E747C", watchHex: "#9097A0", warningHex: "#B6BCC4", criticalHex: "#D6534C", accentHex: "#C8CCD2")
        case .custom:
            return ThemePalette(calmHex: "#5BA88A", watchHex: "#C9A227", warningHex: "#D08A3E", criticalHex: "#C23B4E", accentHex: "#0A84FF")
        }
    }
}

/// Customizable warning/critical thresholds (percent of a window consumed).
public struct RiskThresholds: Codable, Sendable, Equatable {
    public var warning: Double
    public var critical: Double
    public init(warning: Double, critical: Double) {
        self.warning = warning
        self.critical = critical
    }
    public static let `default` = RiskThresholds(warning: 70, critical: 90)
}

/// Per-surface + per-event notification toggles (TokenEater granularity).
public struct NotificationSettings: Codable, Sendable, Equatable {
    // surfaces
    public var fiveHour: Bool
    public var sevenDay: Bool
    public var sonnet: Bool
    // event types
    public var escalation: Bool
    public var recovery: Bool
    public var pacing: Bool
    public var reset: Bool
    public var extraCredit: Bool
    public var tokenExpiry: Bool

    public init(fiveHour: Bool, sevenDay: Bool, sonnet: Bool, escalation: Bool, recovery: Bool,
                pacing: Bool, reset: Bool, extraCredit: Bool, tokenExpiry: Bool) {
        self.fiveHour = fiveHour; self.sevenDay = sevenDay; self.sonnet = sonnet
        self.escalation = escalation; self.recovery = recovery; self.pacing = pacing
        self.reset = reset; self.extraCredit = extraCredit; self.tokenExpiry = tokenExpiry
    }

    public static let `default` = NotificationSettings(
        fiveHour: true, sevenDay: true, sonnet: false,
        escalation: true, recovery: true, pacing: true, reset: true, extraCredit: false, tokenExpiry: true
    )
}

/// The user's full settings (theme + thresholds + notifications + glass), persisted.
public struct AppSettings: Codable, Sendable, Equatable {
    public var theme: Theme
    public var customPalette: ThemePalette
    public var thresholds: RiskThresholds
    public var notifications: NotificationSettings
    public var temperament: Temperament
    /// Popover behind-window blur **veil** opacity (0…1). Lower = more see-through desktop +
    /// softer blur; higher = more frosted. Applied to `GlassPanel`'s `.behindWindow` layer alpha
    /// (ADR-0018). Content stays crisp regardless (it sits above the veil). User-tunable.
    public var glassOpacity: Double

    /// The shipped default blur veil — was a hard-coded constant in `GlassPanel`, now the default
    /// for the user-tunable `glassOpacity` (so existing behavior is unchanged until adjusted).
    public static let defaultGlassOpacity: Double = 0.70

    public init(theme: Theme, customPalette: ThemePalette, thresholds: RiskThresholds,
                notifications: NotificationSettings, temperament: Temperament = .balanced,
                glassOpacity: Double = AppSettings.defaultGlassOpacity) {
        self.theme = theme
        self.customPalette = customPalette
        self.thresholds = thresholds
        self.notifications = notifications
        self.temperament = temperament
        self.glassOpacity = glassOpacity
    }

    private enum CodingKeys: String, CodingKey {
        case theme, customPalette, thresholds, notifications, temperament, glassOpacity
    }

    /// Forgiving decode: any missing field falls back to its default, so adding a new setting
    /// (like `glassOpacity`) never invalidates an older persisted `settings.json` and silently
    /// wipes every other preference. (Synthesized decode would throw on the first missing key.)
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        theme = try c.decodeIfPresent(Theme.self, forKey: .theme) ?? .charcoal
        customPalette = try c.decodeIfPresent(ThemePalette.self, forKey: .customPalette) ?? Theme.custom.presetPalette
        thresholds = try c.decodeIfPresent(RiskThresholds.self, forKey: .thresholds) ?? .default
        notifications = try c.decodeIfPresent(NotificationSettings.self, forKey: .notifications) ?? .default
        temperament = try c.decodeIfPresent(Temperament.self, forKey: .temperament) ?? .balanced
        glassOpacity = try c.decodeIfPresent(Double.self, forKey: .glassOpacity) ?? AppSettings.defaultGlassOpacity
    }

    /// The active palette (preset, or custom colors when theme == .custom).
    public var palette: ThemePalette {
        theme == .custom ? customPalette : theme.presetPalette
    }

    public static let `default` = AppSettings(
        theme: .charcoal,
        customPalette: Theme.custom.presetPalette,
        thresholds: .default,
        notifications: .default
    )
}

/// Persists `AppSettings` to a JSON file. Directory injectable for tests.
public struct SettingsStore: Sendable {
    public static let fileName = "settings.json"
    private let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let support = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.directory = support.appendingPathComponent("TokenMukbang", isDirectory: true)
        }
    }

    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    public func load() -> AppSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return .default }
        return settings
    }

    public func save(_ settings: AppSettings) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

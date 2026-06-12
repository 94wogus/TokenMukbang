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

/// 4 presets + custom (TokenEater theme parity).
public enum Theme: String, Codable, Sendable, CaseIterable, Identifiable {
    case classic, mint, sunset, mono, custom

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .classic: return "Classic"
        case .mint: return "Mint"
        case .sunset: return "Sunset"
        case .mono: return "Mono"
        case .custom: return "Custom"
        }
    }

    /// Preset palette. `.custom` returns a neutral default; the actual custom
    /// colors live in `AppSettings.customPalette`.
    public var presetPalette: ThemePalette {
        switch self {
        case .classic:
            return ThemePalette(calmHex: "#34C759", watchHex: "#FFD60A", warningHex: "#FF9F0A", criticalHex: "#FF453A", accentHex: "#0A84FF")
        case .mint:
            return ThemePalette(calmHex: "#2EE6A8", watchHex: "#A8E62E", warningHex: "#E6C12E", criticalHex: "#E64545", accentHex: "#19C37D")
        case .sunset:
            return ThemePalette(calmHex: "#FFB07C", watchHex: "#FF9F6B", warningHex: "#FF6B6B", criticalHex: "#D7263D", accentHex: "#F75C03")
        case .mono:
            return ThemePalette(calmHex: "#9AA0A6", watchHex: "#BDC1C6", warningHex: "#E8EAED", criticalHex: "#FFFFFF", accentHex: "#C0C0C0")
        case .custom:
            return ThemePalette(calmHex: "#34C759", watchHex: "#FFD60A", warningHex: "#FF9F0A", criticalHex: "#FF453A", accentHex: "#0A84FF")
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

/// The user's full settings (theme + thresholds + notifications), persisted.
public struct AppSettings: Codable, Sendable, Equatable {
    public var theme: Theme
    public var customPalette: ThemePalette
    public var thresholds: RiskThresholds
    public var notifications: NotificationSettings
    public var temperament: Temperament

    public init(theme: Theme, customPalette: ThemePalette, thresholds: RiskThresholds,
                notifications: NotificationSettings, temperament: Temperament = .balanced) {
        self.theme = theme
        self.customPalette = customPalette
        self.thresholds = thresholds
        self.notifications = notifications
        self.temperament = temperament
    }

    /// The active palette (preset, or custom colors when theme == .custom).
    public var palette: ThemePalette {
        theme == .custom ? customPalette : theme.presetPalette
    }

    public static let `default` = AppSettings(
        theme: .classic,
        customPalette: Theme.classic.presetPalette,
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

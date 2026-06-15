import XCTest
@testable import TokenMukbangKit

final class SettingsTests: XCTestCase {
    // MARK: Theme (D1)

    func testThemePresets() {
        XCTAssertEqual(Theme.allCases.count, 7)   // 6 curated rooms + custom
        for theme in Theme.allCases {
            let p = theme.presetPalette
            XCTAssertTrue(p.accentHex.hasPrefix("#"))
            XCTAssertTrue(p.criticalHex.hasPrefix("#"))
            XCTAssertFalse(theme.label.isEmpty)
        }
    }

    func testCustomPaletteUsedWhenCustom() {
        var s = AppSettings.default
        s.theme = .custom
        s.customPalette = ThemePalette(calmHex: "#111111", watchHex: "#222222", warningHex: "#333333", criticalHex: "#444444", accentHex: "#555555")
        XCTAssertEqual(s.palette.accentHex, "#555555")
        s.theme = .matcha
        XCTAssertEqual(s.palette.accentHex, Theme.matcha.presetPalette.accentHex)
    }

    /// Retired theme rawValues decode onto the nearest current room (migration, 2026-06-13).
    func testLegacyThemeMigration() throws {
        let dec = JSONDecoder()
        XCTAssertEqual(try dec.decode(Theme.self, from: Data("\"classic\"".utf8)), .charcoal)
        XCTAssertEqual(try dec.decode(Theme.self, from: Data("\"mint\"".utf8)), .matcha)
        XCTAssertEqual(try dec.decode(Theme.self, from: Data("\"sunset\"".utf8)), .charcoal)
        XCTAssertEqual(try dec.decode(Theme.self, from: Data("\"charcoal\"".utf8)), .charcoal)
    }

    // MARK: Thresholds (D2)

    func testThresholdRiskLevel() {
        let t = RiskThresholds(warning: 70, critical: 90)
        XCTAssertEqual(RiskScorer.level(percent: 95, thresholds: t), .critical)
        XCTAssertEqual(RiskScorer.level(percent: 75, thresholds: t), .warning)
        XCTAssertEqual(RiskScorer.level(percent: 50, thresholds: t), .watch)   // >= 42
        XCTAssertEqual(RiskScorer.level(percent: 10, thresholds: t), .calm)
    }

    // MARK: Notifications (D3)

    func testNotificationDefaults() {
        let n = NotificationSettings.default
        XCTAssertTrue(n.fiveHour)
        XCTAssertTrue(n.escalation)
        XCTAssertFalse(n.sonnet)
        XCTAssertFalse(n.extraCredit)
    }

    // MARK: SettingsStore persistence (D4)

    func testSettingsStoreRoundTrip() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tmk-settings-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SettingsStore(directory: dir)

        XCTAssertEqual(store.load(), .default)   // no file → default

        var s = AppSettings.default
        s.theme = .ganjang
        s.thresholds = RiskThresholds(warning: 60, critical: 85)
        s.notifications.sonnet = true
        store.save(s)

        let loaded = store.load()
        XCTAssertEqual(loaded.theme, .ganjang)
        XCTAssertEqual(loaded.thresholds.warning, 60)
        XCTAssertTrue(loaded.notifications.sonnet)
    }
}

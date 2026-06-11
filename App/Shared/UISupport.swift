import SwiftUI
import ClaudeUsageKit

// UI-only helpers shared by both the app and the widget extension. These are
// presentation glue (hex → Color), not usage/session/risk logic — that all lives
// once in ClaudeUsageKit.

extension Color {
    /// Build a color from a `#RRGGBB` hex string (the form `RiskLevel.hex` emits).
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255.0,
            green: Double((rgb >> 8) & 0xFF) / 255.0,
            blue: Double(rgb & 0xFF) / 255.0
        )
    }
}

extension UsageSnapshot.Window {
    var riskColor: Color { Color(hex: riskHex) }
    var fraction: Double { max(0, min(1, utilization / 100.0)) }
}

extension UsageSnapshot.Session {
    /// Context-fill tint: green → amber → red as the window fills.
    var contextColor: Color {
        guard let f = contextFraction else { return .secondary }
        switch f {
        case ..<0.5: return Color(hex: "#34C759")
        case ..<0.8: return Color(hex: "#FF9F0A")
        default: return Color(hex: "#FF453A")
        }
    }
}

import SwiftUI
import ClaudeUsageKit

// The "Liquid Vitals, Instrument-Grade" design system (docs/design/DESIGN_SYSTEM.md).
// Risk color is resolved HERE (app side), scheme-branched — ClaudeUsageKit stays
// color-free and only emits the RiskLevel rawValue + isOver flag.

/// Scheme-branched risk palette. Risk color rides gauge fill / ring / dot ONLY —
/// never a small readable numeral (DESIGN_SYSTEM §1).
enum RiskTone {
    /// Resolve the risk color for a level rawValue ("calm"/"watch"/"warning"/"critical").
    static func color(level: String, over: Bool, scheme: ColorScheme) -> Color {
        let light = scheme == .light
        if over { return Color(hex: light ? "#A21B3A" : "#FF375F") }
        switch level {
        case "calm":     return Color(hex: light ? "#1E7B34" : "#30D158")
        // Dark watch toned down from neon #FFD60A — it out-shouted critical red.
        case "watch":    return Color(hex: light ? "#946800" : "#D9B225")
        case "warning":  return Color(hex: light ? "#A8521A" : "#FF9F0A")
        case "critical": return Color(hex: light ? "#C0271E" : "#FF453A")
        default:         return Color(hex: light ? "#1E7B34" : "#30D158")
        }
    }

    /// Menu-bar-tuned risk tint. The bar is translucent over a wallpaper and the system
    /// only auto-contrasts *template* glyphs, not custom RGB — so instead of vivid hues +
    /// an outline halo, we use **muted, luminance-pinned** colors branched by the *menu
    /// bar's* effective appearance (not the app's): light bar → deeper/darker so it reads
    /// on bright wallpaper; dark bar → lighter/airy so it reads on dark wallpaper. Saturation
    /// is capped (instrument-grade, not candy); this narrows the low-contrast window to a
    /// sliver without an outline. (Research 2026-06-11; still one resolver — ADR-0015.)
    static func menuBarColor(level: String, over: Bool, scheme: ColorScheme) -> Color {
        let light = scheme == .light
        if over { return Color(hex: light ? "#8E3358" : "#E58FB0") }
        switch level {
        case "calm":     return Color(hex: light ? "#3F7A4E" : "#7FD79A")
        case "watch":    return Color(hex: light ? "#7A6A2E" : "#D9C26A")
        case "warning":  return Color(hex: light ? "#9A5A1E" : "#E0A766")
        case "critical": return Color(hex: light ? "#9A3A33" : "#E08079")
        default:         return Color(hex: light ? "#3F7A4E" : "#7FD79A")
        }
    }

    /// Context-fill (sessions) maps onto the SAME palette via a fraction → level.
    static func contextColor(fraction: Double?, scheme: ColorScheme) -> Color {
        guard let f = fraction else { return Color(.tertiaryLabelColor) }
        let level = f < 0.5 ? "calm" : f < 0.8 ? "warning" : "critical"
        return color(level: level, over: f >= 1.0, scheme: scheme)
    }

    /// A non-color cue glyph for the menu bar / data plane (survives grayscale).
    static func glyph(level: String, over: Bool) -> String? {
        if over { return "✕" }
        if level == "critical" { return "▲" }
        return nil
    }
}

/// Type scale, spacing, radii — the single source the views read from.
enum DS {
    // Spacing (8pt grid)
    static let outer: CGFloat = 16
    static let section: CGFloat = 12
    static let row: CGFloat = 8
    static let intra: CGFloat = 6
    // Radii
    static let cardRadius: CGFloat = 12
    static let pillRadius: CGFloat = 8
    static let gaugeHeight: CGFloat = 6
    // Type
    static let heroFont = Font.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit()
    static let titleFont = Font.system(size: 15, weight: .semibold)
    static let bodyFont = Font.system(size: 13, weight: .regular)
    static let valueFont = Font.system(size: 13, weight: .medium).monospacedDigit()
    static let resetFont = Font.system(size: 13, weight: .regular).monospacedDigit()
    static let captionFont = Font.system(size: 10, weight: .regular)
    static let menuBarFont = Font.system(size: 12, weight: .semibold).monospacedDigit()

    static let gaugeTrackLight = Color.white.opacity(0.12)
    static let gaugeTrackDark = Color.white.opacity(0.14)
}

/// The demoted 6pt gauge bar — a quiet echo of the number, carrying the risk color
/// (the numeral stays neutral). Over-state breaks past a 100% tick (DESIGN_SYSTEM §3.3).
struct GaugeBar: View {
    let window: UsageSnapshot.Window
    let scheme: ColorScheme
    var height: CGFloat = DS.gaugeHeight

    var body: some View {
        let frac = max(0, min(1, window.utilization / 100))
        let color = RiskTone.color(level: window.riskLevel, over: window.isOver, scheme: scheme)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(scheme == .light ? DS.gaugeTrackLight : DS.gaugeTrackDark)
                Capsule().fill(color)
                    .frame(width: max(3, geo.size.width * frac))
                if window.isOver {
                    Rectangle().fill(Color(.labelColor))
                        .frame(width: 1.5, height: height + 2)
                        .offset(x: geo.size.width - 1.5)
                }
            }
        }
        .frame(height: height)
    }
}

/// A lightweight segmented control that matches the footer tab bar and — unlike
/// `Picker(.segmented)` — renders correctly under ImageRenderer and follows the
/// design system (quiet track, one selected pill, no controlAccent in the meaning
/// channel). Generic over any `Hashable` option.
struct DSSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [T]
    let label: (T) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let on = selection == option
                Text(label(option))
                    .font(.system(size: 11, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Color(.labelColor) : .secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .background(on ? AnyShapeStyle(.background.opacity(0.9)) : AnyShapeStyle(.clear),
                                in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option }
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
    }
}

extension View {
    /// An eyebrow-style section label (UPPERCASE, tracked, tertiary) — use ONCE,
    /// at the major seam (DESIGN_SYSTEM §3.6).
    func dsEyebrow() -> some View {
        self.font(.system(size: 10, weight: .medium))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.tertiary)
    }

    /// The one hairline seam (crisp 1px via displayScale).
    @ViewBuilder func dsHairline() -> some View {
        self.overlay(alignment: .bottom) {
            Color(.separatorColor).frame(height: 1)
        }
    }
}

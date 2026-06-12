import SwiftUI
import AppKit
import TokenMukbangKit

extension Color {
    /// Blend this color a fraction `amount` (0…1) toward `other` in sRGB. Used to pull the
    /// categorical model palette toward the theme accent — keeps relative distinguishability
    /// (every hue shifts equally) while tinting the whole set on-theme.
    func blended(toward other: Color, amount: Double) -> Color {
        let a = max(0, min(1, amount))
        guard a > 0 else { return self }
        guard let c1 = NSColor(self).usingColorSpace(.sRGB),
              let c2 = NSColor(other).usingColorSpace(.sRGB) else { return self }
        return Color(.sRGB,
                     red:   Double(c1.redComponent)   * (1 - a) + Double(c2.redComponent)   * a,
                     green: Double(c1.greenComponent) * (1 - a) + Double(c2.greenComponent) * a,
                     blue:  Double(c1.blueComponent)  * (1 - a) + Double(c2.blueComponent)  * a)
    }
}

// The "Liquid Vitals, Instrument-Grade" design system (docs/design/DESIGN_SYSTEM.md).
// Risk color is resolved HERE (app side), scheme-branched — TokenMukbangKit stays
// color-free and only emits the RiskLevel rawValue + isOver flag.

/// Scheme-branched risk palette. Risk color rides gauge fill / ring / dot ONLY —
/// never a small readable numeral (DESIGN_SYSTEM §1).
enum RiskTone {
    /// Resolve the risk color for a level rawValue ("calm"/"watch"/"warning"/"critical").
    /// Unified, **desaturated, L\*-banded** scale (design-critique 2026-06-12): one
    /// instrument-grade hue per level with a consistent mid-luminance so no single state
    /// out-shouts the others. critical is a *cool crimson* (#C23B4E-family), not the old
    /// "tomato soup" orange-red. Dark = the on-glass hue; light = a darker sibling for
    /// contrast on bright panels (same hue, lower L\*).
    static func color(level: String, over: Bool, scheme: ColorScheme) -> Color {
        let light = scheme == .light
        if over { return Color(hex: light ? "#9C2A40" : "#D94E63") }
        switch level {
        case "calm":     return Color(hex: light ? "#3E8C6E" : "#5BA88A")   // cool teal-green
        case "watch":    return Color(hex: light ? "#9C7C1E" : "#C9A227")   // muted amber-gold
        case "warning":  return Color(hex: light ? "#B0682C" : "#D08A3E")   // burnt ochre
        case "critical": return Color(hex: light ? "#A8313F" : "#C23B4E")   // cool crimson
        default:         return Color(hex: light ? "#3E8C6E" : "#5BA88A")
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
        if over { return Color(hex: light ? "#9C3A50" : "#E68FA0") }
        switch level {
        case "calm":     return Color(hex: light ? "#43806A" : "#83C7AC")
        case "watch":    return Color(hex: light ? "#7A6322" : "#D6BE74")
        case "warning":  return Color(hex: light ? "#945826" : "#DDA873")
        case "critical": return Color(hex: light ? "#9A3340" : "#DB8A95")
        default:         return Color(hex: light ? "#43806A" : "#83C7AC")
        }
    }

    /// The gauge **heat-ramp** fill — a gradient that climbs through the risk tiers up to the
    /// current level (calm→…→current), so the bar reads like a heating element: cooler at the
    /// start, hottest at the leading edge (concept mockup 04-steam). This is the *meaning* the
    /// flat single-color fill had lost — risk = "데워짐", not just a colored block. (ADR-0016)
    static func gaugeRamp(level: String, over: Bool, scheme: ColorScheme) -> [Color] {
        let c: (String) -> Color = { color(level: $0, over: false, scheme: scheme) }
        switch (over ? "critical" : level) {
        case "calm":     return [c("calm").opacity(0.55), c("calm")]
        case "watch":    return [c("calm"), c("watch")]
        case "warning":  return [c("watch"), c("warning")]
        case "critical": return over ? [c("warning"), color(level: "critical", over: true, scheme: scheme)]
                                      : [c("warning"), c("critical")]
        default:         return [c("calm").opacity(0.55), c("calm")]
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

    // MARK: - 김 서림 (Steam) — risk-as-vapor channel (STEAM_DESIGN §컬러 토큰, ADR-0016)

    /// The rising-steam plume tint (color + baked alpha) for a risk level — the Steam
    /// direction's risk channel. Dark-first (steam reads best on dark); light variant
    /// drops luminance so the plume floats on a bright panel. calm ≈ invisible (≤10%),
    /// critical = thick ember-red haze. Risk is read as *density + hue*, not glyph color.
    /// Steam plume tint. **Alpha-capped ≤ 0.22** (design-critique: haze was drowning the
    /// glass). Adaptation rides *alpha*, not hue — a single warm-ember family per level,
    /// dark a touch denser than light. calm ≈ invisible. Risk = density, read at a glance.
    static func steamTint(level: String, over: Bool, scheme: ColorScheme) -> Color {
        let light = scheme == .light
        switch (over ? "critical" : level) {
        case "calm":     return Color(hex: "#E9D8C4").opacity(light ? 0.05 : 0.06)
        case "watch":    return Color(hex: "#E8B770").opacity(light ? 0.10 : 0.12)
        case "warning":  return Color(hex: "#E5944A").opacity(light ? 0.15 : 0.17)
        case "critical": return Color(hex: "#DC6A4A").opacity(light ? 0.20 : 0.22)
        default:         return Color(hex: "#E9D8C4").opacity(light ? 0.05 : 0.06)
        }
    }

    /// The z0 broth under-glow (risk hue, low alpha → background). Same hue light/dark,
    /// alpha rises with risk. Sits *beneath* the frost panel so it never touches numerals.
    /// Toned down from the old 0.62 ceiling so the glow warms the floor, not floods it.
    static func brothGlow(level: String, over: Bool, scheme: ColorScheme) -> Color {
        // Light mode gets ~half the alpha — on a bright paper base the warm glow read as a
        // muddy peach stain rather than a glow (user feedback 2026-06-12).
        let k = scheme == .light ? 0.55 : 1.0
        switch (over ? "critical" : level) {
        case "calm":     return Color(hex: "#E8A957").opacity(0.10 * k)
        case "watch":    return Color(hex: "#E8A030").opacity(0.18 * k)
        case "warning":  return Color(hex: "#E27B2C").opacity(0.28 * k)
        case "critical": return Color(hex: "#D85436").opacity(0.40 * k)
        default:         return Color(hex: "#E8A957").opacity(0.10 * k)
        }
    }
}

/// 김 서림(Steam) 표면 토큰 — 쿨 뉴트럴 글래스/프로스트/스크림 (STEAM_DESIGN §컬러 토큰).
/// 채도는 위험(steam/broth)에만, 유리/응결은 무채색. 다크 우선. 모두 scheme 분기.
enum Steam {
    static func frostPanel(_ s: ColorScheme) -> Color { s == .light ? Color(hex: "#E8EAED") : Color(hex: "#1C1E22") }
    static func frostTile(_ s: ColorScheme) -> Color { s == .light ? Color(hex: "#F4F5F7") : Color(hex: "#282B31") }
    static func scrimNumber(_ s: ColorScheme) -> Color { s == .light ? Color(hex: "#DADCE0") : Color(hex: "#131519") }
    static func inkPrimary(_ s: ColorScheme) -> Color { s == .light ? Color(hex: "#1A1C1F") : Color(hex: "#F2F3F5") }
    static func inkSecondary(_ s: ColorScheme) -> Color { s == .light ? Color(hex: "#5B606A") : Color(hex: "#A7ACB5") }
    /// Outer rim refraction edge (2px) — bright on light, faint on dark.
    static func edgeLens(_ s: ColorScheme) -> Color { s == .light ? Color.white.opacity(0.70) : Color.white.opacity(0.20) }
    static func hairline(_ s: ColorScheme) -> Color { s == .light ? Color.black.opacity(0.08) : Color.white.opacity(0.094) }

    // Tightened from 28/22 (design-critique: native macOS cards are crisper, not pill-soft).
    static let panelRadius: CGFloat = 18
    static let tileRadius: CGFloat = 14
}

/// Theme **mood** — how the selected `Theme` tints the popover *atmosphere* (background
/// wash · glass tint · accent). Risk colors stay semantic & theme-independent: the theme is
/// the room's mood, the danger scale never changes meaning (user decision 2026-06-12; ADR-0015
/// keeps color app-side). Resolved once at the popover root and read via `\.themeMood`.
struct ThemeMood: Equatable {
    var baseTop: Color
    var baseBottom: Color
    var glassTint: Color        // faint per-theme overlay on cards (.clear = neutral)
    var accent: Color           // theme accent (drives .tint + categorical-color biasing)
    var dataTint: Double        // how hard categorical (model) colors pull toward accent (0…1)
    var riskTint: Double        // GENTLER pull for risk colors (gauge/dots) — keeps the
                                // calm→critical ordering so danger still reads, just on-theme

    /// Blend a risk color toward the theme so the whole UI is cohesive — gentle so critical
    /// stays clearly hot. 기타-style neutrals are untouched by callers.
    func themedRisk(_ c: Color) -> Color { c.blended(toward: accent, amount: riskTint) }

    /// Intrinsic base wash under the frost — gives the popover its OWN depth/color so it looks
    /// rich over *any* desktop (not only a colorful wallpaper), now tinted by the theme.
    var baseWash: LinearGradient {
        LinearGradient(colors: [baseTop, baseBottom], startPoint: .top, endPoint: .bottom)
    }

    static func resolve(_ theme: Theme, _ scheme: ColorScheme, accent: Color) -> ThemeMood {
        let light = scheme == .light
        // The biggest container is PURE glass — only a faint NEUTRAL frost scrim for text
        // legibility (no theme hue), so the behind-window blur reads as real glass. The THEME
        // color lives on the CARDS (glassTint) instead (user idea 2026-06-12).
        let baseTop    = Color(hex: light ? "#FFFFFF" : "#2C3036").opacity(light ? 0.12 : 0.16)
        let baseBottom = Color(hex: light ? "#F1F0EE" : "#191B20").opacity(light ? 0.18 : 0.22)
        func card(_ hex: String, _ a: Double) -> Color { Color(hex: hex).opacity(a) }
        switch theme {
        case .classic:            // neutral glass cards
            return ThemeMood(baseTop: baseTop, baseBottom: baseBottom,
                             glassTint: .clear, accent: accent, dataTint: 0.0, riskTint: 0.0)
        case .custom:             // cards tinted by the user's accent
            return ThemeMood(baseTop: baseTop, baseBottom: baseBottom,
                             glassTint: accent.opacity(0.16), accent: accent, dataTint: 0.32, riskTint: 0.16)
        case .mint:               // mint-tinted glass cards
            return ThemeMood(baseTop: baseTop, baseBottom: baseBottom,
                             glassTint: card(light ? "#13A56B" : "#37E8AE", 0.18),
                             accent: accent, dataTint: 0.42, riskTint: 0.24)
        case .sunset:             // amber-tinted glass cards
            return ThemeMood(baseTop: baseTop, baseBottom: baseBottom,
                             glassTint: card(light ? "#F2590A" : "#FFA86B", 0.18),
                             accent: accent, dataTint: 0.42, riskTint: 0.24)
        case .mono:               // neutral grey cards + greyscale data
            return ThemeMood(baseTop: baseTop, baseBottom: baseBottom,
                             glassTint: Color.gray.opacity(0.13),
                             accent: accent, dataTint: 0.70, riskTint: 0.50)
        }
    }
}

private struct ThemeMoodKey: EnvironmentKey {
    static let defaultValue = ThemeMood.resolve(.classic, .dark, accent: Color(hex: "#0A84FF"))
    // (riskTint/dataTint baked by resolve)
}
extension EnvironmentValues {
    var themeMood: ThemeMood {
        get { self[ThemeMoodKey.self] }
        set { self[ThemeMoodKey.self] = newValue }
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

    // Track must contrast the card it sits on: ink on light glass, white on dark glass —
    // a white track on a light card was invisible (design-critique r3).
    static let gaugeTrackLight = Color.black.opacity(0.12)
    static let gaugeTrackDark = Color.white.opacity(0.18)

    /// Model **identity** color for the per-model breakdown — a stable hue per cast,
    /// distinct from the risk palette (this channel means "which model", not "how hot").
    /// nil cast = 기타 (synthetic/unmapped) → neutral gray.
    static func modelColor(_ cast: ModelCast?, scheme: ColorScheme) -> Color {
        let light = scheme == .light
        // Desaturated identity hues (design-critique): muted enough to coexist with the
        // risk scale without competing, still distinct from each other.
        switch cast {
        case .opus:   return Color(hex: light ? "#6A5A99" : "#8B7DB8")    // 보라 — 대식가
        case .sonnet: return Color(hex: light ? "#4F7299" : "#7595B8")    // 파랑 — 평균인
        // Pushed toward cyan so model-Haiku never reads as risk-calm (both were teal-green
        // neighbors — design-critique r3).
        case .haiku:  return Color(hex: light ? "#3E8A99" : "#5FB8C9")    // 시안 — 소식좌
        // Pushed toward magenta/rose so identity-pink never gets confused with risk-crimson
        // (they were color-wheel neighbors — design-critique r2).
        case .fable:  return Color(hex: light ? "#9A5A92" : "#C081C0")    // 자홍 — 미식가
        case .none:   return (light ? Color.black : Color.white).opacity(0.32)  // 기타
        }
    }

    /// Theme-aware model color — the categorical hue pulled toward the theme accent so the
    /// History chart/legend read on-theme (relative distinctness preserved). 기타(neutral)
    /// stays neutral. (user feedback 2026-06-12: charts must follow the theme too.)
    static func modelColor(_ cast: ModelCast?, scheme: ColorScheme, mood: ThemeMood) -> Color {
        let base = modelColor(cast, scheme: scheme)
        guard cast != nil else { return base }   // 기타 stays neutral
        return base.blended(toward: mood.accent, amount: mood.dataTint)
    }
}

/// The demoted 6pt gauge bar — a quiet echo of the number, carrying the risk color
/// (the numeral stays neutral). Over-state breaks past a 100% tick (DESIGN_SYSTEM §3.3).
struct GaugeBar: View {
    let window: UsageSnapshot.Window
    let scheme: ColorScheme
    var height: CGFloat = DS.gaugeHeight
    @Environment(\.themeMood) private var mood

    var body: some View {
        let frac = max(0, min(1, window.utilization / 100))
        // Risk ramp, gently pulled on-theme so the dashboard matches the History chart while the
        // calm→critical order (danger reading) survives (user feedback 2026-06-12).
        let ramp = RiskTone.gaugeRamp(level: window.riskLevel, over: window.isOver, scheme: scheme)
            .map { mood.themedRisk($0) }
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(scheme == .light ? DS.gaugeTrackLight : DS.gaugeTrackDark)
                // Heat-ramp fill (concept mockup): climbs the risk tiers → cooler at the start,
                // hottest at the leading edge. The gradient is anchored to the FULL bar width so
                // the hue at any x means the same thing regardless of fill (a true thermometer).
                Capsule()
                    .fill(LinearGradient(colors: ramp, startPoint: .leading, endPoint: .trailing))
                    .mask(alignment: .leading) {
                        Capsule().frame(width: max(3, geo.size.width * frac))
                    }
                    .frame(width: geo.size.width)
                    .overlay(alignment: .leading) {
                        // Ember leading edge at the fill tip — fades out near-full so the tip
                        // doesn't bloom at the 100% mark (design-critique r3).
                        Capsule().fill(ramp.last ?? .clear)
                            .frame(width: height).blur(radius: 1.5)
                            .opacity(frac > 0.85 ? 0.0 : 0.8)
                            .offset(x: max(0, geo.size.width * frac - height))
                    }
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
                // Constant weight — toggling .semibold/.regular changed the label width and made
                // the tabs visibly jump on switch (user 2026-06-12). Selection = pill + ink only.
                Text(label(option))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
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
        // .secondary (not .tertiary) — over the see-through glass the tertiary eyebrows vanished
        // on busy backdrops (user 2026-06-12: "7D WINDOW/SESSIONS 안 보임").
        self.font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    /// The one hairline seam (crisp 1px via displayScale).
    @ViewBuilder func dsHairline() -> some View {
        self.overlay(alignment: .bottom) {
            Color(.separatorColor).frame(height: 1)
        }
    }
}

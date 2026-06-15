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
        let level = f < 0.5 ? "calm" : f < 0.65 ? "watch" : f < 0.85 ? "warning" : "critical"
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
    var glassTint: Color        // per-theme card tint (.clear = neutral)
    var accent: Color           // theme accent (drives .tint + categorical-color biasing)
    var dataTint: Double        // how hard categorical (model) colors pull toward accent (0…1)
    // Per-theme RISK ramp (curated, scheme-branched — theme-palette-redesign 2026-06-13). The
    // grammar is invariant (calm cool/safe → critical hot/danger, monotonic L*), each theme only
    // tints it to its identity (Ember runs hotter, Matcha calmer, Mono achromatic).
    var riskCalm: Color
    var riskWatch: Color
    var riskWarning: Color
    var riskCritical: Color
    var riskOver: Color

    /// The final risk color for a level (per-theme). Replaces RiskTone.color in the popover —
    /// the menu bar keeps RiskTone (theme-independent, wallpaper-tuned).
    func risk(_ level: String, over: Bool) -> Color {
        if over { return riskOver }
        switch level {
        case "watch":    return riskWatch
        case "warning":  return riskWarning
        case "critical": return riskCritical
        case "calm":     return riskCalm
        default:         return riskCalm
        }
    }

    /// Gauge heat-ramp built from this theme's risk colors (cooler start → hottest leading edge).
    func riskRamp(level: String, over: Bool) -> [Color] {
        switch (over ? "critical" : level) {
        case "watch":    return [riskCalm, riskWatch]
        case "warning":  return [riskWatch, riskWarning]
        case "critical": return over ? [riskWarning, riskOver] : [riskWarning, riskCritical]
        case "calm":     return [riskCalm.opacity(0.55), riskCalm]
        default:         return [riskCalm.opacity(0.55), riskCalm]
        }
    }

    /// Session context-fill → risk level → this theme's risk color. All four bands are used so the
    /// per-theme `watch` color actually appears on session dots (theme-palette-redesign 2026-06-13).
    func contextColor(_ fraction: Double?) -> Color {
        guard let f = fraction else { return Color(.tertiaryLabelColor) }
        let level = f < 0.5 ? "calm" : f < 0.65 ? "watch" : f < 0.85 ? "warning" : "critical"
        return risk(level, over: f >= 1.0)
    }

    var baseWash: LinearGradient {
        LinearGradient(colors: [baseTop, baseBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Resolve a theme to its full atmosphere + risk ramp for a scheme. For preset themes the
    /// accent is the theme's own (the passed `accent` is used only by `.custom`).
    static func resolve(_ theme: Theme, _ scheme: ColorScheme, accent customAccent: Color) -> ThemeMood {
        let light = scheme == .light
        func c(_ l: String, _ d: String) -> Color { Color(hex: light ? l : d) }
        // base wash: themed hue at a faint alpha so the behind-window glass still shows through.
        // Pushed up from 0.16/0.24·0.20/0.26 — at the old alpha the wash sat behind the material
        // cards and themes read identical (charcoal ≈ matcha). Higher alpha makes the panel base
        // carry the theme hue in the gaps/around the cards while still letting the behind-window
        // glass (ADR-0018) show through (theme-palette-redesign 2026-06-13).
        func wash(_ lTop: String, _ lBot: String, _ dTop: String, _ dBot: String) -> (Color, Color) {
            light ? (Color(hex: lTop).opacity(0.22), Color(hex: lBot).opacity(0.34))
                  : (Color(hex: dTop).opacity(0.30), Color(hex: dBot).opacity(0.44))
        }
        func tint(_ l: String, _ d: String, _ a: Double) -> Color { Color(hex: light ? l : d).opacity(a) }

        switch theme {
        case .charcoal:   // 숯불 — Korean grill ember, dark-first, runs hot. Base = warm glowing coals.
            let w = wash("#FCF6F1", "#EFE3DA", "#2E2318", "#180F08")
            return ThemeMood(baseTop: w.0, baseBottom: w.1,
                glassTint: tint("#F2590A", "#FF8A4D", 0.22), accent: c("#D9480F", "#F76707"), dataTint: 0.30,
                riskCalm: c("#3E8C6E", "#5BA88A"), riskWatch: c("#9C7C1E", "#D8A92E"),
                riskWarning: c("#B0682C", "#E08B3A"), riskCritical: c("#A8313F", "#E0573F"), riskOver: c("#8C2718", "#FF5630"))
        case .matcha:     // 말차 — tea-ceremony calm, warm yellow-green (chartreuse tea). Base leans
                          // distinctly green so its surround separates from ganjang's brown (closest pair).
            let w = wash("#F1F0DE", "#D6E2C0", "#1E2E16", "#0D170A")
            return ThemeMood(baseTop: w.0, baseBottom: w.1,
                glassTint: tint("#5E8C3E", "#9ED67A", 0.23), accent: c("#5E8C3E", "#8FCB6B"), dataTint: 0.34,
                riskCalm: c("#4F8C5A", "#7BC07F"), riskWatch: c("#8C861E", "#C4BC4A"),
                riskWarning: c("#A06B2C", "#C99A52"), riskCritical: c("#A03B44", "#C8525E"), riskOver: c("#8C2E3A", "#D9606C"))
        case .hanji:      // 한지 — light-first mulberry paper + sumi ink + 인주 seal. In dark the base
                          // is a muted *warm grey* (paper under low light), not brown — that, plus the
                          // sharp vermilion 인주 accent, separates it from charcoal's ember & ganjang's soy.
            let w = wash("#F7F3E9", "#E6DCC8", "#2A2826", "#181615")
            return ThemeMood(baseTop: w.0, baseBottom: w.1,
                glassTint: tint("#C2A878", "#CFC3AE", 0.22), accent: c("#C0341B", "#E85C44"), dataTint: 0.28,
                riskCalm: c("#4A7A5E", "#7AAE8C"), riskWatch: c("#94781E", "#C7A848"),
                riskWarning: c("#A8682C", "#CE9456"), riskCritical: c("#A8313A", "#D04E50"), riskOver: c("#8C2018", "#E0574A"))
        case .ganjang:    // 간장 — fermented soy brown base + 단청 **jade** (양록) jewel accent. The jade
                          // accent (not another red) is what makes this room its own hue, breaking the warm
                          // trio: deep soy-brown panel, jade-tinted glass + tab. Danger stays red (universal).
            let w = wash("#EDE2D0", "#D6BE9C", "#2E1D0C", "#1A0E04")
            return ThemeMood(baseTop: w.0, baseBottom: w.1,
                glassTint: tint("#2F7D63", "#46B38C", 0.22), accent: c("#2F7D63", "#46C39A"), dataTint: 0.34,
                riskCalm: c("#3E6B4F", "#5C9A6E"), riskWatch: c("#A6841E", "#D8B042"),
                riskWarning: c("#B06A2C", "#D89254"), riskCritical: c("#C1352B", "#E0594A"), riskOver: c("#9C2A22", "#F2604A"))
        case .obang:      // 오방 — Korea's five cardinal colors; 청 accent, 적 = danger. Base leans cool navy.
            let w = wash("#F6F8FB", "#DCE6F0", "#141C2E", "#080D18")
            return ThemeMood(baseTop: w.0, baseBottom: w.1,
                glassTint: tint("#1F6FB2", "#5AA8E0", 0.22), accent: c("#1F6FB2", "#4FA0E0"), dataTint: 0.30,
                riskCalm: c("#2E7D5E", "#5ABF93"), riskWatch: c("#C8A21E", "#F0C840"),
                riskWarning: c("#C8702C", "#E89A48"), riskCritical: c("#C8323A", "#E85560"), riskOver: c("#A8222A", "#F25360"))
        case .mono:       // 흑백 — instrument-grade achromatic, with a **VU-meter danger zone**. calm/
                          // watch/warning stay achromatic (lightness ramp, scheme-aware: dark climbs
                          // brighter, light climbs darker). But **critical & over turn a muted
                          // instrument-red** — a near-white "critical" read as *clean*, not *danger*
                          // (QA iter2), so the room follows the universal 빨강=위험 invariant exactly
                          // where it matters, like a meter's red peak zone. Still "the grey room" 95%
                          // of the time (critical is rare); accuracy > purity (정확함 > 귀여움).
            let w = wash("#FAFAFA", "#ECECEC", "#26282B", "#141517")
            return ThemeMood(baseTop: w.0, baseBottom: w.1,
                glassTint: tint("#7A7A7A", "#9AA0A6", 0.16), accent: c("#3A3D42", "#C8CCD2"), dataTint: 0.70,
                riskCalm: c("#979CA3", "#585D64"), riskWatch: c("#6E737B", "#868C94"),
                riskWarning: c("#474B51", "#B4BAC2"), riskCritical: c("#B23A3A", "#D6534C"), riskOver: c("#8E2018", "#F0473A"))
        case .custom:     // user accent drives glass + a gentle on-theme risk pull
            let w = wash("#FBFAF8", "#EEECE8", "#2A2E35", "#191B20")
            let r: (String) -> Color = { lvl in RiskTone.color(level: lvl, over: false, scheme: scheme).blended(toward: customAccent, amount: 0.16) }
            return ThemeMood(baseTop: w.0, baseBottom: w.1,
                glassTint: customAccent.opacity(0.16), accent: customAccent, dataTint: 0.32,
                riskCalm: r("calm"), riskWatch: r("watch"), riskWarning: r("warning"),
                riskCritical: r("critical"), riskOver: RiskTone.color(level: "critical", over: true, scheme: scheme).blended(toward: customAccent, amount: 0.16))
        }
    }
}

private struct ThemeMoodKey: EnvironmentKey {
    static let defaultValue = ThemeMood.resolve(.charcoal, .dark, accent: Color(hex: "#F76707"))
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
        // Per-theme risk heat-ramp (curated per theme; calm→critical order preserved everywhere).
        let ramp = mood.riskRamp(level: window.riskLevel, over: window.isOver)
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
    @Environment(\.themeMood) private var mood
    /// The indicator's animated position, as a fractional index. Driven by an EXPLICIT
    /// `withAnimation` (not the implicit `.animation(_:value:)` modifier, which the big tab
    /// content-swap re-render cancelled, making the pill jump instead of slide — verified via
    /// frame-by-frame capture, user 2026-06-15). Content swaps instantly; only this slides.
    @State private var indicator: CGFloat = 0

    private var selectedIndex: Int { options.firstIndex(of: selection) ?? 0 }
    private var slide: Animation { .spring(response: 0.34, dampingFraction: 0.82) }

    var body: some View {
        GeometryReader { geo in
            let n = max(1, options.count)
            let cellW = geo.size.width / CGFloat(n)
            let pill = RoundedRectangle(cornerRadius: 7, style: .continuous)
            ZStack(alignment: .leading) {
                ZStack {
                    pill.fill(.regularMaterial)
                    pill.fill(mood.accent.opacity(0.16))
                }
                .overlay(pill.strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 2.5, y: 1)
                .frame(width: max(0, cellW - 4), height: max(0, geo.size.height - 4))
                .offset(x: indicator * cellW + 2)

                HStack(spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        let on = selection == option
                        Text(label(option))
                            .font(.system(size: 11.5, weight: on ? .semibold : .medium))
                            .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .lineLimit(1)
                            .frame(width: cellW, height: geo.size.height)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard selection != option else { return }
                                selection = option                                       // content: instant
                                let target = CGFloat(options.firstIndex(of: option) ?? 0)
                                withAnimation(slide) { indicator = target }         // pill: slide
                            }
                    }
                }
            }
        }
        .frame(height: 24)
        .padding(2)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
        .onAppear { indicator = CGFloat(selectedIndex) }
        // External selection changes (not via a tap here) still slide the indicator.
        .onChange(of: selection) { _, _ in
            withAnimation(slide) { indicator = CGFloat(selectedIndex) }
        }
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

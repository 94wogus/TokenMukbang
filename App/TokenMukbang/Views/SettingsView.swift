import SwiftUI
import TokenMukbangKit

/// Which Settings tab is showing. General (time zone & basics), Appearance (how it looks) and
/// Alerts (when it warns) are different kinds of setting, so they live behind a top segmented
/// toggle rather than one long scroll (user feedback 2026-06-15).
enum SettingsTab: String, CaseIterable, Hashable, Identifiable {
    case general, appearance, alerts
    var id: String { rawValue }
    var label: String {
        switch self {
        case .general:    return "General"
        case .appearance: return "Appearance"
        case .alerts:     return "Alerts"
        }
    }
}

/// The Settings space — two tabs:
///   • **Appearance** — a visual theme gallery (each swatch renders its own room: baseWash +
///     frosted card + accent + risk ramp, the macOS Appearance / Raycast / VS Code pattern),
///     a faithful live preview, and the custom-accent color well.
///   • **Alerts** — the warning/critical thresholds + per-surface/per-event notifications.
///
/// All copy is English (global distribution). The risk *grammar* stays invariant (red = danger,
/// calm→critical) — only the per-theme tone shifts (ADR-0015).
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    private let gridColumns = [GridItem(.flexible(), spacing: 10),
                               GridItem(.flexible(), spacing: 10),
                               GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DSSegmented(selection: $model.settingsTab, options: SettingsTab.allCases) { $0.label }

            switch model.settingsTab {
            case .general: generalTab
            case .appearance: appearanceTab
            case .alerts: alertsTab
            }
        }
        // No own background — the shell already washes the whole window; a second baseWash here
        // read as an extra container around Settings only (user 2026-06-15). Just ensure the cards
        // tint to the selected theme via the env.
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.themeMood, selectedMood)
    }

    // MARK: - General tab

    /// General settings — currently the display **time zone**. The OAuth API delivers
    /// UTC-bearing instants; this zone decides how day buckets / chart axes / times are
    /// labelled (it never moves a reset countdown, which is pure interval math).
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Time zone", icon: "clock") {
                // The machine's detected zone — shown for reference even when overriding.
                HStack(spacing: 6) {
                    Image(systemName: "location.fill").font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text("This Mac: \(tzLabel(.current))")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Toggle(isOn: followSystem) {
                    Text("Follow system time zone").font(.caption)
                }
                .toggleStyle(.switch).controlSize(.mini)
                .tint(selectedMood.accent)

                if !followSystem.wrappedValue {
                    Divider().padding(.vertical, 2)
                    Text("Showing times in").font(.caption2).foregroundStyle(.tertiary)
                    TimeZonePicker(selection: timeZoneOverride, accent: selectedMood.accent)
                }

                Text("Charts, day buckets and times use this zone. Reset countdowns are unaffected.")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }

    /// nil identifier ⇄ "follow system" switch.
    private var followSystem: Binding<Bool> {
        Binding(get: { model.settings.followsSystemTimeZone },
                set: { model.settings.timeZoneIdentifier = $0 ? nil : TimeZone.current.identifier })
    }

    /// The explicit override identifier (only read/written while not following system).
    private var timeZoneOverride: Binding<String> {
        Binding(get: { model.settings.timeZoneIdentifier ?? TimeZone.current.identifier },
                set: { model.settings.timeZoneIdentifier = $0 })
    }

    // MARK: - Appearance tab

    private var appearanceTab: some View {
        // One controls card (theme gallery + custom accent + glass slider) and the preview as its
        // own single card — the preview is no longer wrapped in a second GlassTile (that glass-on-
        // glass nesting was the redundant container, user 2026-06-15).
        VStack(alignment: .leading, spacing: 12) {
            section("Theme", icon: "paintpalette.fill") {
                LazyVGrid(columns: gridColumns, spacing: 12) {
                    ForEach(Theme.allCases) { theme in
                        ThemeSwatch(theme: theme, scheme: scheme,
                                    selected: model.settings.theme == theme,
                                    accent: Color(hex: model.settings.customPalette.accentHex))
                            .onTapGesture {
                                withAnimation(.snappy(duration: 0.18)) {
                                    model.settings.theme = theme
                                }
                            }
                    }
                }

                if model.settings.theme == .custom {
                    Divider().padding(.vertical, 4)
                    ColorPicker(selection: customAccent, supportsOpacity: false) {
                        Text("Accent color").font(.caption)
                    }
                }

                Divider().padding(.vertical, 4)
                HStack(spacing: 6) {
                    Image(systemName: "square.on.square.dashed").font(.system(size: 9, weight: .bold))
                    Text("Glass").dsEyebrow()
                }
                .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Image(systemName: "circle.dotted").font(.system(size: 11))
                        .foregroundStyle(.tertiary).help("More see-through")
                    Slider(value: $model.settings.glassOpacity, in: 0.2...1.0, step: 0.05)
                        .tint(selectedMood.accent)
                    Image(systemName: "square.fill").font(.system(size: 11))
                        .foregroundStyle(.secondary).help("More frosted")
                }
                Text("Window background blur — updates live.")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }

            // Preview = a single card (the hero), with a plain eyebrow above — no outer GlassTile.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "eye.fill").font(.system(size: 9, weight: .bold))
                    Text("Preview").dsEyebrow()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
                livePreview
            }
        }
    }

    /// Faithful live preview — the selected theme applied to the *real* hero-card chrome
    /// (GlassTile + StatusChip + GaugeBar), so picking a theme shows the actual result. Risk fixed
    /// at "warning" so the heat-ramp + chip read in mid-scale. (Sits on the section's themed
    /// background, which already carries the room wash.)
    private var livePreview: some View {
        let sample = UsageSnapshot.Window(
            kind: "five_hour", label: "5h", utilization: 73,
            resetsAt: Date().addingTimeInterval(7200), riskHex: "#000000",
            riskLabel: "warning", riskLevel: "warning", isOver: false, paceWarningHours: nil)
        return GlassTile(scheme: scheme) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("5H WINDOW").dsEyebrow()
                    Spacer()
                    StatusChip(level: "warning", over: false, scheme: scheme)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("73%")
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Resets in 2h").font(DS.resetFont).foregroundStyle(.primary.opacity(0.72))
                }
                GaugeBar(window: sample, scheme: scheme, height: 8)
                HStack(spacing: 5) {
                    ForEach(["calm", "watch", "warning", "critical"], id: \.self) { lvl in
                        Circle().fill(selectedMood.risk(lvl, over: false)).frame(width: 7, height: 7)
                    }
                    Text("Risk scale").font(.system(size: 9)).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
            .padding(DS.section)
        }
        .environment(\.themeMood, selectedMood)
    }

    // MARK: - Alerts tab

    private var alertsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Thresholds", icon: "gauge.with.dots.needle.67percent") {
                Text("Where the warnings switch on").font(.caption2).foregroundStyle(.tertiary)
                threshold("Warning", value: $model.settings.thresholds.warning, color: selectedMood.riskWarning)
                threshold("Critical", value: $model.settings.thresholds.critical, color: selectedMood.riskCritical)
            }

            section("Notifications", icon: "bell.badge.fill") {
                // Surfaces = which windows to watch — selectable chips read cleaner than 3 switches.
                Text("Surfaces").font(.caption2).foregroundStyle(.tertiary)
                HStack(spacing: 6) {
                    surfaceChip("5h", isOn: $model.settings.notifications.fiveHour)
                    surfaceChip("7d", isOn: $model.settings.notifications.sevenDay)
                    surfaceChip("Sonnet", isOn: $model.settings.notifications.sonnet)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 2)

                // Events = each alert type as an icon row (color tile + title + subtitle + switch).
                Text("Events").font(.caption2).foregroundStyle(.tertiary).padding(.top, 4)
                VStack(spacing: 2) {
                    notifyRow("flame.fill", "#E0573F", "Overeating", "Crossed warning / critical",
                              isOn: $model.settings.notifications.escalation)
                    notifyRow("checkmark.seal.fill", "#5BA88A", "Digested", "Dropped back to safe",
                              isOn: $model.settings.notifications.recovery)
                    notifyRow("speedometer", "#4FA0E0", "Pace warning", "On track to finish early",
                              isOn: $model.settings.notifications.pacing)
                    notifyRow("fork.knife", "#8FB85E", "Fresh table", "A window reset",
                              isOn: $model.settings.notifications.reset)
                    notifyRow("plus.circle.fill", "#9AA0A6", "Extra credit", "Coming soon",
                              isOn: $model.settings.notifications.extraCredit, disabled: true)
                    notifyRow("key.fill", "#8B7DB8", "Token expiry", "OAuth token expired",
                              isOn: $model.settings.notifications.tokenExpiry)
                }
            }
        }
    }

    /// A selectable surface chip (pill) — accent-filled when on, quiet when off.
    private func surfaceChip(_ label: String, isOn: Binding<Bool>) -> some View {
        let on = isOn.wrappedValue
        return Text(label)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(on ? AnyShapeStyle(selectedMood.accent.opacity(0.28)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                        in: Capsule())
            .overlay(Capsule().strokeBorder(on ? selectedMood.accent.opacity(0.6) : .clear, lineWidth: 1))
            .contentShape(Capsule())
            .onTapGesture { isOn.wrappedValue.toggle() }
    }

    /// An event row: colored icon tile · title + subtitle · trailing switch (iOS settings idiom).
    private func notifyRow(_ icon: String, _ tint: String, _ title: String, _ subtitle: String,
                           isOn: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color(hex: tint).gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 9.5)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.mini)
        }
        .opacity(disabled ? 0.45 : 1)
        .disabled(disabled)
        .padding(.vertical, 2)
    }

    // MARK: - Shared chrome

    private var selectedMood: ThemeMood {
        ThemeMood.resolve(model.settings.theme, scheme, accent: Color(hex: model.settings.customPalette.accentHex))
    }

    private var customAccent: Binding<Color> {
        Binding(get: { Color(hex: model.settings.customPalette.accentHex) },
                set: { model.settings.customPalette.accentHex = $0.hexString })
    }

    /// Each settings group sits in a GlassTile (shares the dashboard's card aesthetic) with an
    /// icon + eyebrow header for a clear, scannable hierarchy.
    @ViewBuilder
    private func section<C: View>(_ title: String, icon: String, @ViewBuilder _ content: @escaping () -> C) -> some View {
        GlassTile(scheme: scheme) {
            VStack(alignment: .leading, spacing: DS.intra) {
                HStack(spacing: 5) {
                    Image(systemName: icon).font(.system(size: 9, weight: .bold))
                    Text(title).dsEyebrow()
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.section)
        }
    }

    private func threshold(_ label: String, value: Binding<Double>, color: Color) -> some View {
        HStack {
            Text(label).font(.caption).frame(width: 60, alignment: .leading)
            Slider(value: value, in: 10...100, step: 5).tint(color)
            Text("\(Int(value.wrappedValue))%").font(.caption.monospacedDigit()).frame(width: 38, alignment: .trailing)
        }
    }
}

/// A self-previewing theme swatch for the gallery — renders the theme's room (baseWash) + a
/// frosted card (glassTint over material, mirroring the real GlassTile layering) + accent dot +
/// a heat-ramp gauge + the 4 risk dots. The whole point is that the swatch *is* a miniature of
/// what the theme does, so the gallery sells each room's identity at a glance.
private struct ThemeSwatch: View {
    let theme: Theme
    let scheme: ColorScheme
    let selected: Bool
    let accent: Color

    var body: some View {
        let mood = ThemeMood.resolve(theme, scheme, accent: accent)
        let card = RoundedRectangle(cornerRadius: 7, style: .continuous)
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(mood.baseWash)
                VStack(spacing: 6) {
                    // Mini frosted card: accent dot + heat-ramp gauge (the in-room content).
                    HStack(spacing: 5) {
                        Circle().fill(mood.accent).frame(width: 7, height: 7)
                        Capsule()
                            .fill(LinearGradient(colors: mood.riskRamp(level: "warning", over: false),
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(height: 5)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 6)
                    .background {
                        ZStack {
                            card.fill(.regularMaterial)
                            card.fill(mood.glassTint)
                        }
                    }
                    .overlay(card.strokeBorder(.white.opacity(scheme == .light ? 0.5 : 0.08), lineWidth: 0.5))
                    // Risk ramp — the theme's danger identity (calm → critical).
                    HStack(spacing: 4) {
                        ForEach(["calm", "watch", "warning", "critical"], id: \.self) { lvl in
                            Circle().fill(mood.risk(lvl, over: false)).frame(width: 6, height: 6)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .padding(8)
            }
            .frame(height: 66)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? mood.accent : Color.primary.opacity(0.10),
                                  lineWidth: selected ? 2 : 1)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.white, mood.accent)
                        .padding(4)
                }
            }
            .shadow(color: .black.opacity(selected ? 0.20 : 0.08), radius: selected ? 5 : 2, y: 1)

            Text(theme.label)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .help(theme.label)
    }
}

// MARK: - Time zone picker

/// "UTC+09:00" style offset for a zone (uses the zone's *current* offset incl. DST).
private func tzOffset(_ tz: TimeZone) -> String {
    let secs = tz.secondsFromGMT()
    let a = abs(secs)
    return String(format: "UTC%@%02d:%02d", secs >= 0 ? "+" : "-", a / 3600, (a % 3600) / 60)
}

/// "Asia/Seoul (UTC+09:00)" — identifier + current offset.
private func tzLabel(_ tz: TimeZone) -> String { "\(tz.identifier) (\(tzOffset(tz)))" }

/// A searchable list of every IANA time zone — type to filter, tap to select. Lives inside the
/// Settings popover, so it's a compact filter field + a fixed-height scrolling list (not a sheet).
private struct TimeZonePicker: View {
    @Binding var selection: String
    var accent: Color
    @State private var query: String = ""

    private var matches: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers.sorted()
        guard !query.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.tertiary)
                TextField("Search (e.g. Seoul, New_York, UTC)", text: $query)
                    .textFieldStyle(.plain).font(.caption)
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(matches, id: \.self) { id in
                        let isSel = id == selection
                        Button { selection = id } label: {
                            HStack(spacing: 6) {
                                Text(id).font(.caption)
                                    .foregroundStyle(isSel ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                Spacer(minLength: 6)
                                Text(tzOffset(TimeZone(identifier: id) ?? .current))
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                if isSel {
                                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(accent)
                                }
                            }
                            .padding(.vertical, 4).padding(.horizontal, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .background(isSel ? AnyShapeStyle(accent.opacity(0.16)) : AnyShapeStyle(.clear),
                                        in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                    }
                    if matches.isEmpty {
                        Text("No matching zone").font(.caption2).foregroundStyle(.tertiary)
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(height: 170)
        }
    }
}

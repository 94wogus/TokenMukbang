import SwiftUI
import ClaudeUsageKit

/// The dropdown panel shown when the menu-bar item is clicked.
struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.openSettings) private var openSettings
    private let now = Date()

    var body: some View {
        // Content-sized popover with nav at the TOP (현황|기록 toggle) and Settings in a
        // separate ⌘, window — native menu-bar IA, not a bottom tab bar. The toggle stays put
        // at the top, so switching modes never moves the control under the cursor (the old
        // bottom-tab jump). A maxHeight cap keeps an unusually long history scrollable, not
        // off-screen. (user feedback + research 2026-06-12)
        VStack(spacing: DS.row) {
            header

            DSSegmented(selection: $model.layout, options: DashboardLayout.allCases) { $0.label }
                .padding(.horizontal, 2)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.section) {
                    if let snapshot = model.snapshot {
                        content(snapshot)
                    } else {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
            }
            .frame(maxHeight: 560)
            .fixedSize(horizontal: false, vertical: true)   // size to content, up to the cap

            footer
        }
        .padding(DS.outer)
        .frame(width: 320)
        .steamBackground(level: headlineLevel, isOver: headlineOver, scheme: scheme)
        .tint(Color(hex: model.settings.palette.accentHex))
    }

    /// Headline window's risk drives the 김 서림 background (broth glow + steam plume).
    private var headlineLevel: String { model.snapshot?.headlineWindow?.riskLevel ?? "calm" }
    private var headlineOver: Bool { model.snapshot?.headlineWindow?.isOver ?? false }

    /// Hero header: chip + title (row 1) · hero % right-aligned · demoted bar ·
    /// persistent status + reset (DESIGN_SYSTEM §3.1/3.3).
    /// Slim brand strip — mascot + wordmark + plan. The hero % now lives in the hero card.
    private var header: some View {
        HStack(spacing: DS.intra) {
            // Wordmark only — the kaomoji mascot chip was decorative clutter (design feedback
            // 2026-06-12). 먹방 정체성은 완식 카피/모델 캐스트에 남고, 헤더는 깔끔하게.
            Text("TokenMukbang").font(DS.titleFont).foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            if let plan = model.snapshot?.planLabel {
                // Ghost chip (outline, no fill) — it's metadata, not status; must not grab
                // a fixation before the hero % (design-critique r2).
                Text(plan).font(DS.captionFont.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(.secondary.opacity(0.35), lineWidth: 1))
                    .fixedSize()
            }
            // Gear → the standard macOS Settings window (⌘,). Settings is not a popover mode
            // (native convention — research 2026-06-12).
            Button {
                NSApp.setActivationPolicy(.regular)   // accessory app can't front a window otherwise
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("환경설정 (⌘,)")
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func content(_ snapshot: UsageSnapshot) -> some View {
        // Error always surfaces (it blocks all tabs); the pace warning is dashboard-only
        // so History/Settings aren't cluttered by it (design-critique: cross-tab redundancy).
        if let error = snapshot.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        switch model.layout {
        case .dashboard: dashboardLayout(snapshot)
        case .history: HistoryBrowserView(model: model)
        }
    }

    /// Dashboard = 김 서림 composition: hero window card · two side-by-side window cards ·
    /// sessions card (mockup 04-steam). Cards are raised GlassTiles; risk shows as steam.
    /// MODEL HISTORY intentionally lives ONLY in the History tab now (was duplicated here).
    @ViewBuilder
    private func dashboardLayout(_ snapshot: UsageSnapshot) -> some View {
        let headline = snapshot.headlineWindow
        let secondary = snapshot.windows.filter { $0.kind != headline?.kind }.prefix(2)

        if let w = headline {
            HeroWindowCard(window: w, zone: model.headlineZone, now: now, scheme: scheme)
        }
        // Pace warning ("이 속도면 N시간 뒤 완식") — unique time-to-full signal, dashboard-only.
        // Hugs the hero it describes (pull up, small push down) so it reads as the hero's
        // caption, not the mini-cards' header (design-critique r3).
        if let hours = snapshot.windows.compactMap(\.paceWarningHours).min() {
            Label(MukbangCopy.event(.paceWarning(hoursToFull: hours)), systemImage: "flame.fill")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, -4)
        }
        if !secondary.isEmpty {
            HStack(spacing: DS.row) {
                ForEach(Array(secondary), id: \.kind) { w in
                    MiniWindowCard(window: w, scheme: scheme)
                }
                if secondary.count == 1 { Spacer() }   // keep a single card left-sized
            }
        }
        if !snapshot.sessions.isEmpty {
            GlassTile(scheme: scheme) {
                VStack(alignment: .leading, spacing: DS.intra) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("SESSIONS").dsEyebrow()
                        Spacer()
                        Text("\(snapshot.sessions.count)").font(DS.captionFont).foregroundStyle(.tertiary)
                    }
                    ForEach(snapshot.sessions) { session in
                        SessionRowView(session: session) { model.focusSession(session) }
                    }
                }
                .padding(DS.section)
            }
        }
    }

    /// Footer = a thin utility row only (refresh · 관전 · quit). Navigation moved to the TOP
    /// segmented toggle; the bottom is just quiet utilities, hairline-separated from content
    /// (native menu-bar convention — research 2026-06-12).
    private var footer: some View {
        VStack(spacing: 8) {
            Rectangle().fill(Steam.hairline(scheme)).frame(height: 1)
                .padding(.horizontal, 4)
            actionRow
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            IconGlassButton(symbol: "arrow.clockwise", help: "새로고침", scheme: scheme) {
                Task { await model.refresh(); await model.loadTokenHistory() }
            }
            .disabled(model.isRefreshing)
            .opacity(model.isRefreshing ? 0.5 : 1)

            IconGlassButton(symbol: "rectangle.on.rectangle", help: "관전 오버레이", scheme: scheme) {
                model.overlay.toggle()
            }

            Spacer(minLength: 0)

            // 종료 is neutral ink — red is reserved for the risk channel (design-critique r2).
            IconGlassButton(symbol: "power", help: "종료", scheme: scheme) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Footer chrome (utility actions)

/// A compact icon-only glass action button (~30pt) — the label lives in a tooltip so
/// the footer stays one thin row (design-critique r2: bottom chrome was too tall).
struct IconGlassButton: View {
    let symbol: String
    let help: String
    let scheme: ColorScheme
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 28)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(.white.opacity(scheme == .light ? 0.45 : 0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - 김 서림 window cards (mockup 04-steam composition)

/// 윈도우 표시명: "5h"→"5H", "Sonnet 7d"→"SONNET 7D".
private func windowTitle(_ label: String) -> String { label.uppercased() }

/// 위험 상태 칩 — risk dot + 단어(CALM/WATCH/WARNING/CRITICAL/OVER).
struct StatusChip: View {
    let level: String
    let over: Bool
    let scheme: ColorScheme
    var body: some View {
        let c = RiskTone.color(level: level, over: over, scheme: scheme)
        // A real pill (faint risk-tinted bg) so the top-priority state reads as status,
        // not floating text (design-critique r3).
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(over ? "OVER" : level.uppercased())
                .font(.system(size: 9.5, weight: .bold)).tracking(0.4)
                .foregroundStyle(c)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(c.opacity(0.14), in: Capsule())
    }
}

/// 히어로 윈도우 카드 — 큰 %, 리셋, 풀 게이지. 가장 임박한 윈도우(headline).
struct HeroWindowCard: View {
    let window: UsageSnapshot.Window
    let zone: MukbangZone
    let now: Date
    let scheme: ColorScheme

    var body: some View {
        GlassTile(scheme: scheme) {
            VStack(alignment: .leading, spacing: DS.row) {
                HStack {
                    Text(windowTitle(window.label) + " WINDOW").dsEyebrow()
                    Spacer()
                    StatusChip(level: window.riskLevel, over: window.isOver, scheme: scheme)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(Formatting.percent(window.utilization))
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                        .lineLimit(1).fixedSize()
                    Spacer()
                    // Stronger than .secondary — over the warm hero tint, secondary ink dropped
                    // below comfortable contrast on a light wallpaper (design-critique r3).
                    Text(MukbangCopy.reset(to: window.resetsAt, from: now))
                        .font(DS.resetFont).foregroundStyle(.primary.opacity(0.72))
                }
                GaugeBar(window: window, scheme: scheme, height: 8)
                Text(MukbangCopy.status(for: zone))
                    .font(DS.captionFont).foregroundStyle(.primary.opacity(0.6))
            }
            .padding(DS.section)
        }
    }
}

/// 보조 윈도우 카드 — 라벨 · % · 작은 게이지 · 상태 단어. 7d/Sonnet 나란히.
struct MiniWindowCard: View {
    let window: UsageSnapshot.Window
    let scheme: ColorScheme

    var body: some View {
        GlassTile(scheme: scheme) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    // Card identity — stronger than the tertiary eyebrow, which ghosted out
                    // on the frosted card (design-critique r3).
                    Text(windowTitle(window.label))
                        .font(.system(size: 10.5, weight: .semibold)).tracking(0.5).textCase(.uppercase)
                        .foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Text(Formatting.percent(window.utilization))
                        .font(.system(size: 19, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                GaugeBar(window: window, scheme: scheme)
                // Status word carries its risk chroma at readable weight (was too faint).
                Text(window.riskLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(RiskTone.color(level: window.riskLevel, over: window.isOver, scheme: scheme))
                    .lineLimit(1)
            }
            .padding(DS.section)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

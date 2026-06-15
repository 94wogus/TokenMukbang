import SwiftUI
import AppKit
import TokenMukbangKit

/// The app's main window — a **sidebar + detail** layout (ADR-0019; sidebar structure 2026-06-15).
/// Left rail picks the section (Now / History / Settings); the detail pane shows it and **scrolls
/// independently**, so different content heights are irrelevant and the window resizes freely like a
/// real app. This replaces the cramped tabbed dropdown whose per-tab height differences fought the
/// container. Glass (behind-window blur + theme wash) spans the whole window.
struct AppShellView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private let now = Date()

    private var mood: ThemeMood {
        ThemeMood.resolve(model.settings.theme, scheme, accent: Color(hex: model.settings.palette.accentHex))
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(minWidth: 600, minHeight: 440)
        .environment(\.themeMood, mood)
        .background {
            ZStack {
                VisualEffectBackground(alpha: model.settings.glassOpacity)   // desktop blur (glass)
                mood.baseWash                                                // theme room wash
                mood.accent.opacity(scheme == .light ? 0.10 : 0.16)         // chromatic theme tint
            }
            .ignoresSafeArea()
        }
        .tint(mood.accent)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Brand: app-icon-style logo mark (theme accent + 먹방 fork.knife) + wordmark + plan as
            // a subtitle (the floating "Max" pill read as misplaced — user 2026-06-15). Top padding
            // clears the traffic lights that float over the sidebar's top-left.
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(mood.accent.gradient)
                    .frame(width: 30, height: 30)
                    .overlay(Image(systemName: "fork.knife")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white))
                    .shadow(color: mood.accent.opacity(0.40), radius: 3, y: 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text("TokenMukbang")
                        .font(.system(size: 13.5, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if let plan = model.snapshot?.planLabel {
                        Text("\(plan) plan")
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            .padding(.top, 28).padding(.horizontal, 12).padding(.bottom, 10)

            VStack(spacing: 2) {
                ForEach(DashboardLayout.allCases) { item in sidebarRow(item) }
            }
            .padding(.top, 14)
            .padding(.horizontal, 8)

            Spacer(minLength: 0)

            // Utility actions pinned to the bottom of the rail.
            HStack(spacing: 8) {
                IconGlassButton(symbol: "arrow.clockwise", help: "Refresh", scheme: scheme) {
                    Task { await model.refresh(); await model.loadTokenHistory() }
                }
                .disabled(model.isRefreshing).opacity(model.isRefreshing ? 0.5 : 1)
                IconGlassButton(symbol: "rectangle.on.rectangle", help: "Watch overlay", scheme: scheme) {
                    model.overlay.toggle()
                }
                Spacer(minLength: 0)
                IconGlassButton(symbol: "power", help: "Quit", scheme: scheme) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(12)
        }
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.black.opacity(scheme == .light ? 0.03 : 0.10))   // faint rail scrim
    }

    private func sidebarRow(_ item: DashboardLayout) -> some View {
        let on = model.layout == item
        return HStack(spacing: 9) {
            Image(systemName: icon(for: item)).font(.system(size: 12, weight: .medium)).frame(width: 18)
            Text(item.label).font(.system(size: 13, weight: on ? .semibold : .regular)).lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(on ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(on ? AnyShapeStyle(mood.accent.opacity(0.22)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { model.layout = item }
    }

    private func icon(for item: DashboardLayout) -> String {
        switch item {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .history:   return "chart.bar.fill"
        case .settings:  return "gearshape.fill"
        }
    }

    // MARK: - Detail

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.section) {
                if let error = model.snapshot?.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                switch model.layout {
                case .dashboard:
                    if let snapshot = model.snapshot {
                        NowDashboard(model: model, snapshot: snapshot, now: now, scheme: scheme)
                    } else {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 24)
                    }
                case .history:  HistoryBrowserView(model: model)
                case .settings: SettingsView(model: model)
                }
            }
            .frame(maxWidth: 520, alignment: .leading)     // cap content width for readability
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
            .padding(.top, 12)   // traffic lights sit over the sidebar, not here → minimal top room
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scrollIndicators(.never)
    }
}

/// The "Now" detail pane — hero window card · pace warning · secondary window cards · sessions.
/// (Extracted from the old tabbed dropdown's dashboard so the sidebar shell can host it.)
struct NowDashboard: View {
    @ObservedObject var model: AppModel
    let snapshot: UsageSnapshot
    let now: Date
    let scheme: ColorScheme

    var body: some View {
        let headline = snapshot.headlineWindow
        let secondary = snapshot.windows.filter { $0.kind != headline?.kind }.prefix(2)
        VStack(alignment: .leading, spacing: DS.section) {
            if let w = headline {
                HeroWindowCard(window: w, zone: model.headlineZone, now: now, scheme: scheme)
            }
            if let hours = snapshot.windows.compactMap(\.paceWarningHours).min() {
                Label(MukbangCopy.event(.paceWarning(hoursToFull: hours)), systemImage: "flame.fill")
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.top, -4)
            }
            if !secondary.isEmpty {
                HStack(spacing: DS.row) {
                    ForEach(Array(secondary), id: \.kind) { w in MiniWindowCard(window: w, scheme: scheme) }
                    if secondary.count == 1 { Spacer() }
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
    }
}

import SwiftUI
import ClaudeUsageKit

/// The dropdown panel shown when the menu-bar item is clicked.
struct MenuContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    private let now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.section) {
            header

            if let snapshot = model.snapshot {
                content(snapshot)
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            }

            footer
        }
        .padding(DS.outer)
        .frame(width: 320)
        .background(.regularMaterial)
        .tint(Color(hex: model.settings.palette.accentHex))
    }

    /// Hero header: chip + title (row 1) · hero % right-aligned · demoted bar ·
    /// persistent status + reset (DESIGN_SYSTEM §3.1/3.3).
    private var header: some View {
        let w = model.snapshot?.headlineWindow
        return VStack(alignment: .leading, spacing: DS.row) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.menuBarMascot)
                    .font(.system(size: 12, design: .rounded))
                    .lineLimit(1).fixedSize()
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.quaternary.opacity(0.5), in: Capsule())
                Text("TokenMukbang").font(DS.titleFont)
                if let plan = model.snapshot?.planLabel {
                    Text(plan).font(DS.captionFont.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                if let w {
                    Text(Formatting.percent(w.utilization))
                        .font(DS.heroFont)
                        .foregroundStyle(Color(.labelColor))
                }
            }
            if let w {
                GaugeBar(window: w, scheme: scheme)
                HStack(alignment: .firstTextBaseline) {
                    Text(MukbangCopy.status(for: model.headlineZone))
                        .font(DS.bodyFont).foregroundStyle(.secondary)
                    Spacer()
                    Text(MukbangCopy.reset(to: w.resetsAt, from: now))
                        .font(DS.resetFont).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ snapshot: UsageSnapshot) -> some View {
        if let error = snapshot.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        // Pace warning for the most-urgent window (T2.2): "이 속도면 N시간 뒤 완식".
        if let hours = snapshot.windows.compactMap(\.paceWarningHours).min() {
            Label(MukbangCopy.event(.paceWarning(hoursToFull: hours)), systemImage: "flame.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        switch model.layout {
        case .focus: focusLayout(snapshot)
        case .compact: compactLayout(snapshot)
        case .classic: classicLayout(snapshot)
        case .history: HistoryBrowserView(model: model)
        case .settings: SettingsView(model: model)
        }
    }

    /// Focus: only the headline window, large.
    @ViewBuilder
    private func focusLayout(_ snapshot: UsageSnapshot) -> some View {
        if let w = snapshot.headlineWindow {
            let risk = RiskTone.color(level: w.riskLevel, over: w.isOver, scheme: scheme)
            VStack(alignment: .leading, spacing: 6) {
                Text(w.label).font(.caption).foregroundStyle(.secondary)
                Text(MukbangCopy.headline(utilization: w.utilization))
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(risk)
                GaugeBar(window: w, scheme: scheme, height: 8)
                Text(MukbangCopy.reset(to: w.resetsAt, from: now))
                    .font(.caption).foregroundStyle(.secondary)
                // 7-day usage graph for the headline window (T3.2).
                MiniSparkline(values: model.sparkline(forKind: w.kind).map(\.value), color: risk)
                    .frame(height: 40)
                    .padding(.top, 4)
            }
        }
    }

    /// Compact: condensed window rows + a one-line session count.
    @ViewBuilder
    private func compactLayout(_ snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 6) {
            ForEach(snapshot.windows, id: \.kind) { UsageRowView(window: $0, now: now) }
        }
        if !snapshot.sessions.isEmpty {
            Text("활성 세션 \(snapshot.sessions.count)개 식사 중")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Classic = Monitoring space (flip tiles + pacing graph + peak day) + sessions.
    @ViewBuilder
    private func classicLayout(_ snapshot: UsageSnapshot) -> some View {
        if !snapshot.windows.isEmpty {
            MonitoringView(model: model, snapshot: snapshot)
        }
        if !snapshot.sessions.isEmpty {
            // The single hairline seam between usage and Agent-Watchers.
            Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 1)
            // The single eyebrow (DESIGN_SYSTEM §3.6).
            HStack(alignment: .firstTextBaseline) {
                Text("관전 중인 세션").dsEyebrow()
                Spacer()
                Text("\(snapshot.sessions.count)").font(DS.captionFont).foregroundStyle(.tertiary)
            }
            .padding(.top, 2)
            VStack(spacing: DS.intra) {
                ForEach(snapshot.sessions) { session in
                    SessionRowView(session: session) { model.focusSession(session) }
                }
            }
        } else {
            Text("관전할 세션이 없습니다.")
                .font(DS.bodyFont).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            // Compact custom tab bar (a 5-segment Picker overflows 320 + breaks).
            HStack(spacing: 2) {
                ForEach(DashboardLayout.allCases) { layout in
                    let on = model.layout == layout
                    Text(layout.label)
                        .font(.system(size: 11, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color(.labelColor) : .secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity)
                        .background(on ? AnyShapeStyle(.background.opacity(0.9)) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                        .onTapGesture { model.layout = layout }
                }
            }
            .padding(2)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))

            HStack {
                Button {
                    Task { await model.refresh(); await model.loadTokenHistory() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)

                Button {
                    model.overlay.toggle()
                } label: {
                    Label("관전", systemImage: "rectangle.on.rectangle")
                }

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .foregroundStyle(.secondary)
            }
            .font(.callout)
        }
    }
}

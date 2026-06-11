import SwiftUI
import ClaudeUsageKit

/// The dropdown panel shown when the menu-bar item is clicked.
struct MenuContentView: View {
    @ObservedObject var model: AppModel
    private let now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let snapshot = model.snapshot {
                content(snapshot)
            } else {
                ProgressView("Loading usage…")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // The terminal-born mascot, chewing (ADR-0009).
                Text(model.menuBarMascot)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(model.menuBarColor)
                Text("TokenMukbang")
                    .font(.headline)
                if let plan = model.snapshot?.planLabel {
                    Text(plan)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                }
            }
            // Status mukbang line for the headline window.
            if model.snapshot?.headlineWindow != nil {
                Text(MukbangCopy.status(for: model.headlineZone))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
    }

    /// Focus: only the headline window, large.
    @ViewBuilder
    private func focusLayout(_ snapshot: UsageSnapshot) -> some View {
        if let w = snapshot.headlineWindow {
            VStack(alignment: .leading, spacing: 6) {
                Text(w.label).font(.caption).foregroundStyle(.secondary)
                Text(MukbangCopy.headline(utilization: w.utilization))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(w.riskColor)
                ProgressView(value: w.fraction).tint(w.riskColor)
                Text(MukbangCopy.reset(to: w.resetsAt, from: now))
                    .font(.caption).foregroundStyle(.secondary)
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

    /// Classic: windows + full clickable session list.
    @ViewBuilder
    private func classicLayout(_ snapshot: UsageSnapshot) -> some View {
        if !snapshot.windows.isEmpty {
            VStack(spacing: 8) {
                ForEach(snapshot.windows, id: \.kind) { UsageRowView(window: $0, now: now) }
            }
        }
        if !snapshot.sessions.isEmpty {
            Divider()
            HStack {
                Text("관전 중인 세션")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(snapshot.sessions.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                ForEach(snapshot.sessions) { session in
                    SessionRowView(session: session) { model.focusSession(session) }
                }
            }
        } else {
            Text("관전할 세션이 없습니다.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Picker("", selection: $model.layout) {
                ForEach(DashboardLayout.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isRefreshing)

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

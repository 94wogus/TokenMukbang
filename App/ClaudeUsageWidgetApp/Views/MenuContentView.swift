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

        if !snapshot.windows.isEmpty {
            VStack(spacing: 8) {
                ForEach(snapshot.windows, id: \.kind) { window in
                    UsageRowView(window: window, now: now)
                }
            }
        }

        if !snapshot.sessions.isEmpty {
            Divider()
            HStack {
                Text("Active sessions")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(snapshot.sessions.count)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 6) {
                ForEach(snapshot.sessions) { session in
                    SessionRowView(session: session) {
                        model.focusSession(session)
                    }
                }
            }
        } else {
            Text("No active Claude Code sessions.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
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

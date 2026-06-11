import SwiftUI
import ClaudeUsageKit

/// One usage window row: label, progress bar tinted by risk, %, reset countdown.
struct UsageRowView: View {
    let window: UsageSnapshot.Window
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Text(window.label)
                .font(.system(.body).weight(.medium))
                .frame(width: 78, alignment: .leading)

            GaugeBar(window: window, scheme: scheme)
                .frame(maxWidth: .infinity)

            Text(Formatting.percent(window.utilization))
                .font(.system(.body).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color(.labelColor))
                .frame(width: 42, alignment: .trailing)

            Text(Formatting.countdown(to: window.resetsAt, from: now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }
}

/// One active-session row: a risk-colored dot (the meaning channel) + project name,
/// then a clean right value column (neutral ctx% · tty). Clickable to focus.
struct SessionRowView: View {
    let session: UsageSnapshot.Session
    let onFocus: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: onFocus) {
            HStack(spacing: DS.row) {
                // Color rides the dot only — context fill mapped onto the risk palette.
                Circle()
                    .fill(RiskTone.contextColor(fraction: session.contextFraction, scheme: scheme))
                    .frame(width: 8, height: 8)
                Text(session.projectName)
                    .font(DS.bodyFont)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: DS.row)
                // ctx% — neutral text (the dot already says the state); right column.
                Text(session.contextFraction.map { "ctx \(Formatting.percent(fraction: $0))" } ?? "ctx —")
                    .font(DS.captionFont.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
                Text(session.tty ?? "—")
                    .font(DS.captionFont.monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .frame(width: 56, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Focus this session's terminal window")
    }
}

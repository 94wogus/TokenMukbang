import SwiftUI
import TokenMukbangKit

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
    @Environment(\.themeMood) private var mood

    var body: some View {
        Button(action: onFocus) {
            HStack(spacing: DS.row) {
                // Color rides the dot only — context fill mapped onto the risk palette, gently
                // pulled on-theme to match the rest of the UI (user feedback 2026-06-12).
                Circle()
                    .fill(mood.themedRisk(RiskTone.contextColor(fraction: session.contextFraction, scheme: scheme)))
                    .frame(width: 8, height: 8)
                Text(session.projectName)
                    .font(DS.bodyFont)
                    .lineLimit(1).truncationMode(.tail)
                    .layoutPriority(1)          // let the name take the row's free width
                Spacer(minLength: DS.row)
                // ctx% — neutral text (the dot already says the state). The tty was glance-
                // altitude noise → moved to the tooltip (design-critique r3).
                Text(session.contextFraction.map { "ctx \(Formatting.percent(fraction: $0))" } ?? "ctx —")
                    .font(DS.captionFont.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("터미널 포커스 · \(session.tty ?? "tty 없음")")
    }
}

import SwiftUI
import ClaudeUsageKit

/// One usage window row: label, progress bar tinted by risk, %, reset countdown.
struct UsageRowView: View {
    let window: UsageSnapshot.Window
    let now: Date

    var body: some View {
        HStack(spacing: 10) {
            Text(window.label)
                .font(.system(.body, design: .rounded).weight(.medium))
                .frame(width: 78, alignment: .leading)

            ProgressView(value: window.fraction)
                .tint(window.riskColor)
                .frame(maxWidth: .infinity)

            Text(Formatting.percent(window.utilization))
                .font(.system(.body, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(window.riskColor)
                .frame(width: 42, alignment: .trailing)

            Text(Formatting.countdown(to: window.resetsAt, from: now))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
        }
    }
}

/// One active-session row: project, context-fill gauge, terminal — clickable to focus.
struct SessionRowView: View {
    let session: UsageSnapshot.Session
    let onFocus: () -> Void

    var body: some View {
        Button(action: onFocus) {
            HStack(spacing: 8) {
                Circle()
                    .fill(session.contextColor)
                    .frame(width: 8, height: 8)
                Text(session.projectName)
                    .font(.system(.body, design: .rounded))
                    .lineLimit(1)
                Spacer()
                if let f = session.contextFraction {
                    Text("ctx \(Formatting.percent(fraction: f))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(session.contextColor)
                } else {
                    Text("ctx —").font(.caption).foregroundStyle(.secondary)
                }
                Text(session.tty ?? "—")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Focus this session's terminal window")
    }
}

import SwiftUI
import TokenMukbangKit

/// Now-tab **Claude Code activity** card (ADR-0023 follow-up): the last 7 days of what Claude
/// Code actually *did* — edit-acceptance rate, lines written, commits / PRs, active time — read
/// from the local OTLP telemetry the receiver ingests. This is the "reflection mirror" payoff
/// (`docs/VISION.md`): you opted into telemetry, here's your data back, locally.
///
/// Shown **only when telemetry is enabled** (opt-in, off by default — ADR-0023), so the majority
/// who haven't opted in never see an empty card. Enabled-but-no-data shows a waiting state, since
/// Claude Code must be restarted after the settings.json auto-wire (ADR-0024 Slice 1) takes effect.
struct TelemetryActivityCard: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GlassTile(scheme: scheme) {
            VStack(alignment: .leading, spacing: DS.intra) {
                HStack(alignment: .firstTextBaseline) {
                    Text("CLAUDE CODE").dsEyebrow()
                    Spacer()
                    Text("last 7d").font(DS.captionFont).foregroundStyle(.tertiary)
                }
                if let d = model.telemetryDigest, d.hasData {
                    body(d)
                } else {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Waiting for Claude Code telemetry — restart Claude Code if you just enabled it.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(DS.section)
        }
    }

    @ViewBuilder
    private func body(_ d: TelemetryDigest) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let rate = d.acceptanceRate {
                Text("\(Int((rate * 100).rounded()))%").font(.system(size: 24, weight: .bold))
                Text("edits accepted").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(Self.activeTime(d.activeTimeSeconds)).font(.system(size: 24, weight: .bold))
                Text("active").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if d.acceptanceRate != nil {
                Text(Self.activeTime(d.activeTimeSeconds) + " active")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        // Lines added / removed — green/red carry the sign, the connective stays quiet.
        (Text(Self.signed(d.linesAdded, "+")).fontWeight(.semibold).foregroundStyle(.green)
         + Text(" / ").foregroundStyle(.secondary)
         + Text(Self.signed(d.linesRemoved, "−")).fontWeight(.semibold).foregroundStyle(.red)
         + Text(" lines").foregroundStyle(.secondary))
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 8) {
            stat("\(d.commits)", d.commits == 1 ? "commit" : "commits")
            Text("·").foregroundStyle(.tertiary)
            stat("\(d.pullRequests)", d.pullRequests == 1 ? "PR" : "PRs")
            if d.editsAccepted + d.editsRejected > 0 {
                Text("·").foregroundStyle(.tertiary)
                stat("\(d.editsAccepted + d.editsRejected)", "edits")
            }
        }
        .font(DS.captionFont)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        (Text(value).fontWeight(.semibold).foregroundStyle(.primary)
         + Text(" \(label)").foregroundStyle(.secondary))
    }

    /// "1,234" with thousands grouping; `sign` ("+"/"−") prefixes the magnitude.
    private static func signed(_ n: Int, _ sign: String) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return sign + (f.string(from: NSNumber(value: n)) ?? "\(n)")
    }

    /// Seconds → "4h 12m" / "37m" / "45s".
    private static func activeTime(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s >= 3600 { return "\(s / 3600)h \((s % 3600) / 60)m" }
        if s >= 60 { return "\(s / 60)m" }
        return "\(s)s"
    }
}

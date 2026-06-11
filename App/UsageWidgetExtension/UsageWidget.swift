import WidgetKit
import SwiftUI
import ClaudeUsageKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
}

/// Reads the snapshot the app cached in the shared container. The widget never
/// touches Keychain or the network — it only renders what the app last wrote.
struct UsageProvider: TimelineProvider {
    private let store = SharedStore()

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), snapshot: store.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: Date(), snapshot: store.read())
        // Refresh roughly every 15 minutes; the app also nudges reloads on poll.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct UsageWidget: Widget {
    let kind = "ClaudeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Usage")
        .description("Live Claude usage limits and active sessions.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct UsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        if let snapshot = entry.snapshot, snapshot.error == nil, let headline = snapshot.headlineWindow {
            switch family {
            case .systemSmall: SmallWidget(headline: headline, plan: snapshot.planLabel, now: entry.date)
            default: MediumWidget(snapshot: snapshot, now: entry.date)
            }
        } else {
            UnavailableView(message: entry.snapshot?.error)
        }
    }
}

private struct SmallWidget: View {
    let headline: UsageSnapshot.Window
    let plan: String?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(MukbangZone.forUtilization(headline.utilization).restingFace)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(headline.riskColor)
                Text("먹방").font(.caption.weight(.semibold))
                Spacer()
                if let plan { Text(plan).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            // Gauge read as an emptying table: "NN% 완식" (ADR-0009).
            Text(MukbangCopy.headline(utilization: headline.utilization))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(headline.riskColor)
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(headline.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            ProgressView(value: headline.fraction).tint(headline.riskColor)
            Text(MukbangCopy.reset(to: headline.resetsAt, from: now))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct MediumWidget: View {
    let snapshot: UsageSnapshot
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text(MukbangZone.forUtilization(snapshot.headlineWindow?.utilization ?? 0).restingFace)
                        .font(.system(.caption2, design: .monospaced))
                    Text("TokenMukbang").font(.caption.weight(.semibold))
                }
                ForEach(snapshot.windows.prefix(3), id: \.kind) { w in
                    HStack(spacing: 6) {
                        Text(w.label).font(.caption2).frame(width: 58, alignment: .leading)
                        ProgressView(value: w.fraction).tint(w.riskColor)
                        Text(Formatting.percent(w.utilization))
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(w.riskColor)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !snapshot.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sessions").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(snapshot.sessions.prefix(3)) { s in
                        HStack(spacing: 4) {
                            Circle().fill(s.contextColor).frame(width: 6, height: 6)
                            Text(s.projectName).font(.caption2).lineLimit(1)
                            Spacer(minLength: 2)
                            if let f = s.contextFraction {
                                Text(Formatting.percent(fraction: f))
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(width: 130, alignment: .leading)
            }
        }
    }
}

private struct UnavailableView: View {
    let message: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.bottom.0percent")
                .font(.title2).foregroundStyle(.secondary)
            Text(message ?? "Open Claude Usage Widget to load data.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(8)
    }
}

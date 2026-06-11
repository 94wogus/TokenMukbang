import SwiftUI
import ClaudeUsageKit

/// Compact token count, e.g. 1.2k / 3.4M. Shared by the History views.
private func fmtTokens(_ n: Int) -> String {
    n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1_000_000)
        : n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
}
/// "M/d" day formatter shared by the History views.
private let historyDayFmt: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "M/d"; return f
}()

/// One window's 7-day usage graph: label + current "완식" + sparkline.
struct UsageGraphView: View {
    @ObservedObject var model: AppModel
    let kind: String
    let label: String

    private var window: UsageSnapshot.Window? {
        model.snapshot?.windows.first { $0.kind == kind }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label).font(.caption.weight(.medium))
                Spacer()
                if let w = window {
                    Text(MukbangCopy.headline(utilization: w.utilization))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(w.riskColor)
                }
            }
            MiniSparkline(values: model.sparkline(forKind: kind).map(\.value),
                          color: window?.riskColor ?? .secondary)
                .frame(height: 34)
        }
    }
}

/// History browser (T3.3): filter by model cast, show each window's 7-day graph.
struct HistoryBrowserView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let buckets = model.historyTokenBuckets
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("식단 기록")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Picker("", selection: $model.historyModelFilter) {
                    Text("전체").tag(ModelCast?.none)
                    ForEach(ModelCast.allCases, id: \.self) { cast in
                        Text(cast.modelName).tag(ModelCast?.some(cast))
                    }
                }
                .pickerStyle(.menu).labelsHidden().fixedSize()
            }

            // Timeframe: 24h / 7d / 30d / 90d (C1).
            Picker("", selection: $model.historyTimeframe) {
                ForEach(Timeframe.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            if buckets.isEmpty {
                Text(model.tokenEvents.isEmpty
                     ? "아직 식사 기록이 없습니다. 잠시 후 다시 보세요."
                     : "이 기간/출연진의 기록이 없습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                // Daily token bar chart with hover detail (C2).
                TokenBarChart(buckets: buckets, color: .accentColor)
                // heaviest day + top project (C4).
                if let peak = model.historyHeaviestDay {
                    Label("최다 먹방: \(historyDayFmt.string(from: peak.day)) · \(fmtTokens(peak.tokens)) 토큰",
                          systemImage: "flame.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let tp = model.historyTopProject {
                    Label("대식 프로젝트: \(tp.project) · \(fmtTokens(tp.tokens)) 토큰", systemImage: "trophy")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Daily token-consumption bar chart with on-hover day/total detail (C2).
struct TokenBarChart: View {
    let buckets: [TokenHistory.DayBucket]
    var color: Color = .accentColor
    @State private var hovered: Int?

    var body: some View {
        let maxTokens = max(1, buckets.map(\.tokens).max() ?? 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(buckets.enumerated()), id: \.element.id) { idx, bucket in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(hovered == idx ? color : color.opacity(0.55))
                        .frame(height: max(2, CGFloat(bucket.tokens) / CGFloat(maxTokens) * 64))
                        .onHover { hovered = $0 ? idx : nil }
                }
            }
            .frame(height: 64)
            // Hover detail (or the heaviest bucket by default).
            if let i = hovered, i < buckets.count {
                Text("\(historyDayFmt.string(from: buckets[i].day)) · \(fmtTokens(buckets[i].tokens)) 토큰")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text("막대에 마우스를 올리면 일별 상세")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}

import SwiftUI
import ClaudeUsageKit

/// Compact token count (k/M/B). Shared by the History views.
private func fmtTokens(_ n: Int) -> String { Formatting.tokenCount(n) }
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

/// History browser: per-model breakdown (token volume OR API utilization %) + the
/// daily token chart. The metric toggle exists because the two answer different
/// questions — Opus dominates token volume, while the API util view shows Sonnet.
struct HistoryBrowserView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.row) {
            Text("식단 기록").dsEyebrow()
            // Timeframe (24h/7d/30d/90d) + metric (토큰량 / 사용률) toggles.
            DSSegmented(selection: $model.historyTimeframe, options: Timeframe.allCases) { $0.label }
            DSSegmented(selection: $model.historyMetric, options: HistoryMetric.allCases) { $0.label }

            switch model.historyMetric {
            case .tokens:      tokenBreakdown
            case .utilization: utilizationBreakdown
            }
        }
    }

    // MARK: 토큰량 — per-model consumed-token volume + daily chart

    @ViewBuilder
    private var tokenBreakdown: some View {
        let totals = model.historyCastTotals
        if model.tokenEvents.isEmpty {
            emptyState("아직 식사 기록이 없습니다. 잠시 후 다시 보세요.")
        } else if totals.isEmpty {
            emptyState("이 기간엔 먹은 기록이 없어요.")
        } else {
            let maxTokens = max(1, totals.map(\.tokens).max() ?? 1)
            VStack(spacing: DS.intra) {
                ForEach(totals) { tokenBar($0, maxTokens: maxTokens) }
            }
            tokenChartOrEmpty
        }
    }

    private func tokenBar(_ t: TokenHistory.CastTotal, maxTokens: Int) -> some View {
        let selected = model.historyModelFilter == t.cast && t.cast != nil
        let dimmed = model.historyModelFilter != nil && model.historyModelFilter != t.cast
        return BreakdownBar(
            label: t.cast?.modelName ?? "기타",
            valueText: fmtTokens(t.tokens),
            fraction: Double(t.tokens) / Double(maxTokens),
            color: DS.modelColor(t.cast, scheme: scheme),
            selected: selected, dimmed: dimmed
        )
        .onTapGesture {
            guard let c = t.cast else { return }   // 기타 can't be isolated
            model.historyModelFilter = (model.historyModelFilter == c) ? nil : c
        }
    }

    @ViewBuilder
    private var tokenChartOrEmpty: some View {
        let buckets = model.historyTokenBuckets
        if buckets.isEmpty {
            // A model is selected but it ate 0 tokens this timeframe — the key
            // "Sonnet looks empty" case made explicit instead of just blank.
            emptyState("이 기간 \(model.historyModelFilter?.modelName ?? "") 사용 0 — 턴은 있어도 토큰이 적을 수 있어요.")
        } else {
            // Daily chart takes the selected model's color, or the accent when showing all.
            let chartColor = model.historyModelFilter.map { DS.modelColor($0, scheme: scheme) } ?? Color.accentColor
            TokenBarChart(buckets: buckets, color: chartColor)
            tokenFooter
        }
    }

    @ViewBuilder
    private var tokenFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let peak = model.historyHeaviestDay {
                Label("최다 먹방 \(historyDayFmt.string(from: peak.day)) · \(fmtTokens(peak.tokens)) 토큰", systemImage: "flame")
            }
            if let tp = model.historyTopProject {
                Label("대식 프로젝트 \(tp.project) · \(fmtTokens(tp.tokens)) 토큰", systemImage: "trophy")
            }
        }
        .font(DS.captionFont).foregroundStyle(.tertiary).labelStyle(.titleAndIcon)
    }

    // MARK: 사용률 — per-model API limit %, risk-colored, with sparklines

    @ViewBuilder
    private var utilizationBreakdown: some View {
        let windows = model.historyModelWindows
        if windows.isEmpty {
            emptyState("이 계정/플랜은 API가 모델별 한도(%)를 따로 주지 않아요. ‘토큰량’으로 보세요.")
        } else {
            VStack(spacing: DS.intra) {
                ForEach(windows, id: \.kind) { utilBar($0) }
            }
            VStack(alignment: .leading, spacing: DS.intra) {
                ForEach(windows, id: \.kind) { utilSparkline($0) }
            }
            .padding(.top, 2)
        }
    }

    private func utilBar(_ w: UsageSnapshot.Window) -> BreakdownBar {
        BreakdownBar(
            label: ModelCast.forModel(w.kind)?.modelName ?? w.label,
            valueText: "\(Int(w.utilization.rounded()))%",
            fraction: min(1, w.utilization / 100),
            color: RiskTone.color(level: w.riskLevel, over: w.isOver, scheme: scheme)
        )
    }

    @ViewBuilder
    private func utilSparkline(_ w: UsageSnapshot.Window) -> some View {
        let color = RiskTone.color(level: w.riskLevel, over: w.isOver, scheme: scheme)
        VStack(alignment: .leading, spacing: 1) {
            Text(ModelCast.forModel(w.kind)?.modelName ?? w.label)
                .font(DS.captionFont).foregroundStyle(.secondary)
            MiniSparkline(values: model.sparkline(forKind: w.kind).map(\.value), color: color)
                .frame(height: 26)
        }
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(DS.bodyFont).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

/// One labeled horizontal bar in the per-model breakdown (label · gauge · value).
private struct BreakdownBar: View {
    let label: String
    let valueText: String
    let fraction: Double
    let color: Color
    var selected: Bool = false
    var dimmed: Bool = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: DS.intra) {
            Text(label)
                .font(selected ? DS.bodyFont.weight(.semibold) : DS.bodyFont)
                .foregroundStyle(selected ? Color(.labelColor) : .secondary)
                .frame(width: 56, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(scheme == .light ? DS.gaugeTrackLight : DS.gaugeTrackDark)
                    Capsule().fill(color).frame(width: max(3, geo.size.width * max(0, min(1, fraction))))
                }
            }
            .frame(height: 8)
            Text(valueText)
                .font(DS.valueFont).foregroundStyle(Color(.labelColor))
                .frame(width: 52, alignment: .trailing)
        }
        .opacity(dimmed ? 0.4 : 1)
        .contentShape(Rectangle())
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

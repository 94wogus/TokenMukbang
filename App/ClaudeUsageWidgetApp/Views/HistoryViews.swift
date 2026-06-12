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
            // Legend (color · model · total) + daily bars stacked by model.
            ModelLegend(totals: totals, scheme: scheme)
            StackedTokenBarChart(stacks: model.historyDayStacks)
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

/// A compact legend for the stacked chart: a color swatch · model name · total tokens
/// per model in the timeframe (the per-model numbers, without big bars).
struct ModelLegend: View {
    let totals: [TokenHistory.CastTotal]
    let scheme: ColorScheme

    private var grandTotal: Int { max(1, totals.reduce(0) { $0 + $1.tokens }) }

    var body: some View {
        // Two-up flow so up to 5 models stay compact.
        let cols = [GridItem(.flexible(), spacing: DS.row), GridItem(.flexible(), spacing: DS.row)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 4) {
            ForEach(totals) { t in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.modelColor(t.cast, scheme: scheme))
                        .frame(width: 9, height: 9)
                    Text(t.cast?.modelName ?? "기타").font(DS.captionFont).foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Text(fmtTokens(t.tokens)).font(DS.captionFont.monospacedDigit())
                        .foregroundStyle(Color(.labelColor))
                }
            }
        }
    }
}

/// Daily consumed-token bars **stacked by model** — each day's bar shows its model
/// composition (Opus/Sonnet/Haiku/Fable/기타), so the mix is read straight off the bar.
struct StackedTokenBarChart: View {
    let stacks: [TokenHistory.DayStack]
    @Environment(\.colorScheme) private var scheme
    @State private var hovered: Int?

    var body: some View {
        let maxTotal = max(1, stacks.map(\.total).max() ?? 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(stacks.enumerated()), id: \.element.id) { idx, st in
                    dayBar(st, idx: idx, maxTotal: maxTotal)
                }
            }
            .frame(height: 64, alignment: .bottom)
            hoverDetail
        }
    }

    private func dayBar(_ st: TokenHistory.DayStack, idx: Int, maxTotal: Int) -> some View {
        let dim = hovered != nil && hovered != idx
        return VStack(spacing: 0.5) {
            ForEach(st.segments) { seg in
                RoundedRectangle(cornerRadius: 1)
                    .fill(DS.modelColor(seg.cast, scheme: scheme))
                    .frame(height: max(1, CGFloat(seg.tokens) / CGFloat(maxTotal) * 60))
            }
        }
        .opacity(dim ? 0.45 : 1)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? idx : nil }
    }

    @ViewBuilder
    private var hoverDetail: some View {
        if let i = hovered, i < stacks.count {
            let st = stacks[i]
            let parts = st.segments.map { "\($0.cast?.modelName ?? "기타") \(fmtTokens($0.tokens))" }
            Text("\(historyDayFmt.string(from: st.day)) · \(parts.joined(separator: "  "))")
                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        } else {
            Text("막대에 마우스를 올리면 그날 모델 구성")
                .font(.caption2).foregroundStyle(.tertiary)
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

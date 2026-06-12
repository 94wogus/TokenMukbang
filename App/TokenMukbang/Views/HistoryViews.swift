import SwiftUI
import TokenMukbangKit

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

/// History browser: a token summary (active/cached/hit-rate + trend) over a daily
/// chart **stacked by model**, with a per-model legend. Purely token-based — the API
/// utilization % is a different, account-wide metric and lives in the live views, not
/// here (TokenEater does the same).
struct HistoryBrowserView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: DS.row) {
            // Timeframe is the only top control — the "식단 기록" eyebrow was redundant with
            // the History tab label (design-critique: cross-tab redundancy).
            DSSegmented(selection: $model.historyTimeframe, options: Timeframe.allCases) { $0.label }

            let totals = model.historyCastTotals
            if model.tokenEvents.isEmpty {
                emptyState("아직 식사 기록이 없습니다. 잠시 후 다시 보세요.")
            } else if totals.isEmpty {
                emptyState("이 기간엔 먹은 기록이 없어요.")
            } else {
                // Wrapped in GlassTiles so History shares the dashboard/Settings card
                // aesthetic (design-critique: unify into card containers).
                GlassTile(scheme: scheme) {
                    HistorySummaryView(summary: model.historySummary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.section)
                }
                GlassTile(scheme: scheme) {
                    VStack(alignment: .leading, spacing: DS.row) {
                        Text("모델 구성").dsEyebrow()
                        ModelLegend(totals: totals, scheme: scheme)
                        StackedTokenBarChart(stacks: model.historyDayStacks)
                        tokenFooter
                    }
                    .padding(DS.section)
                }
            }
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
        .font(DS.captionFont).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(DS.bodyFont).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }
}

/// Summary header: hero "active" tokens + 신선/재가열(cached)/캐시적중 breakdown and a
/// trend badge vs the previous period. Surfaces the cache_read volume the stacked bars
/// exclude — the merge that replaces the (confusing, account-wide) API util toggle.
struct HistorySummaryView: View {
    let summary: TokenHistory.Summary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.row) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Formatting.tokenCount(summary.active))
                    .font(DS.heroFont).foregroundStyle(Color(.labelColor))
                Text("신선 토큰").dsEyebrow()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let d = summary.deltaPercent { deltaBadge(d) }
                Text("재가열 \(Formatting.tokenCount(summary.cached)) · 캐시 \(Int((summary.cacheHitRate * 100).rounded()))%")
                    .font(DS.captionFont.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
    }

    private func deltaBadge(_ percent: Double) -> some View {
        let up = percent >= 0
        return HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right").font(.system(size: 8, weight: .bold))
            Text("\(up ? "+" : "")\(Int(percent.rounded()))%").font(DS.captionFont.monospacedDigit().weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

/// A compact legend for the stacked chart: a color swatch · model name · total tokens
/// per model in the timeframe (the per-model numbers, without big bars).
struct ModelLegend: View {
    let totals: [TokenHistory.CastTotal]
    let scheme: ColorScheme
    @Environment(\.themeMood) private var mood

    private var grandTotal: Int { max(1, totals.reduce(0) { $0 + $1.tokens }) }

    var body: some View {
        // Single-column list (swatch · name · right-aligned value) — the old 2-up grid let
        // small values collide and orphan-wrap (design-critique r4).
        VStack(alignment: .leading, spacing: 4) {
            ForEach(totals) { t in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.modelColor(t.cast, scheme: scheme, mood: mood))
                        .frame(width: 9, height: 9)
                    // Name carries its model chroma (matches the dashboard status words) so the
                    // label and its swatch agree at a glance (design-critique r3).
                    Text(t.cast?.modelName ?? "기타")
                        .font(DS.captionFont.weight(.medium))
                        .foregroundStyle(DS.modelColor(t.cast, scheme: scheme, mood: mood))
                    Spacer(minLength: 8)
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
    @Environment(\.themeMood) private var mood
    @State private var hovered: Int?

    var body: some View {
        let maxTotal = max(1, stacks.map(\.total).max() ?? 1)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(stacks.enumerated()), id: \.element.id) { idx, st in
                    dayBar(st, idx: idx, maxTotal: maxTotal)
                }
            }
            .frame(height: 92, alignment: .bottom)        // taller so the chart reads as data, not a strip
            // Baseline rule so the bars sit on the floor, not float (design-critique r2).
            Rectangle().fill(Color(.separatorColor)).frame(height: 1)
            hoverDetail
        }
    }

    private func dayBar(_ st: TokenHistory.DayStack, idx: Int, maxTotal: Int) -> some View {
        let dim = hovered != nil && hovered != idx
        return VStack(spacing: 0.5) {
            ForEach(st.segments) { seg in
                RoundedRectangle(cornerRadius: 1)
                    .fill(DS.modelColor(seg.cast, scheme: scheme, mood: mood))
                    .frame(height: max(1, CGFloat(seg.tokens) / CGFloat(maxTotal) * 88))
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


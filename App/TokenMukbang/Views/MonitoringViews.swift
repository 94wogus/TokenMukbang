import SwiftUI
import TokenMukbangKit

/// A compact window row: label (left) · gauge (flex) · value% on the shared right
/// gutter — the value-column discipline (DESIGN_SYSTEM §3.2/3.5).
struct WindowRow: View {
    let window: UsageSnapshot.Window
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: DS.intra) {
            Text(window.label)
                .font(DS.bodyFont).foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            GaugeBar(window: window, scheme: scheme)
            if let g = RiskTone.glyph(level: window.riskLevel, over: window.isOver) {
                Text(g).font(.system(size: 9))
                    .foregroundStyle(RiskTone.color(level: window.riskLevel, over: window.isOver, scheme: scheme))
            }
            Text("\(Int(window.utilization.rounded()))%")
                .font(DS.valueFont).foregroundStyle(Color(.labelColor))
                .frame(width: 40, alignment: .trailing)
        }
    }
}

/// Pacing-vs-equilibrium graph: the window's trend with a dashed "even pace"
/// reference line, plus how far ahead/behind the eater is (B3).
struct PacingEquilibriumView: View {
    @ObservedObject var model: AppModel
    let window: UsageSnapshot.Window
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let start = model.windowStart(forKind: window.kind)
        let now = Date()
        let equilibrium = start.map {
            PacingCalculator.equilibrium(windowStart: $0, resetsAt: window.resetsAt, now: now)
        }
        let delta = start.map {
            PacingCalculator.delta(utilization: window.utilization, windowStart: $0, resetsAt: window.resetsAt, now: now)
        }

        let series = model.sparkline(forKind: window.kind).map(\.value)
        let hasTrend = series.filter { $0 > 0 }.count >= 2

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("페이스 vs 평형").font(DS.captionFont).foregroundStyle(.secondary)
                Spacer()
                if let d = delta {
                    Text(d > 0 ? "+\(Int(d.rounded()))% 빨리" : "\(Int(d.rounded()))% 여유")
                        .font(DS.captionFont.monospacedDigit())
                        .foregroundStyle(d > 0 ? RiskTone.color(level: "warning", over: false, scheme: scheme)
                                               : RiskTone.color(level: "calm", over: false, scheme: scheme))
                }
            }
            if hasTrend {
                ZStack {
                    MiniSparkline(values: series,
                                  color: RiskTone.color(level: window.riskLevel, over: window.isOver, scheme: scheme))
                    if let equilibrium {
                        GeometryReader { geo in
                            let y = geo.size.height * (1 - CGFloat(min(100, max(0, equilibrium)) / 100))
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: geo.size.width, y: y))
                            }
                            .stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        }
                    }
                }
                .frame(height: 34)
            } else {
                Text("추세 모으는 중…").font(DS.captionFont).foregroundStyle(.tertiary)
            }
        }
    }
}

/// The Monitoring space: flip tiles + pacing-vs-equilibrium graph + peak day +
/// top project (TokenEater Monitoring parity).
struct MonitoringView: View {
    @ObservedObject var model: AppModel
    let snapshot: UsageSnapshot

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "M/d"; return f
    }()
    private static func tokens(_ n: Int) -> String { Formatting.tokenCount(n) }

    /// The hero already shows the headline window — list the rest as compact rows.
    private var secondaryWindows: [UsageSnapshot.Window] {
        let headline = snapshot.headlineWindow?.kind
        return snapshot.windows.filter { $0.kind != headline }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.row) {
            ForEach(secondaryWindows, id: \.kind) { WindowRow(window: $0) }

            if let w = snapshot.headlineWindow {
                PacingEquilibriumView(model: model, window: w)
            }

            if model.peakDay != nil || model.topProject != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let peak = model.peakDay {
                        Label("최다 먹방 \(Self.dayFmt.string(from: peak.day)) · \(Self.tokens(peak.tokens))",
                              systemImage: "flame")
                    }
                    if let tp = model.topProject {
                        Label("대식 프로젝트 \(tp.project) · \(Self.tokens(tp.tokens))", systemImage: "trophy")
                    }
                }
                .font(DS.captionFont).foregroundStyle(.tertiary)
                .labelStyle(.titleAndIcon)
            }
        }
    }
}

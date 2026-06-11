import SwiftUI
import ClaudeUsageKit

/// A flippable tile: front shows "NN% 완식", back shows the 7-day sparkline (B1).
struct FlipTile: View {
    @ObservedObject var model: AppModel
    let window: UsageSnapshot.Window
    @State private var flipped = false

    var body: some View {
        ZStack {
            if flipped {
                MiniSparkline(values: model.sparkline(forKind: window.kind).map(\.value), color: window.riskColor)
                    .padding(6)
            } else {
                VStack(spacing: 0) {
                    Text(window.label)
                        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    Text(Formatting.percent(window.utilization))
                        .font(.system(size: 23, weight: .bold, design: .rounded))
                        .foregroundStyle(window.riskColor)
                        .monospacedDigit()
                    Text("완식").font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .frame(height: 58)
        .frame(maxWidth: .infinity)
        .background(window.riskColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(window.riskColor.opacity(0.28), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { flipped.toggle() } }
        .help("탭하면 7일 추세로 뒤집힙니다")
    }
}

/// Pacing-vs-equilibrium graph: the window's trend with a dashed "even pace"
/// reference line, plus how far ahead/behind the eater is (B3).
struct PacingEquilibriumView: View {
    @ObservedObject var model: AppModel
    let window: UsageSnapshot.Window

    var body: some View {
        let start = model.windowStart(forKind: window.kind)
        let now = Date()
        let equilibrium = start.map {
            PacingCalculator.equilibrium(windowStart: $0, resetsAt: window.resetsAt, now: now)
        }
        let delta = start.map {
            PacingCalculator.delta(utilization: window.utilization, windowStart: $0, resetsAt: window.resetsAt, now: now)
        }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("페이스 vs 평형").font(.caption.weight(.medium))
                Spacer()
                if let d = delta {
                    Text(d > 0 ? "+\(Int(d.rounded()))% 빨리 먹는 중" : "\(Int(d.rounded()))% 여유")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(d > 0 ? Color(hex: "#FF9F0A") : Color(hex: "#34C759"))
                }
            }
            ZStack {
                MiniSparkline(values: model.sparkline(forKind: window.kind).map(\.value), color: window.riskColor)
                if let equilibrium {
                    GeometryReader { geo in
                        let y = geo.size.height * (1 - CGFloat(min(100, max(0, equilibrium)) / 100))
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: y))
                            p.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
            }
            .frame(height: 40)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                ForEach(snapshot.windows, id: \.kind) { FlipTile(model: model, window: $0) }
            }
            if let w = snapshot.headlineWindow {
                PacingEquilibriumView(model: model, window: w)
            }
            if let peak = model.peakDay {
                Label("최다 먹방: \(Self.dayFmt.string(from: peak.day)) · \(Self.tokens(peak.tokens)) 토큰",
                      systemImage: "flame.fill")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let tp = model.topProject {
                Label("대식 프로젝트: \(tp.project) · \(Self.tokens(tp.tokens)) 토큰", systemImage: "trophy")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

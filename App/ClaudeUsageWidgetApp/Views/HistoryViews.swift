import SwiftUI
import ClaudeUsageKit

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

    private var kinds: [String] {
        model.filteredHistoryKinds.filter { kind in
            model.historySamples.contains { $0.utilizations[kind] != nil }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("식단 기록 (7일)")
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

            if kinds.isEmpty {
                Text(model.historySamples.isEmpty
                     ? "아직 식사 기록이 없습니다. 잠시 후 다시 보세요."
                     : "이 출연진의 기록이 없습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(kinds, id: \.self) { kind in
                    UsageGraphView(
                        model: model, kind: kind,
                        label: UsageWindowKind(rawValue: kind)?.label ?? kind
                    )
                }
            }
        }
    }
}

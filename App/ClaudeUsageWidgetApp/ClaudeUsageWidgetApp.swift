import SwiftUI
import ClaudeUsageKit

@main
struct ClaudeUsageWidgetApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            // Menu bar = clean per-window numbers (5h 85% · 7d 47%), each tinted by
            // risk. The 먹방 mascot lives in the popover header + widget, not here.
            if model.menuBarWindows.isEmpty {
                Text("( ﹃ )").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    ForEach(model.menuBarWindows, id: \.kind) { w in
                        Text("\(w.label) \(Formatting.percent(w.utilization))")
                            .foregroundStyle(w.riskColor)
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
        .menuBarExtraStyle(.window)
    }
}

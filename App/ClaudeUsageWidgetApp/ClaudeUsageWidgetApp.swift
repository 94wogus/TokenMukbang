import SwiftUI

@main
struct ClaudeUsageWidgetApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            // Live headline in the menu bar: "5h 32%", tinted by risk.
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.67percent")
                Text(model.menuBarText)
                    .monospacedDigit()
            }
            .foregroundStyle(model.menuBarColor)
        }
        .menuBarExtraStyle(.window)
    }
}

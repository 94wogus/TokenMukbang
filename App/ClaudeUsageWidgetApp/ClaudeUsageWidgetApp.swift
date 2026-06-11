import SwiftUI

@main
struct ClaudeUsageWidgetApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            // The terminal-born mascot lives here: SF Mono kaomoji + percent,
            // chewing on each refresh, tinted by risk (ADR-0009).
            Text(model.menuBarText)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(model.menuBarColor)
        }
        .menuBarExtraStyle(.window)
    }
}

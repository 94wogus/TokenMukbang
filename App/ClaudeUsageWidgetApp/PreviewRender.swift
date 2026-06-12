import SwiftUI
import AppKit
import ClaudeUsageKit

/// Realistic sample data so the headless renderer shows a representative popover.
enum PreviewData {
    private static func window(_ kind: String, _ label: String, _ util: Double, _ resetIn: TimeInterval, _ level: String, pace: Int? = nil) -> UsageSnapshot.Window {
        UsageSnapshot.Window(kind: kind, label: label, utilization: util,
                             resetsAt: Date().addingTimeInterval(resetIn),
                             riskHex: "#000000", riskLabel: level, riskLevel: level,
                             isOver: util >= 100, paceWarningHours: pace)
    }

    static var snapshot: UsageSnapshot {
        var s = UsageSnapshot(
            capturedAt: Date(), planLabel: "Max",
            windows: [
                window("five_hour", "5h", 85, 3600 * 2 + 540, "critical", pace: 1),
                window("seven_day", "7d", 47, 3600 * 24 * 4, "watch"),
                window("seven_day_sonnet", "Sonnet 7d", 11, 3600 * 24 * 4, "calm"),
            ],
            sessions: [
                UsageSnapshot.Session(pid: 1, projectName: "claude-usage-widget", cwd: "/x", tty: "ttys002", contextFraction: 0.80),
                UsageSnapshot.Session(pid: 2, projectName: "arkraft", cwd: "/y", tty: "ttys017", contextFraction: 0.69),
                UsageSnapshot.Session(pid: 3, projectName: "njtransit", cwd: "/z", tty: "ttys025", contextFraction: 0.21),
            ],
            error: nil
        )
        s.headlineSparkline = [8, 14, 22, 31, 40, 52, 61, 70, 78, 85]
        return s
    }

    /// Sample token events so the History breakdown renders a realistic split —
    /// Opus-dominant by volume, with Fable (newly mapped), a little Sonnet, and a
    /// `<synthetic>` turn that lands in the 기타 bucket.
    static var tokenEvents: [TokenEvent] {
        func ev(_ daysAgo: Double, _ model: String, _ tok: Int, _ proj: String) -> TokenEvent {
            TokenEvent(timestamp: Date().addingTimeInterval(-daysAgo * 86400), model: model,
                       inputTokens: tok, outputTokens: tok / 4, cacheReadTokens: tok * 5,
                       cacheCreationTokens: tok / 2, project: proj)
        }
        return [
            ev(0.1, "claude-opus-4-8", 90_000, "arkraft"),
            ev(0.5, "claude-opus-4-7", 60_000, "claude-usage-widget"),
            ev(1.2, "claude-fable-5", 40_000, "arkraft"),
            ev(2.0, "claude-opus-4-8", 55_000, "njtransit"),
            ev(2.4, "claude-sonnet-4-6", 6_000, "claude-usage-widget"),
            ev(3.1, "claude-fable-5", 24_000, "njtransit"),
            ev(4.0, "claude-sonnet-4-6", 4_000, "arkraft"),
            ev(5.0, "<synthetic>", 1_500, "arkraft"),
        ]
    }
}

@MainActor
enum PopoverRenderer {
    /// Render the popover for a layout + scheme to a PNG (no window needed).
    static func render(to path: String, layout: DashboardLayout, scheme: ColorScheme) {
        let model = AppModel(previewSnapshot: PreviewData.snapshot, tokenEvents: PreviewData.tokenEvents)
        model.layout = layout
        let bg = scheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.13)
                                 : Color(red: 0.93, green: 0.93, blue: 0.94)
        let view = MenuContentView(model: model)
            .background(bg)               // solid backing (material renders clear in ImageRenderer)
            .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    /// Render just the menu-bar label on a representative bar strip, so the exact
    /// status-item typography (small dim unit + bold risk-tinted %) is reviewable.
    static func renderMenuBar(to path: String, scheme: ColorScheme) {
        let model = AppModel(previewSnapshot: PreviewData.snapshot)
        // The macOS menu bar is translucent over the desktop — approximate with a
        // light/dark strip so the label's contrast is judged in context.
        let bar = scheme == .dark ? Color(red: 0.16, green: 0.16, blue: 0.17)
                                  : Color(red: 0.97, green: 0.97, blue: 0.98)
        let view = MenuBarLabel(model: model, schemeOverride: scheme)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(bar)
            .environment(\.colorScheme, scheme)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    /// Render all the surfaces we want to review into `dir`.
    static func renderAll(dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for scheme in [ColorScheme.light, .dark] {
            let tag = scheme == .dark ? "dark" : "light"
            renderMenuBar(to: "\(dir)/menubar-\(tag).png", scheme: scheme)
            render(to: "\(dir)/classic-\(tag).png", layout: .classic, scheme: scheme)
            render(to: "\(dir)/history-\(tag).png", layout: .history, scheme: scheme)
            render(to: "\(dir)/settings-\(tag).png", layout: .settings, scheme: scheme)
        }
    }
}

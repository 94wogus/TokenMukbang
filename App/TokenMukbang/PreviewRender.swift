import SwiftUI
import AppKit
import TokenMukbangKit

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
            render(to: "\(dir)/dashboard-\(tag).png", layout: .dashboard, scheme: scheme)
            render(to: "\(dir)/history-\(tag).png", layout: .history, scheme: scheme)
        }
    }
}

/// FAITHFUL capture — renders the real SwiftUI view through AppKit's `cacheDisplay`
/// inside an off-screen NSWindow (so `.regularMaterial`/blur draw for real, unlike
/// `ImageRenderer` which flattens materials). No screen-recording permission needed.
/// A wallpaper backdrop sits behind the popover so glass has something to blur.
/// This is the verification tool: what it shows ≈ the live app.
@MainActor
enum WindowSnapshot {
    /// Stand-in wallpapers to prove the glass adapts to the backdrop (not fixed hex).
    private enum Backdrop: String, CaseIterable {
        case black, white, colorful, neutralDark, neutralLight
        var view: AnyView {
            switch self {
            case .black:  return AnyView(Color.black)
            case .white:  return AnyView(Color(white: 0.96))
            case .colorful: return AnyView(LinearGradient(
                colors: [Color(red: 0.20, green: 0.10, blue: 0.40), Color(red: 0.05, green: 0.30, blue: 0.45),
                         Color(red: 0.55, green: 0.18, blue: 0.30)],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            // HONEST tests — a plain, muted desktop (what most users actually have behind the
            // popover), so the render isn't over-flattered by a colorful wallpaper.
            case .neutralDark:  return AnyView(Color(red: 0.13, green: 0.14, blue: 0.16))
            case .neutralLight: return AnyView(Color(red: 0.86, green: 0.86, blue: 0.84))
            }
        }
        var scheme: ColorScheme { (self == .white || self == .neutralLight) ? .light : .dark }
    }

    static func renderAll(dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // (a) adaptation proof — dashboard over each backdrop (incl. honest plain desktops).
        for bg in Backdrop.allCases {
            render(to: "\(dir)/live-bg-\(bg.rawValue).png", layout: .dashboard, backdrop: bg)
        }
        // (b) every tab over the colorful wallpaper — for IA / redundancy / tab-structure critique.
        let tabs: [(String, DashboardLayout)] = [
            ("dashboard", .dashboard), ("history", .history),
        ]
        for (name, layout) in tabs {
            render(to: "\(dir)/live-tab-\(name).png", layout: layout, backdrop: .colorful)
        }
        // (c) theme mood proof — dashboard over a plain dark AND light desktop, one per theme, so
        // light-first rooms (hanji/mono) are judged in their native scheme too. History in dark only.
        for theme in Theme.allCases {
            render(to: "\(dir)/live-theme-\(theme.rawValue).png", layout: .dashboard,
                   backdrop: .neutralDark, theme: theme)
            render(to: "\(dir)/live-themelight-\(theme.rawValue).png", layout: .dashboard,
                   backdrop: .neutralLight, theme: theme)
            render(to: "\(dir)/live-themehist-\(theme.rawValue).png", layout: .history,
                   backdrop: .neutralDark, theme: theme)
        }
        // (d) Settings window — the redesigned Appearance (theme gallery + preview) and Alerts
        // tabs, in dark & light, plus the custom-accent state, reviewable like the popover.
        renderSettings(to: "\(dir)/live-settings-dark.png", scheme: .dark, theme: .charcoal, tab: .appearance)
        renderSettings(to: "\(dir)/live-settings-light.png", scheme: .light, theme: .hanji, tab: .appearance)
        renderSettings(to: "\(dir)/live-settings-custom.png", scheme: .dark, theme: .custom, tab: .appearance)
        renderSettings(to: "\(dir)/live-settings-alerts.png", scheme: .dark, theme: .obang, tab: .alerts)
    }

    /// Render the Settings window (the controller hosts it at width 360 + 20pt padding).
    private static func renderSettings(to path: String, scheme: ColorScheme, theme: Theme, tab: SettingsTab) {
        var settings = AppSettings.default
        settings.theme = theme
        let model = AppModel(previewSnapshot: PreviewData.snapshot, settings: settings, tokenEvents: PreviewData.tokenEvents)
        let backdrop: Backdrop = scheme == .dark ? .neutralDark : .neutralLight
        let root = ZStack(alignment: .top) {
            backdrop.view.ignoresSafeArea()
            SettingsView(model: model, initialTab: tab).frame(width: 360).padding(20)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 400)
        .environment(\.colorScheme, scheme)

        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 400, height: host.fittingSize.height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    private static func render(to path: String, layout: DashboardLayout, backdrop: Backdrop, theme: Theme = .charcoal) {
        var settings = AppSettings.default
        settings.theme = theme
        let model = AppModel(previewSnapshot: PreviewData.snapshot, settings: settings, tokenEvents: PreviewData.tokenEvents)
        model.layout = layout
        let root = ZStack(alignment: .top) {
            backdrop.view.ignoresSafeArea()             // the "wallpaper" the glass blends with
            MenuContentView(model: model).padding(.top, 28)
        }
        .frame(width: 392, height: 760)
        .environment(\.colorScheme, backdrop.scheme)

        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 392, height: 760)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: backdrop.scheme == .dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}

import SwiftUI
import AppKit
import ClaudeUsageKit

/// Dev helper: when TMK_SHOWWINDOW=1, become a regular app and pin the dashboard
/// window at a fixed top-left spot so it can be screenshotted during design work.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        // Headless design-iteration render: write PNGs of the popover, then quit.
        if let dir = ProcessInfo.processInfo.environment["TMK_RENDER"] {
            PopoverRenderer.renderAll(dir: dir)
            exit(0)
        }
        // Track the *menu bar's* light/dark (wallpaper-aware) so the label colors adapt.
        MenuBarAppearance.shared.start()
        guard ProcessInfo.processInfo.environment["TMK_SHOWWINDOW"] == "1" else { return }
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let win = NSApp.windows.first(where: { $0.title == "TokenMukbang" }),
               let screen = NSScreen.main {
                win.setFrameTopLeftPoint(NSPoint(x: 60, y: screen.frame.height - 60))
                win.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

@main
struct ClaudeUsageWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        // A windowed mirror of the popover — handy as a pinned dashboard, and the
        // only way to screenshot the popover content during design iteration.
        Window("TokenMukbang", id: "dashboard") {
            MenuContentView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

/// Best-effort detector of the **menu bar's** effective appearance — which tracks the
/// wallpaper behind it, unlike `NSApp.effectiveAppearance` (only the app's light/dark
/// mode). It reads the status-item button's `effectiveAppearance`, the exact signal that
/// template menu-bar glyphs use to auto-adapt, and KVO-observes it. SwiftUI's `MenuBarExtra`
/// doesn't expose the `NSStatusItem`, so we locate the button by walking `NSApp.windows`
/// (defensive; falls back to the app appearance if not found). (Research 2026-06-11.)
@MainActor
final class MenuBarAppearance: ObservableObject {
    static let shared = MenuBarAppearance()
    @Published private(set) var isDark: Bool = false
    private var observation: NSKeyValueObservation?

    func start() {
        isDark = NSApp.effectiveAppearance.isMenuBarDark   // seed until the button is found
        attach(retries: 12)
    }

    private func attach(retries: Int) {
        if let button = Self.statusButton() {
            isDark = button.effectiveAppearance.isMenuBarDark
            // effectiveAppearance KVO is delivered on the main thread.
            observation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] btn, _ in
                MainActor.assumeIsolated { self?.isDark = btn.effectiveAppearance.isMenuBarDark }
            }
        } else if retries > 0 {
            // The status item appears shortly after launch — retry briefly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                MainActor.assumeIsolated { self?.attach(retries: retries - 1) }
            }
        }
    }

    private static func statusButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            if let b = window.contentView as? NSStatusBarButton { return b }
            if let b = window.contentView?.subviews.compactMap({ $0 as? NSStatusBarButton }).first { return b }
        }
        return nil
    }
}

extension NSAppearance {
    /// The menu bar's effective light/dark via the canonical `bestMatch` idiom.
    var isMenuBarDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

/// Menu bar: "5h 05%  7d 50%" — the unit (`5h`) is bold but transparent (context), the
/// number+% is the signal: bold, risk-tinted by state. Color is **muted + luminance-pinned
/// to the menu bar's own light/dark** (`MenuBarAppearance`) so it reads on any wallpaper —
/// no outline halo (research 2026-06-11). 2-digit zero-pad keeps width stable.
///
/// IMPORTANT: a SwiftUI `Text` label in `MenuBarExtra` is flattened by the status item
/// (per-run weight/size/color stripped, rendered as a monochrome template). To keep the
/// bold + color we render the label to a **non-template color image** and show that —
/// the same trick used for colored menu-bar icons (DESIGN_SYSTEM §3.4).
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var appearance = MenuBarAppearance.shared
    /// Forces a scheme for the headless renderer; live app follows the menu bar.
    var schemeOverride: ColorScheme? = nil

    // The unit recedes by BOTH size and transparency; the percent is the larger, opaque signal.
    private static let unitFont = Font.system(size: 9.5, weight: .bold).monospacedDigit()
    private static let pctFont  = Font.system(size: 14, weight: .bold).monospacedDigit()

    /// 2-digit zero-padded percent so width never jitters (9%→10%) and `05%` aligns.
    private static func pct(_ utilization: Double) -> String {
        String(format: "%02d%%", Int(utilization.rounded()))
    }

    /// The label as a SwiftUI view (colors + weights are honored here, unlike in the bar).
    @ViewBuilder
    private static func content(_ windows: [UsageSnapshot.Window], scheme: ColorScheme) -> some View {
        // Bold but TRANSPARENT — the unit recedes via low opacity, not a lighter weight.
        let dim = (scheme == .dark ? Color.white : Color.black).opacity(0.45)
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(windows.enumerated()), id: \.offset) { i, w in
                if i > 0 { Text("   ").font(Self.pctFont) }
                Text(w.label + " ")
                    .font(Self.unitFont)
                    .foregroundStyle(dim)
                Text(Self.pct(w.utilization))
                    .font(Self.pctFont)
                    .foregroundStyle(RiskTone.menuBarColor(level: w.riskLevel, over: w.isOver, scheme: scheme))
            }
        }
    }

    /// Render the label to a color (non-template) image so the menu bar preserves it.
    @MainActor
    private func rendered(_ windows: [UsageSnapshot.Window], scheme: ColorScheme) -> NSImage {
        let renderer = ImageRenderer(content: Self.content(windows, scheme: scheme))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = renderer.nsImage ?? NSImage(size: NSSize(width: 1, height: 1))
        img.isTemplate = false   // keep our colors; do not let the bar tint it monochrome
        return img
    }

    var body: some View {
        let windows = model.menuBarWindows
        let scheme: ColorScheme = schemeOverride ?? (appearance.isDark ? .dark : .light)
        if windows.isEmpty {
            Text("· · ·")
        } else {
            Image(nsImage: rendered(windows, scheme: scheme)).renderingMode(.original)
        }
    }
}

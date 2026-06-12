import SwiftUI
import AppKit
import ClaudeUsageKit
import MenuBarExtraAccess

/// Dev helper: when TMK_SHOWWINDOW=1, become a regular app and pin the dashboard
/// window at a fixed top-left spot so it can be screenshotted during design work.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        // Headless design-iteration render: write PNGs of the popover, then quit.
        if let dir = ProcessInfo.processInfo.environment["TMK_RENDER"] {
            PopoverRenderer.renderAll(dir: dir)
            exit(0)
        }
        // FAITHFUL capture (real materials/blur via cacheDisplay) — the verification tool.
        if let dir = ProcessInfo.processInfo.environment["TMK_SNAPSHOT"] {
            WindowSnapshot.renderAll(dir: dir)
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
    @State private var menuBarPresented = false

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        // Must be the FIRST modifier after MenuBarExtra (it's a MenuBarExtra extension).
        // Reaches the real NSStatusItem so we can KVO its (wallpaper-aware) appearance.
        .menuBarExtraAccess(isPresented: $menuBarPresented) { statusItem in
            MenuBarAppearance.shared.attach(statusItem: statusItem)
        }
        .menuBarExtraStyle(.window)

        // Standard macOS Settings window (⌘,) — opened from the popover's gear. Native
        // menu-bar IA puts configuration in its own window, not a popover tab (research
        // 2026-06-12). On close, drop back to .accessory so the Dock icon disappears (the
        // gear flips us to .regular so an accessory app can actually front the window).
        Settings {
            SettingsView(model: model)
                .frame(width: 360)
                .padding(DS.outer)
                .onDisappear { NSApp.setActivationPolicy(.accessory) }
        }

        // A windowed mirror of the popover — handy as a pinned dashboard, and the
        // only way to screenshot the popover content during design iteration.
        Window("TokenMukbang", id: "dashboard") {
            MenuContentView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

/// Tracks the **menu bar's** effective appearance — which follows the *wallpaper* behind it,
/// unlike `NSApp.effectiveAppearance` (only the app's light/dark mode). It KVO-observes the
/// status-item button's `effectiveAppearance` (the exact signal template glyphs auto-adapt
/// to). The `NSStatusItem` comes from `MenuBarExtraAccess` (`.menuBarExtraAccess` closure) —
/// the prior `NSApp.windows` reflection failed because the status window isn't in that list,
/// so it fell back to app mode and never tracked the wallpaper (2026-06-12 research).
@MainActor
final class MenuBarAppearance: ObservableObject {
    static let shared = MenuBarAppearance()
    @Published private(set) var isDark: Bool = false
    private var observation: NSKeyValueObservation?
    private weak var observedButton: NSStatusBarButton?

    /// Seed from the app appearance until the real status button is attached.
    func start() { isDark = NSApp.effectiveAppearance.isMenuBarDark }

    /// Wire to the real status item (from MenuBarExtraAccess) and KVO its wallpaper-aware
    /// appearance. Idempotent — re-attaching the same button is a no-op.
    func attach(statusItem: NSStatusItem) {
        guard let button = statusItem.button, button !== observedButton else { return }
        observedButton = button
        isDark = button.effectiveAppearance.isMenuBarDark
        observation = button.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] btn, _ in
            MainActor.assumeIsolated { self?.isDark = btn.effectiveAppearance.isMenuBarDark }
        }
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

    /// The label as a SwiftUI view (colors + weights honored here, unlike in the bar).
    /// 메뉴바는 가독성 최우선 — 깔끔한 라벨 그대로(김은 팝오버/위젯에서만). 5h/7d 둘 다, 색 %.
    @ViewBuilder
    private static func content(_ windows: [UsageSnapshot.Window], scheme: ColorScheme) -> some View {
        // Unit label recedes by transparency. `scheme` now comes from the REAL menu-bar
        // appearance (MenuBarAppearance via MenuBarExtraAccess), so this adapts to the
        // wallpaper: white-dim on a dark bar, black-dim on a light bar.
        let dim = (scheme == .dark ? Color.white : Color.black).opacity(0.5)
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

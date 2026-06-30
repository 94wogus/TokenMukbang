import SwiftUI
import AppKit
import TokenMukbangKit

/// Creates the menu-bar status item + glass panel, and (dev) handles the render/screenshot
/// branches. The popover is a custom borderless NSPanel (ADR-0018) — `MenuBarExtra(.window)`
/// can't show the desktop behind it (its window is system-managed + opaque).
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Retains the receiver in the headless `TMK_OTLP_TEST` smoke-test branch.
    private var otlpTestReceiver: OTLPReceiver?

    /// Menu-bar accessory app: closing the Settings window (the only SwiftUI window) must NOT
    /// quit the app — the status item keeps it alive. Without MenuBarExtra anchoring the app,
    /// the default "terminate after last window closed" kicked in (user: "setting 끄니깐 꺼짐").
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
        // Headless OTLP receiver smoke test (ADR-0023): start a loopback receiver, print each
        // ingest to stdout, and STAY ALIVE so tools/otlp-smoke.sh can curl a fixture, then kill us.
        // The env value is the port (e.g. TMK_OTLP_TEST=4319). No status item / UI.
        if let portStr = ProcessInfo.processInfo.environment["TMK_OTLP_TEST"] {
            let port = UInt16(portStr) ?? 4318
            // Optional forward target for the forward smoke test (TMK_OTLP_FORWARD=base URL).
            let env = ProcessInfo.processInfo.environment
            let forwarder = env["TMK_OTLP_FORWARD"].flatMap {
                TelemetryForwarder(endpoint: $0, token: env["TMK_OTLP_TOKEN"] ?? "smoke-token")
            }
            let receiver = OTLPReceiver(port: port, forwarder: forwarder)
            receiver.onIngest = { kind, m, e in
                FileHandle.standardOutput.write(Data("INGESTED kind=\(kind) metrics=\(m) events=\(e)\n".utf8))
            }
            receiver.start()
            otlpTestReceiver = receiver
            FileHandle.standardOutput.write(Data("OTLP_TEST_READY port=\(port)\n".utf8))
            return
        }
        // Track the *menu bar's* light/dark (wallpaper-aware) so the label colors adapt, then
        // build the status item + glass panel.
        MenuBarAppearance.shared.start()
        StatusItemController.shared.install()

        if ProcessInfo.processInfo.environment["TMK_SHOWWINDOW"] == "1" {
            NSApp.setActivationPolicy(.regular)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let win = NSApp.windows.first(where: { $0.title == "TokenMukbang" }),
                   let screen = NSScreen.main {
                    win.setFrameTopLeftPoint(NSPoint(x: 60, y: screen.frame.height - 60))
                    win.makeKeyAndOrderFront(nil)
                }
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            // The `Window` scene (a dev/screenshot mirror) would otherwise auto-open at launch —
            // close it so the app stays a pure menu-bar accessory.
            DispatchQueue.main.async {
                NSApp.windows.first(where: { $0.title == "TokenMukbang" })?.close()
            }
        }
    }
}

@main
struct TokenMukbang: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let model = AppModel.shared

    var body: some Scene {
        // The real UI is a controller-owned normal glass NSWindow (StatusItemController, ADR-0019)
        // — Now/History/Settings in one window. This SwiftUI scene is only a dev/screenshot mirror,
        // closed at launch unless TMK_SHOWWINDOW.
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
    private static func content(_ windows: [UsageSnapshot.Window], scheme: ColorScheme, accent: Color) -> some View {
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
                    .foregroundStyle(Self.pctColor(w, scheme: scheme, accent: accent))
            }
        }
    }

    /// Menu-bar % color is **always risk-semantic** — calm green → critical red. (The earlier
    /// "calm = theme accent" made 0% look alarming with a warm accent like Sunset's orange,
    /// user feedback 2026-06-12. The menu bar's job is the danger glance, not the theme.)
    private static func pctColor(_ w: UsageSnapshot.Window, scheme: ColorScheme, accent: Color) -> Color {
        RiskTone.menuBarColor(level: w.riskLevel, over: w.isOver, scheme: scheme)
    }

    /// Render the label to a color (non-template) image so the menu bar preserves it.
    @MainActor
    private func rendered(_ windows: [UsageSnapshot.Window], scheme: ColorScheme, accent: Color) -> NSImage {
        let renderer = ImageRenderer(content: Self.content(windows, scheme: scheme, accent: accent))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = renderer.nsImage ?? NSImage(size: NSSize(width: 1, height: 1))
        img.isTemplate = false   // keep our colors; do not let the bar tint it monochrome
        return img
    }

    var body: some View {
        let windows = model.menuBarWindows
        let scheme: ColorScheme = schemeOverride ?? (appearance.isDark ? .dark : .light)
        let accent = Color(hex: model.settings.palette.accentHex)
        if windows.isEmpty {
            Text("· · ·")
        } else {
            Image(nsImage: rendered(windows, scheme: scheme, accent: accent)).renderingMode(.original)
        }
    }
}

import AppKit
import SwiftUI
import Combine
import TokenMukbangKit

// Menu-bar status item + a single NORMAL glass window (ADR-0019, supersedes ADR-0018's borderless
// NSPanel popover). The old custom NSPanel had to fake everything — transient anchoring, fixed
// heights, "recreate every show" to dodge a stale-opaque bug over full-screen Spaces, etc. A plain
// titled NSWindow with a `.behindWindow` visual-effect background gives the SAME desktop-blur glass
// but is robust (movable, closable, never flips opaque), so all that fragility is gone.

/// App-level actions reachable from AppKit-hosted SwiftUI (no SwiftUI scene environment).
enum AppActions {
    /// Show the main window on the Settings tab (kept for ⌘, / future menu wiring).
    @MainActor static func openSettings() {
        StatusItemController.shared.showMain(selecting: .settings)
    }
}

/// A `.behindWindow` blur as a SwiftUI background — lets a plain non-opaque window show the blurred
/// desktop (real glassmorphism) while the window auto-sizes to SwiftUI content via a hosting
/// controller. `alpha` is the see-through/frost veil (AppSettings.glassOpacity) — being a SwiftUI
/// view, it updates **live** when the setting changes (no manual KVO/subscription).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var alpha: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.blendingMode = .behindWindow
        v.material = material
        v.state = .active                       // never dim to the inactive frost
        v.alphaValue = max(0.1, min(1.0, alpha))
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.state = .active
        v.alphaValue = max(0.1, min(1.0, alpha))
    }
}

/// The main window's SwiftUI root: the dashboard/settings content over the behind-window glass.
/// The theme wash (steamBackground, inside MenuContentView) sits *over* this blur, so the glass
/// reads tinted to the room while the blurred desktop shows through.
private struct MainWindowRoot: View {
    @ObservedObject var model: AppModel
    var body: some View {
        MenuContentView(model: model)
            .background(VisualEffectBackground(alpha: model.settings.glassOpacity).ignoresSafeArea())
    }
}

/// Owns the menu-bar status item (its label image + wallpaper-aware color) and the single glass
/// window. Replaces the `MenuBarExtra(.window)` popover and the old GlassPanel (ADR-0019).
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private let model = AppModel.shared
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var positioned = false
    private var cancellables = Set<AnyCancellable>()

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.action = #selector(toggle)
        item.button?.target = self
        statusItem = item
        MenuBarAppearance.shared.attach(statusItem: item)   // wallpaper-aware label color (KVO)

        // Re-render the label image only when the usage data or the menu-bar appearance changes.
        model.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.renderLabel() }
            .store(in: &cancellables)
        MenuBarAppearance.shared.$isDark
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.renderLabel() }
            .store(in: &cancellables)
        renderLabel()
    }

    private func renderLabel() {
        guard let button = statusItem?.button else { return }
        let scheme: ColorScheme = MenuBarAppearance.shared.isDark ? .dark : .light
        let renderer = ImageRenderer(content: MenuBarLabel(model: model, schemeOverride: scheme))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let img = renderer.nsImage else { return }
        img.isTemplate = false
        button.image = img
        button.imagePosition = .imageOnly
    }

    @objc private func toggle() {
        let w = window ?? makeWindow()
        // Hide only when it's already frontmost; if it's visible-but-behind, bring it forward
        // (a menu-bar click should never feel like it "did nothing").
        if w.isVisible && w.isKeyWindow {
            w.orderOut(nil)
        } else {
            if !positioned { positionUnderStatusItem(w); positioned = true }
            NSApp.activate(ignoringOtherApps: true)
            w.makeKeyAndOrderFront(nil)
        }
    }

    /// Show the window and select a tab (e.g., from ⌘, → Settings).
    func showMain(selecting layout: DashboardLayout) {
        model.layout = layout
        let w = window ?? makeWindow()
        if !positioned { positionUnderStatusItem(w); positioned = true }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    /// Build the single glass window: a plain titled NSWindow made non-opaque with a transparent,
    /// full-size-content titlebar (traffic lights float over the glass), auto-sized to the SwiftUI
    /// content by a hosting controller. The `.behindWindow` blur lives in `MainWindowRoot`.
    private func makeWindow() -> NSWindow {
        let hc = NSHostingController(rootView: MainWindowRoot(model: model))
        hc.sizingOptions = [.preferredContentSize]
        let w = NSWindow(contentViewController: hc)
        w.styleMask = [.titled, .closable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = "TokenMukbang"
        w.isMovableByWindowBackground = true
        w.isOpaque = false                       // load-bearing: lets the behind-window blur show desktop
        w.backgroundColor = .clear
        w.isReleasedWhenClosed = false           // closing just hides; the status item keeps the app alive
        w.hasShadow = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Drop back to .accessory (Dock icon hidden) when the window closes.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                               object: w, queue: .main) { _ in
            MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
        }
        window = w
        return w
    }

    /// Place the window just below the status item on first show (like a menu-bar popover would);
    /// after that it's a normal movable window that remembers where the user left it.
    private func positionUnderStatusItem(_ w: NSWindow) {
        w.layoutIfNeeded()
        guard let button = statusItem?.button, let bwin = button.window else { w.center(); return }
        let rect = bwin.convertToScreen(button.convert(button.bounds, to: nil))
        var x = rect.midX - w.frame.width / 2
        if let vf = bwin.screen?.visibleFrame {
            x = min(max(x, vf.minX + 8), vf.maxX - w.frame.width - 8)
        }
        w.setFrameTopLeftPoint(NSPoint(x: x, y: rect.minY - 6))
    }
}

import AppKit
import SwiftUI
import Combine
import TokenMukbangKit

// Custom status-item + borderless glass NSPanel popover (ADR-0018). The SwiftUI
// `MenuBarExtra(.window)` popover window is system-managed with an opaque material that
// cannot be stripped, so `NSVisualEffectView(.behindWindow)` can never reveal the desktop
// behind it (research 2026-06-12). A borderless, non-opaque NSPanel rooted in a
// `.behindWindow` visual-effect view DOES show the blurred desktop — real glassmorphism.

/// App-level actions reachable from AppKit-hosted SwiftUI (no SwiftUI scene environment).
enum AppActions {
    /// Open Settings via our own controller-owned NSWindow (not the SwiftUI `Settings` scene +
    /// `showSettingsWindow:` selector, which reopened unreliably — opened once, then never again
    /// after close, user 2026-06-12).
    @MainActor static func openSettings() {
        StatusItemController.shared.openSettingsWindow()
    }
}

/// A borderless, non-opaque panel whose content root is a `.behindWindow` visual-effect view
/// — the blurred desktop shows through (the thing MenuBarExtra's popover can't do). The SwiftUI
/// content is hosted by an `NSHostingController` whose view auto-sizes to the content, and the
/// panel tracks that size (no manual fittingSize gymnastics — those collapsed the content).
final class GlassPanel: NSPanel {
    /// Blur layer opacity (0…1). Lower = more transparent + softer blur. Dialed to near-max
    /// transparency per user (2026-06-12). Tune this one number for the see-through/blur balance.
    static let blurStrength: CGFloat = 0.70
    static let panelWidth: CGFloat = 320

    private let hosting: NSHostingController<AnyView>
    private let blur = NSVisualEffectView()
    /// The fixed top-left screen point (just below the status item). On a content-height change
    /// (tab switch) the window must keep its TOP here and grow DOWNWARD — a bare setContentSize
    /// keeps the bottom-left fixed, so the panel jumped upward (user 2026-06-12: "height 문제").
    var anchorTopLeft: NSPoint?

    // Force the window permanently non-opaque — a resize on tab switch was flipping it back to
    // opaque, turning the whole panel into a solid frosted block (user 2026-06-12, Image #7).
    override var isOpaque: Bool { get { false } set {} }

    init<Content: View>(rootView: Content) {
        hosting = NSHostingController(rootView: AnyView(rootView))
        hosting.sizingOptions = [.preferredContentSize]   // view's size follows SwiftUI content
        super.init(contentRect: NSRect(x: 0, y: 0, width: 320, height: 600),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        // --- load-bearing transparency: a transparent window lets the desktop sit directly
        // behind the glass so the glass can refract it (ghostty's Liquid Glass pattern). ---
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        // Hosting view must be non-opaque or it covers the glass (the bug that made the panel
        // read as a flat frosted panel with nothing behind it).
        let host = hosting.view
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor

        let radius: CGFloat = 18
        // `.state = .active` forces the material always-active → never dims to the frosted
        // "inactive" gray on the 2nd show over a full-screen Space (confirmed bug 2026-06-12:
        // glass follows system active state, no public override). The blur is its OWN backmost
        // layer (not the content's parent) and its `alphaValue` is dialed DOWN, so the desktop
        // shows through with *less* blur veil (higher transparency) while the content stays crisp.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 600))
        container.wantsLayer = true
        container.layer?.cornerRadius = radius
        container.layer?.masksToBounds = true
        container.autoresizesSubviews = true

        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.material = .underWindowBackground
        blur.isEmphasized = false
        blur.alphaValue = Self.blurStrength   // <1 → more transparent + softer blur (tunable)
        blur.frame = container.bounds
        blur.autoresizingMask = [.width, .height]
        container.addSubview(blur)

        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)            // content on top, full opacity (crisp)
        contentView = container
        resizeToFit()
    }

    /// Measure the SwiftUI content's ideal height (width pinned) and resize the panel to it — this
    /// is the "content determines the parent height" the preferredContentSize KVO failed to deliver
    /// on tab switches (user 2026-06-12). `sizeThatFits` already reflects the new layout, so we can
    /// resize synchronously (no delay) and animate the frame change for a smooth transition.
    func resizeToFit(animated: Bool = false) {
        var s = hosting.sizeThatFits(in: NSSize(width: Self.panelWidth, height: 10_000))
        s.width = Self.panelWidth
        guard s.height > 10 else { return }
        applyContentSize(s, animated: animated)
    }

    /// Resize to `s`, keeping the TOP edge anchored (grow downward, not upward), then re-assert
    /// transparency (a bare setFrame also left the window opaque on resize — Image #7).
    private func applyContentSize(_ s: NSSize, animated: Bool) {
        let tl = anchorTopLeft ?? NSPoint(x: frame.minX, y: frame.maxY)
        let newFrame = NSRect(x: tl.x, y: tl.y - s.height, width: s.width, height: s.height)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: true)
        }
        backgroundColor = .clear
        blur.state = .active
        blur.alphaValue = Self.blurStrength
    }

    override var canBecomeKey: Bool { true }
}

/// Owns the menu-bar status item (its label image + wallpaper-aware color) and toggles the
/// glass panel. Replaces `MenuBarExtra(.window)` (ADR-0018).
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private let model = AppModel.shared
    private var statusItem: NSStatusItem?
    private var panel: GlassPanel?
    private var clickMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var settingsWindow: NSWindow?

    /// Settings opens a controller-owned NSWindow (not the SwiftUI `Settings` scene, which
    /// reopened unreliably). Kept alive (`isReleasedWhenClosed = false`) so it re-shows every time;
    /// closing it drops the app back to `.accessory` so the Dock icon disappears.
    func openSettingsWindow() {
        dismissPanel()
        if settingsWindow == nil {
            let hc = NSHostingController(rootView: AnyView(SettingsView(model: model).frame(width: 360).padding(20)))
            let w = NSWindow(contentViewController: hc)
            w.title = "TokenMukbang 환경설정"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            // Drop back to .accessory (Dock icon hidden) when this window closes.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                   object: w, queue: .main) { _ in
                MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
            }
            settingsWindow = w
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.action = #selector(toggle)
        item.button?.target = self
        statusItem = item
        MenuBarAppearance.shared.attach(statusItem: item)   // wallpaper-aware label color (KVO)

        // Re-render the label image ONLY when the usage data or the menu-bar appearance changes —
        // NOT on every `objectWillChange` (that fired the expensive ImageRenderer on every tab tap,
        // making the popover laggy/unresponsive — user 2026-06-12). Panel resize/anchor is handled
        // entirely by the panel's own preferredContentSize observer, so no $layout subscription here.
        model.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.renderLabel() }
            .store(in: &cancellables)
        MenuBarAppearance.shared.$isDark
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.renderLabel() }
            .store(in: &cancellables)
        // No per-tab resize: the panel is a FIXED height (the taller tab) so switching 현황↔기록
        // is instant with zero resize jank (Option B, user choice 2026-06-12).
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
        if let panel, panel.isVisible { dismiss() } else { present() }
    }

    private func present() {
        // Recreate the panel fresh each show. Reusing a cached glass panel left it in a stale
        // (suddenly-opaque) state on the *second* present over a full-screen Space whose menu bar
        // auto-hides (user 2026-06-12). A fresh NSGlassEffectView re-samples cleanly every time.
        panel?.orderOut(nil)
        // Option B: fix the panel to the taller of the two tabs so tab switches never resize.
        let h = measureMaxTabHeight()
        let p = GlassPanel(rootView: MenuContentView(model: model, fixedHeight: h))
        panel = p
        anchorPanel()          // sets anchorTopLeft so resizeToFit keeps the top fixed
        p.resizeToFit()
        anchorPanel()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in self?.dismiss()
        }
    }

    /// Measure the taller of the two tabs (Option B fixed height). Each is rendered off-screen
    /// with a forced layout so its natural height can be measured without touching the live model.
    private func measureMaxTabHeight() -> CGFloat {
        var maxH: CGFloat = 200
        for layout in DashboardLayout.allCases {
            let hc = NSHostingController(rootView: AnyView(MenuContentView(model: model, forcedLayout: layout)))
            let h = hc.sizeThatFits(in: NSSize(width: GlassPanel.panelWidth, height: 10_000)).height
            maxH = max(maxH, h)
        }
        return maxH
    }

    private func anchorPanel() {
        guard let panel, let button = statusItem?.button, let bwin = button.window else { return }
        let rect = bwin.convertToScreen(button.convert(button.bounds, to: nil))
        var x = rect.midX - panel.frame.width / 2
        if let vf = bwin.screen?.visibleFrame {
            x = min(max(x, vf.minX + 8), vf.maxX - panel.frame.width - 8)
        }
        // Anchor by the TOP-left (just below the status item) so height changes grow downward.
        let topLeft = NSPoint(x: x, y: rect.minY - 6)
        panel.anchorTopLeft = topLeft
        panel.setFrameTopLeftPoint(topLeft)
    }

    /// Public so the Settings action can close the popover before opening the window.
    func dismissPanel() { dismiss() }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil                        // drop the glass so the next show builds fresh
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
    }
}

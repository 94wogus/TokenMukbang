import SwiftUI
import AppKit
import TokenMukbangKit

/// Two visual styles for the floating overlay (F3).
enum OverlayStyle: String, CaseIterable, Identifiable {
    case frost
    case neon
    var id: String { rawValue }
    var label: String { self == .frost ? "Frost" : "Neon" }
}

/// Owns the floating `NSPanel` Agent Watchers overlay, scans active Claude Code
/// sessions every 2 seconds (F5), and focuses a session's terminal on click.
@MainActor
final class OverlayController: ObservableObject {
    @Published var sessions: [ActiveSession] = []
    @Published var style: OverlayStyle = .frost
    @Published private(set) var isVisible = false

    private let focus = TerminalFocus()
    private var panel: NSPanel?
    private var scanTask: Task<Void, Never>?

    func toggle() { isVisible ? hide() : show() }

    func show() {
        if panel == nil { panel = makePanel() }
        panel?.makeKeyAndOrderFront(nil)
        isVisible = true
        startScan()
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        scanTask?.cancel(); scanTask = nil
    }

    func focusSession(_ session: ActiveSession) { focus.focus(session) }

    private func startScan() {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                let found = await Task.detached(priority: .utility) { SessionDetector().activeSessions() }.value
                self?.sessions = found
                try? await Task.sleep(nanoseconds: 2_000_000_000)   // F5: 2-second updates
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 240),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.title = "Agent Watchers"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: OverlayContentView(controller: self))
        panel.center()
        return panel
    }
}

/// The overlay's SwiftUI content: a dock-like list of active sessions.
struct OverlayContentView: View {
    @ObservedObject var controller: OverlayController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Watching 🍿").font(.headline)
                Spacer()
                Picker("", selection: $controller.style) {
                    ForEach(OverlayStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            if controller.sessions.isEmpty {
                Text("No sessions eating right now.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(controller.sessions) { session in
                            OverlaySessionRow(session: session, style: controller.style) {
                                controller.focusSession(session)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(minWidth: 260, minHeight: 200)
        .background(overlayBackground)
    }

    @ViewBuilder private var overlayBackground: some View {
        switch controller.style {
        case .frost: Rectangle().fill(.ultraThinMaterial)
        case .neon: Color.black.opacity(0.85)
        }
    }
}

/// A session row with a dock-like hover scale (F2).
struct OverlaySessionRow: View {
    let session: ActiveSession
    let style: OverlayStyle
    let onTap: () -> Void
    @State private var hover = false

    private var accent: Color {
        guard let f = session.contextFraction else { return .secondary }
        switch f {
        case ..<0.5: return Color(hex: "#34C759")
        case ..<0.8: return Color(hex: "#FF9F0A")
        default: return Color(hex: "#FF453A")
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(style == .neon ? accent.opacity(0.9) : accent)
                .frame(width: 9, height: 9)
                .shadow(color: style == .neon ? accent : .clear, radius: style == .neon ? 4 : 0)
            VStack(alignment: .leading, spacing: 1) {
                Text(session.projectName).font(.callout).lineLimit(1)
                Text(session.tty ?? "—").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if let f = session.contextFraction {
                Text("ctx \(Int(f * 100))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hover ? accent.opacity(style == .neon ? 0.18 : 0.12) : .clear)
        )
        .scaleEffect(hover ? 1.06 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hover)
        .onHover { hover = $0 }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .help("Click to open this session's terminal")
    }
}

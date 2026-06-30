import Foundation
import TokenMukbangKit

/// Watches each active session's transcript and fires `onFinished` the moment a
/// session crosses `working → idle` — i.e. Claude ended its turn (ADR-0022).
///
/// Why reactive (a `FileWatcher` per session) and not the 5-min usage poll: a task
/// can start and finish well inside one poll interval, so polling would miss it or
/// report it minutes late. Transcript writes, by contrast, land the instant Claude
/// appends its final `end_turn` message, so the notification is timely.
///
/// App-side (not Kit): it touches the filesystem reactively and drives notifications.
/// The pure "is this session idle?" decision lives in `SessionActivityReader` (Kit).
@MainActor
final class SessionActivityWatcher {
    private let detector: SessionDetector
    private let onFinished: (UsageSnapshot.Session) -> Void

    private var enabled: Bool
    private var watchers: [Int32: any FileWatching] = [:]      // pid → file watcher
    private var transcriptPath: [Int32: String] = [:]          // pid → watched transcript
    private var lastActivity: [Int32: SessionActivity] = [:]   // pid → last observed state
    private var meta: [Int32: UsageSnapshot.Session] = [:]      // pid → session identity (for focus)

    init(detector: SessionDetector = SessionDetector(),
         enabled: Bool,
         onFinished: @escaping (UsageSnapshot.Session) -> Void) {
        self.detector = detector
        self.enabled = enabled
        self.onFinished = onFinished
    }

    /// Toggle the feature live (Settings → Alerts). Disabling tears down all watchers.
    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if !on { stopAll() }
    }

    /// Reconcile watched sessions against the latest snapshot: start watchers for new
    /// sessions, drop them for sessions that have exited. Called after every refresh.
    func reconcile(sessions: [UsageSnapshot.Session]) {
        guard enabled else { stopAll(); return }
        let current = Set(sessions.map(\.pid))
        for pid in Array(watchers.keys) where !current.contains(pid) { remove(pid) }
        for s in sessions {
            meta[s.pid] = s
            if watchers[s.pid] == nil { addWatcher(for: s) }
        }
    }

    // MARK: - Internals

    private func addWatcher(for s: UsageSnapshot.Session) {
        guard let path = detector.newestTranscript(forCwd: s.cwd) else { return }
        transcriptPath[s.pid] = path
        // Seed the baseline WITHOUT notifying — a session already idle when first seen
        // (e.g. it was resting at app launch) must not fire a spurious "finished".
        lastActivity[s.pid] = SessionActivityReader.activity(transcriptPath: path)
        let pid = s.pid
        let watcher = FileWatcher(path: path) { [weak self] in
            Task { @MainActor in self?.handleChange(pid: pid) }
        }
        watcher.start()
        watchers[pid] = watcher
    }

    private func handleChange(pid: Int32) {
        guard enabled, let path = transcriptPath[pid],
              let activity = SessionActivityReader.activity(transcriptPath: path) else { return }
        let previous = lastActivity[pid]
        lastActivity[pid] = activity
        // Edge-triggered: only the working → idle transition is a "just finished".
        if previous == .working, activity == .idle, let session = meta[pid] {
            onFinished(session)
        }
    }

    private func remove(_ pid: Int32) {
        watchers[pid]?.stop()
        watchers[pid] = nil
        transcriptPath[pid] = nil
        lastActivity[pid] = nil
        meta[pid] = nil
    }

    private func stopAll() {
        for w in watchers.values { w.stop() }
        watchers.removeAll(); transcriptPath.removeAll()
        lastActivity.removeAll(); meta.removeAll()
    }
}

import Foundation
import Network
import TokenMukbangKit

/// Loopback-only OTLP/HTTP receiver (ADR-0023): binds `127.0.0.1`, accepts Claude Code's
/// telemetry POSTs, decodes them (Kit, pure), and persists app-only via `TelemetryStore`.
///
/// This is the app's **first inbound network boundary** — everything else is outbound
/// (usage API, retrospective CLI). The security invariant is the loopback bind: the
/// listener's `requiredLocalEndpoint` is the IPv4 loopback address, so it is never
/// reachable off-host. Content is dropped in the Kit decoder, not here.
final class OTLPReceiver: @unchecked Sendable {
    private let port: UInt16
    private let store: TelemetryStore
    private let now: () -> Date
    private let queue = DispatchQueue(label: "com.tokenmukbang.otlp")
    private var listener: NWListener?

    /// Optional hook fired after each ingested batch — used by the headless verify branch.
    var onIngest: ((_ kind: String, _ metrics: Int, _ events: Int) -> Void)?

    init(port: UInt16, store: TelemetryStore = TelemetryStore(), now: @escaping () -> Date = { Date() }) {
        self.port = port
        self.store = store
        self.now = now
    }

    func start() {
        stop()
        let params = NWParameters.tcp
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
        // Loopback-only bind — the load-bearing security invariant (ADR-0023).
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        guard let listener = try? NWListener(using: params) else { return }
        self.listener = listener
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.stop() }
            if case .cancelled = state { self?.listener = nil }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    /// Accumulate bytes until a full HTTP request frames, ingest it, reply 200, and close.
    /// One request per connection — our 200 sets `Connection: close`, so exporters just
    /// open a fresh connection per batch (fine at this volume).
    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data, !data.isEmpty { buf.append(data) }

            if let (request, _) = OTLPHTTP.parseRequest(buf) {
                self.ingest(request)
                conn.send(content: OTLPHTTP.okResponse(),
                          completion: .contentProcessed { _ in conn.cancel() })
                return
            }
            if isComplete || error != nil { conn.cancel(); return }
            self.receive(conn, buffer: buf)   // headers/body not all here yet
        }
    }

    private func ingest(_ request: OTLPHTTP.Request) {
        switch OTLPDecoder.kind(forPath: request.path) {
        case .metrics:
            let metrics = OTLPDecoder.decodeMetrics(request.body)
            store.append(metrics: metrics, events: [], now: now())
            onIngest?("metrics", metrics.count, 0)
        case .logs:
            let events = OTLPDecoder.decodeLogs(request.body)
            store.append(metrics: [], events: events, now: now())
            onIngest?("logs", 0, events.count)
        case nil:
            break   // unknown path (e.g. /v1/traces) — accept + 200, store nothing
        }
    }
}

import Foundation

/// Minimal HTTP/1.1 request framing for the local OTLP receiver — just enough to pull
/// the method, path, and body out of the bytes an OTLP exporter POSTs. Pure → the App's
/// `NWListener` glue feeds it accumulated bytes and stays thin and untested-able (ADR-0023).
public enum OTLPHTTP {
    public struct Request: Equatable, Sendable {
        public let method: String
        public let path: String
        public let body: Data
        public init(method: String, path: String, body: Data) {
            self.method = method; self.path = path; self.body = body
        }
    }

    /// A 200 response an OTLP/HTTP exporter accepts: empty JSON `ExportResponse` body.
    public static func okResponse() -> Data {
        let body = "{}"
        let headers = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n"
        return Data((headers + body).utf8)
    }

    /// Parse one complete HTTP request from `raw`. Returns the request plus how many bytes
    /// it consumed (so a connection can frame multiple pipelined requests), or `nil` when
    /// more bytes are still needed (headers incomplete, or body shorter than Content-Length).
    public static func parseRequest(_ raw: Data) -> (request: Request, consumed: Int)? {
        let bytes = Data(raw)   // normalize to 0-based indices
        guard let sep = bytes.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let bodyStart = sep.upperBound
        guard let headerStr = String(data: bytes.subdata(in: 0..<sep.lowerBound), encoding: .utf8) else { return nil }
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var contentLength = 0
        for line in lines.dropFirst() where line.lowercased().hasPrefix("content-length:") {
            let v = line.drop(while: { $0 != ":" }).dropFirst().trimmingCharacters(in: .whitespaces)
            contentLength = Int(v) ?? 0
        }

        let total = bodyStart + contentLength
        guard bytes.count >= total else { return nil }   // body not fully arrived yet
        let body = bytes.subdata(in: bodyStart..<total)
        return (Request(method: method, path: path, body: body), total)
    }
}

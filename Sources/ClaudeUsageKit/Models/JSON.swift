import Foundation

/// Shared JSON decoder configured for the Claude OAuth API's ISO-8601 dates,
/// which carry fractional seconds and a timezone offset
/// (e.g. `2026-06-11T13:59:59.715802+00:00`).
public enum ClaudeJSON {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let raw = try d.singleValueContainer().decode(String.self)
            if let date = Self.parseISO8601(raw) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: d.codingPath, debugDescription: "Unparseable date: \(raw)")
            )
        }
        return decoder
    }

    /// Parse an ISO-8601 timestamp with or without fractional seconds.
    public static func parseISO8601(_ raw: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

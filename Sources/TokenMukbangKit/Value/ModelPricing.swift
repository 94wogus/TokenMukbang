import Foundation

/// API **list-price** equivalence for a `TokenEvent` — the basis of the "Value / Savings"
/// estimate (ADR-0021). The user pays a flat subscription; this answers "what would the same
/// token traffic have cost on pay-per-token API rates?" so we can show the value they're getting.
///
/// Pricing is matched off the **raw model id** (not `ModelCast`) so Opus versions price
/// correctly — current Opus (4.5/4.6/4.7/4.8) is $5/$25 per 1M, but older Opus (4.0/4.1/3) was
/// $15/$75. Cache tokens are priced relative to input: a cache **write** (creation) is 1.25×
/// input (5-min TTL — the common Claude Code case), a cache **read** is 0.1× input.
public enum ModelPricing {
    /// Cache-creation (write) multiplier over input price. 5-min ephemeral TTL = 1.25×.
    /// (A 1-hour TTL would be 2× — we assume the common 5-min case; documented in the UI.)
    public static let cacheWriteMultiplier = 1.25
    /// Cache-read multiplier over input price (reheated context is ~0.1× input).
    public static let cacheReadMultiplier = 0.10

    /// `($ per 1M input, $ per 1M output)` for a model id, or `nil` if we don't price it
    /// (e.g. `mock-claude`, `<synthetic>`) so the caller can exclude it from the estimate.
    public static func forModel(_ raw: String) -> (input: Double, output: Double)? {
        let s = raw.lowercased()
        if s.contains("opus") {
            // 4.5/4.6/4.7/4.8 = $5/$25; older Opus (4.0/4.1/3) was $15/$75.
            let old = ["opus-4-0", "opus-4-1", "opus-3", "claude-3-opus"].contains { s.contains($0) }
            return old ? (15, 75) : (5, 25)
        }
        if s.contains("sonnet") { return (3, 15) }
        if s.contains("haiku") { return (1, 5) }
        if s.contains("fable") || s.contains("mythos") { return (10, 50) }
        return nil
    }

    /// The API-equivalent dollar cost of one turn, split by component, or `nil` if unpriced.
    public static func cost(_ e: TokenEvent) -> (total: Double, input: Double, output: Double,
                                                 cacheRead: Double, cacheWrite: Double)? {
        guard let p = forModel(e.model) else { return nil }
        let input = Double(e.inputTokens) * p.input / 1_000_000
        let output = Double(e.outputTokens) * p.output / 1_000_000
        let cacheWrite = Double(e.cacheCreationTokens) * p.input * cacheWriteMultiplier / 1_000_000
        let cacheRead = Double(e.cacheReadTokens) * p.input * cacheReadMultiplier / 1_000_000
        return (input + output + cacheWrite + cacheRead, input, output, cacheRead, cacheWrite)
    }
}

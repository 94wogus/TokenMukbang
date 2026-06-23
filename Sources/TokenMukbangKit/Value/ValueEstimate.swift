import Foundation

/// "What would this token traffic cost at API rates?" — the data behind the Now-tab
/// **Value / Savings** card (ADR-0021). Pure aggregation over `TokenEvent`s priced via
/// `ModelPricing`, so it lives in Kit and is unit-tested (ADR-0001).
///
/// `apiEquivalent` is the full pay-per-token cost (incl. cache reads). `costExclCacheRead`
/// is the "fresh work" cost (output + uncached input + cache write) — shown as a conservative
/// second number, because cache **reads** are near-free per token yet dominate the total by
/// sheer volume (the honest split we surface so the headline isn't misread).
public struct ValueEstimate: Sendable, Equatable {
    /// One model family's contribution (heaviest cost first).
    public struct CastLine: Sendable, Equatable, Identifiable {
        public let name: String          // "Opus" / "Sonnet" / "Haiku" / "Fable" / "Other"
        public let input: Int
        public let output: Int
        public let cacheRead: Int
        public let cacheWrite: Int
        public let cost: Double           // API-equivalent $ for this family (0 when unpriced)
        public let priced: Bool
        public var id: String { name }

        public init(name: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int,
                    cost: Double, priced: Bool) {
            self.name = name; self.input = input; self.output = output
            self.cacheRead = cacheRead; self.cacheWrite = cacheWrite; self.cost = cost; self.priced = priced
        }
    }

    public let lines: [CastLine]
    public let apiEquivalent: Double        // total $ incl. cache reads — what API would charge
    public let costExclCacheRead: Double    // $ for output + fresh-input + cache-write only
    public let inputCost: Double
    public let outputCost: Double
    public let cacheReadCost: Double
    public let cacheWriteCost: Double
    public let unpricedTokens: Int          // tokens we couldn't price (mock/synthetic models)
    public let periodStart: Date
    public let periodEnd: Date

    public init(lines: [CastLine], apiEquivalent: Double, costExclCacheRead: Double,
                inputCost: Double, outputCost: Double, cacheReadCost: Double, cacheWriteCost: Double,
                unpricedTokens: Int, periodStart: Date, periodEnd: Date) {
        self.lines = lines; self.apiEquivalent = apiEquivalent; self.costExclCacheRead = costExclCacheRead
        self.inputCost = inputCost; self.outputCost = outputCost; self.cacheReadCost = cacheReadCost
        self.cacheWriteCost = cacheWriteCost; self.unpricedTokens = unpricedTokens
        self.periodStart = periodStart; self.periodEnd = periodEnd
    }

    /// Dollars saved vs a flat subscription for this period (can be negative if under-using).
    public func savings(subscription: Double) -> Double { apiEquivalent - subscription }
    /// How many times the subscription's worth you'd have paid at API rates (0 if no price set).
    public func multiple(subscription: Double) -> Double {
        subscription > 0 ? apiEquivalent / subscription : 0
    }

    /// Build the estimate for `[periodStart, periodEnd)` from all token events. Unpriced
    /// models (mock/synthetic) are kept out of the cost but their tokens are counted in
    /// `unpricedTokens` so the UI can note them.
    public static func build(events: [TokenEvent], periodStart: Date, periodEnd: Date) -> ValueEstimate {
        let inPeriod = events.filter { $0.timestamp >= periodStart && $0.timestamp < periodEnd }

        struct Acc { var input = 0, output = 0, cacheRead = 0, cacheWrite = 0; var cost = 0.0; var priced = false }
        var byName: [String: Acc] = [:]
        var inputCost = 0.0, outputCost = 0.0, crCost = 0.0, cwCost = 0.0
        var unpriced = 0

        for e in inPeriod {
            let c = ModelPricing.cost(e)
            // Group priced families under their cast name; everything unpriced under "Other".
            let name = c != nil ? (ModelCast.forModel(e.model)?.modelName ?? "Other") : "Other"
            var a = byName[name] ?? Acc()
            a.input += e.inputTokens; a.output += e.outputTokens
            a.cacheRead += e.cacheReadTokens; a.cacheWrite += e.cacheCreationTokens
            if let c {
                a.cost += c.total; a.priced = true
                inputCost += c.input; outputCost += c.output; crCost += c.cacheRead; cwCost += c.cacheWrite
            } else {
                unpriced += e.totalTokens
            }
            byName[name] = a
        }

        let lines = byName
            .map { CastLine(name: $0.key, input: $0.value.input, output: $0.value.output,
                            cacheRead: $0.value.cacheRead, cacheWrite: $0.value.cacheWrite,
                            cost: $0.value.cost, priced: $0.value.priced) }
            .sorted { $0.cost > $1.cost }

        return ValueEstimate(
            lines: lines,
            apiEquivalent: inputCost + outputCost + crCost + cwCost,
            costExclCacheRead: inputCost + outputCost + cwCost,
            inputCost: inputCost, outputCost: outputCost, cacheReadCost: crCost, cacheWriteCost: cwCost,
            unpricedTokens: unpriced, periodStart: periodStart, periodEnd: periodEnd)
    }

    // MARK: - Formatting (shared so the app doesn't re-implement it; Kit stays UI-free)

    /// `$16,619` — grouped, no cents. Small values keep their dollars too (`$220`).
    public static func dollars(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return "$" + (f.string(from: NSNumber(value: v.rounded())) ?? String(Int(v.rounded())))
    }

    /// `75×` / `3.4×` — one decimal under 10, whole above.
    public static func multipleLabel(_ x: Double) -> String {
        guard x > 0 else { return "—" }
        return x >= 10 ? "\(Int(x.rounded()))×" : String(format: "%.1f×", x)
    }
}

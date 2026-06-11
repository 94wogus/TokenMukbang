import Foundation

/// A single rate-limit window returned by `GET /api/oauth/usage`.
/// Each window is either present (`{utilization, resets_at}`) or `null`.
public struct RateLimitWindow: Codable, Sendable, Equatable {
    /// Percentage 0...100 of this window consumed.
    public let utilization: Double
    /// When this window's allowance resets.
    public let resetsAt: Date

    public init(utilization: Double, resetsAt: Date) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

/// Logical identity of a usage window, kept stable for the UI regardless of how
/// many experimental buckets the API adds.
public enum UsageWindowKind: String, Sendable, CaseIterable {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"
    case sevenDayOpus = "seven_day_opus"
    case sevenDaySonnet = "seven_day_sonnet"

    /// Human label for menu-bar / widget rows.
    public var label: String {
        switch self {
        case .fiveHour: return "5h"
        case .sevenDay: return "7d"
        case .sevenDayOpus: return "Opus 7d"
        case .sevenDaySonnet: return "Sonnet 7d"
        }
    }
}

/// Decoded `GET /api/oauth/usage` payload. The API exposes many nullable buckets;
/// we decode the four that drive v1 and keep the rest out of the model surface.
public struct Usage: Codable, Sendable, Equatable {
    public let fiveHour: RateLimitWindow?
    public let sevenDay: RateLimitWindow?
    public let sevenDayOpus: RateLimitWindow?
    public let sevenDaySonnet: RateLimitWindow?

    public init(
        fiveHour: RateLimitWindow?,
        sevenDay: RateLimitWindow?,
        sevenDayOpus: RateLimitWindow?,
        sevenDaySonnet: RateLimitWindow?
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
    }

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    /// Ordered, non-nil windows for display, primary (5h) first.
    public var displayWindows: [(kind: UsageWindowKind, window: RateLimitWindow)] {
        var out: [(UsageWindowKind, RateLimitWindow)] = []
        if let w = fiveHour { out.append((.fiveHour, w)) }
        if let w = sevenDay { out.append((.sevenDay, w)) }
        if let w = sevenDayOpus { out.append((.sevenDayOpus, w)) }
        if let w = sevenDaySonnet { out.append((.sevenDaySonnet, w)) }
        return out
    }
}

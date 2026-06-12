import Foundation

/// Decoded `GET /api/oauth/profile` payload (only the fields v1 surfaces).
public struct Profile: Codable, Sendable, Equatable {
    public struct Account: Codable, Sendable, Equatable {
        public let displayName: String?
        public let email: String?
        public let hasClaudeMax: Bool
        public let hasClaudePro: Bool

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case email
            case hasClaudeMax = "has_claude_max"
            case hasClaudePro = "has_claude_pro"
        }
    }

    public struct Organization: Codable, Sendable, Equatable {
        public let organizationType: String?
        public let rateLimitTier: String?
        public let subscriptionStatus: String?

        enum CodingKeys: String, CodingKey {
            case organizationType = "organization_type"
            case rateLimitTier = "rate_limit_tier"
            case subscriptionStatus = "subscription_status"
        }
    }

    public let account: Account
    public let organization: Organization

    public init(account: Account, organization: Organization) {
        self.account = account
        self.organization = organization
    }

    /// "Max" / "Pro" / "Free" label for the dashboard header.
    public var planLabel: String {
        if account.hasClaudeMax { return "Max" }
        if account.hasClaudePro { return "Pro" }
        return "Free"
    }
}

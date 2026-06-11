import XCTest
@testable import ClaudeUsageKit

final class DecodingTests: XCTestCase {
    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: ext))
        return try Data(contentsOf: url)
    }

    func testUsageDecoding() throws {
        let usage = try ClaudeJSON.makeDecoder().decode(Usage.self, from: try fixture("usage", "json"))
        XCTAssertEqual(usage.fiveHour?.utilization, 8.0)
        XCTAssertEqual(usage.sevenDay?.utilization, 31.0)
        XCTAssertEqual(usage.sevenDaySonnet?.utilization, 4.0)
        XCTAssertNil(usage.sevenDayOpus)

        // Fractional-seconds + offset date parsed correctly.
        let reset = try XCTUnwrap(usage.fiveHour?.resetsAt)
        let expected = ClaudeJSON.parseISO8601("2026-06-11T13:59:59.715802+00:00")
        XCTAssertEqual(reset, expected)

        // Display ordering: 5h first, opus dropped (nil).
        let kinds = usage.displayWindows.map(\.kind)
        XCTAssertEqual(kinds, [.fiveHour, .sevenDay, .sevenDaySonnet])
    }

    func testProfileDecoding() throws {
        let profile = try ClaudeJSON.makeDecoder().decode(Profile.self, from: try fixture("profile", "json"))
        XCTAssertEqual(profile.account.displayName, "Tester")
        XCTAssertTrue(profile.account.hasClaudeMax)
        XCTAssertEqual(profile.planLabel, "Max")
        XCTAssertEqual(profile.organization.rateLimitTier, "default_claude_max_20x")
    }

    func testCredentialsDecoding() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"sk-xxx","refreshToken":"rt","expiresAt":1781197284714,"scopes":["user:inference"],"subscriptionType":"max"}}"#
        struct Env: Codable { let claudeAiOauth: OAuthCredentials }
        let creds = try JSONDecoder().decode(Env.self, from: Data(json.utf8)).claudeAiOauth
        XCTAssertEqual(creds.accessToken, "sk-xxx")
        XCTAssertEqual(creds.subscriptionType, "max")
        // Expiry is in the future relative to a 2024 date.
        XCTAssertFalse(creds.isExpired(asOf: Date(timeIntervalSince1970: 1_700_000_000)))
        XCTAssertTrue(creds.isExpired(asOf: Date(timeIntervalSince1970: 2_000_000_000)))
    }
}

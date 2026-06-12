import XCTest
@testable import TokenMukbangKit

final class UpdateCheckerTests: XCTestCase {
    func testParsesTagName() {
        XCTAssertEqual(UpdateChecker.latestVersion(fromReleaseJSON: #"{"tag_name":"v1.2.3","name":"x"}"#), "1.2.3")
        XCTAssertEqual(UpdateChecker.latestVersion(fromReleaseJSON: #"{"tag_name":"2.0.0"}"#), "2.0.0")
        XCTAssertNil(UpdateChecker.latestVersion(fromReleaseJSON: "not json"))
        XCTAssertNil(UpdateChecker.latestVersion(fromReleaseJSON: #"{"name":"no tag"}"#))
    }

    func testIsNewerSemver() {
        XCTAssertTrue(UpdateChecker.isNewer(latest: "1.2.0", current: "1.1.9"))
        XCTAssertTrue(UpdateChecker.isNewer(latest: "2.0.0", current: "1.9.9"))
        XCTAssertTrue(UpdateChecker.isNewer(latest: "1.0.1", current: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer(latest: "1.0.0", current: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer(latest: "1.0.0", current: "1.0.1"))
        XCTAssertTrue(UpdateChecker.isNewer(latest: "1.1", current: "1.0.9"))   // ragged components
    }

    func testReleaseURL() {
        XCTAssertEqual(UpdateChecker.latestReleaseURL(owner: "94wogus", repo: "TokenMukbang").absoluteString,
                       "https://api.github.com/repos/94wogus/TokenMukbang/releases/latest")
    }
}

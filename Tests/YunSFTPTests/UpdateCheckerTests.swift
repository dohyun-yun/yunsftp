import XCTest
@testable import yunsftp

@MainActor
final class UpdateCheckerTests: XCTestCase {

    func testVersionComparison() {
        XCTAssertTrue(UpdateChecker.isNewer("v1.1.0", than: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.10", than: "1.0.9"))
        XCTAssertTrue(UpdateChecker.isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(UpdateChecker.isNewer("v1.0.0", than: "1.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.9", than: "1.0.0"))
        XCTAssertTrue(UpdateChecker.isNewer("1.2.0-beta", than: "1.1.0"), "pre-release suffix ignored for ordering")
    }

    func testParsesLatestReleaseAndIgnoresDraftsAndPrereleases() {
        let ok = #"{"tag_name":"v1.2.0","html_url":"https://github.com/dohyun-yun/yunsftp/releases/tag/v1.2.0","body":"notes","draft":false,"prerelease":false}"#
        let info = UpdateChecker.parseLatestRelease(Data(ok.utf8))
        XCTAssertEqual(info?.version, "v1.2.0")
        XCTAssertEqual(info?.notes, "notes")
        XCTAssertEqual(info?.url.absoluteString, "https://github.com/dohyun-yun/yunsftp/releases/tag/v1.2.0")

        let pre = #"{"tag_name":"v9.0.0","html_url":"https://x","prerelease":true}"#
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data(pre.utf8)))
        XCTAssertNil(UpdateChecker.parseLatestRelease(Data("not json".utf8)))
    }

    func testDailyThrottleAndSkippedVersionPersist() {
        let suite = "yunsftp.upd.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        defer { d.removePersistentDomain(forName: suite) }
        let checker = UpdateChecker(defaults: d)
        let now = Date()
        XCTAssertTrue(checker.isDue(now: now))
        checker.markChecked(now: now)
        XCTAssertFalse(checker.isDue(now: now.addingTimeInterval(3600)))
        XCTAssertTrue(checker.isDue(now: now.addingTimeInterval(UpdateChecker.interval + 1)))
        checker.skip(version: "v1.2.0")
        XCTAssertEqual(UpdateChecker(defaults: d).skippedVersion, "v1.2.0")
    }
}

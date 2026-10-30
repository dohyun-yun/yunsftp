import XCTest
@testable import yunsftp

final class UIPolishTests: XCTestCase {
    private var viewsRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/YunSFTP/Views")
    }

    func testToolbarItemIDsAreUniqueAndPrimarySetIsSmall() {
        let all = ToolbarView.primaryItemIDs + ToolbarView.secondaryItemIDs
        XCTAssertEqual(Set(all).count, all.count)
        XCTAssertLessThanOrEqual(ToolbarView.primaryItemIDs.count, 7)
        XCTAssertTrue(ToolbarView.primaryItemIDs.contains("more"))
    }

    func testWelcomeBannerOnlyOnActiveLocalPaneWithoutServers() {
        XCTAssertTrue(WelcomeBanner.shouldShow(connectionsEmpty: true, dismissed: false, isRemote: false, isActive: true))
        XCTAssertFalse(WelcomeBanner.shouldShow(connectionsEmpty: false, dismissed: false, isRemote: false, isActive: true))
        XCTAssertFalse(WelcomeBanner.shouldShow(connectionsEmpty: true, dismissed: true, isRemote: false, isActive: true))
        XCTAssertFalse(WelcomeBanner.shouldShow(connectionsEmpty: true, dismissed: false, isRemote: true, isActive: true))
        XCTAssertFalse(WelcomeBanner.shouldShow(connectionsEmpty: true, dismissed: false, isRemote: false, isActive: false))
    }

    /// Body-sized text uses system text styles (Dynamic Type, accessibility sizes); only large
    /// decorative glyphs and the settings-driven list font may use literal point sizes.
    func testNoLiteralBodyFontSizesInViews() throws {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: viewsRoot, includingPropertiesForKeys: nil))
        let literal = try NSRegularExpression(pattern: #"\.font\(\.system\(size: (9|1[0-5])(\.0)?[,)]"#)
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let hits = literal.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            XCTAssertEqual(hits, 0, "\(url.lastPathComponent) still has \(hits) literal body font sizes")
        }
    }
}

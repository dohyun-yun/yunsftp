import XCTest
@testable import yunsftp

final class FilterAndPathTests: XCTestCase {
    @MainActor
    func testFilterToggleClearsQueryWhenHiding() {
        let pane = PaneModel(initialURL: FileManager.default.temporaryDirectory, autoLoad: false)
        XCTAssertFalse(pane.shouldShowFilter)
        pane.toggleFilter()
        XCTAssertTrue(pane.shouldShowFilter)
        pane.searchQuery = "abc"
        pane.toggleFilter()
        XCTAssertFalse(pane.shouldShowFilter)
        XCTAssertEqual(pane.searchQuery, "")
        // A query typed while hidden (e.g. type-to-filter) still shows the field.
        pane.searchQuery = "x"
        XCTAssertTrue(pane.shouldShowFilter)
    }
}

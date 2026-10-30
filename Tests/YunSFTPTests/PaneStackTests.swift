import XCTest
@testable import yunsftp

@MainActor
final class PaneStackTests: XCTestCase {
    private func makeStack() -> PaneStack {
        PaneStack(initial: PaneModel(initialURL: FileManager.default.temporaryDirectory, autoLoad: false))
    }

    func testNewTabOpensNextToCurrentAtTheSameLocationAndBecomesSelected() {
        let stack = makeStack()
        let first = stack.current
        let second = stack.newTab()
        XCTAssertEqual(stack.tabs.count, 2)
        XCTAssertTrue(stack.current === second)
        XCTAssertEqual(second.currentURL.standardizedFileURL, first.currentURL.standardizedFileURL)
        stack.select(0)
        let middle = stack.newTab()
        XCTAssertTrue(stack.tabs[1] === middle, "inserted right after the tab it was opened from")
        XCTAssertEqual(stack.selectedIndex, 1)
    }

    func testLastTabCannotBeClosedAndSelectionStaysValid() {
        let stack = makeStack()
        stack.closeCurrent()
        XCTAssertEqual(stack.tabs.count, 1)
        stack.newTab(); stack.newTab()          // [a, b, c], c selected
        stack.closeCurrent()                    // [a, b], b selected
        XCTAssertEqual(stack.selectedIndex, 1)
        stack.select(1)
        stack.close(at: 0)                      // [b], selection shifts with it
        XCTAssertEqual(stack.selectedIndex, 0)
        XCTAssertEqual(stack.tabs.count, 1)
    }

    func testNextAndPreviousWrapAround() {
        let stack = makeStack()
        stack.newTab(); stack.newTab()
        stack.select(2)
        stack.selectNext()
        XCTAssertEqual(stack.selectedIndex, 0)
        stack.selectPrevious()
        XCTAssertEqual(stack.selectedIndex, 2)
    }

    func testTitlesAndConnectedIDs() {
        let stack = makeStack()
        XCTAssertEqual(PaneStack.title(for: stack.current), FileManager.default.temporaryDirectory.lastPathComponent)
        let conn = RemoteConnection(name: "NAS", host: "nas.example.com")
        let remote = PaneModel(initialURL: FileManager.default.temporaryDirectory, autoLoad: false)
        remote.isRemote = true
        remote.remoteConnection = conn
        remote.remotePath = "/volume1/photos"
        XCTAssertEqual(PaneStack.title(for: remote), "NAS: photos")
        remote.remotePath = "/"
        XCTAssertEqual(PaneStack.title(for: remote), "NAS")
        XCTAssertTrue(stack.connectedConnectionIDs.isEmpty)
    }

    func testStackForwardsChangesOfItsCurrentTab() {
        let stack = makeStack()
        let exp = expectation(description: "objectWillChange forwarded")
        let c = stack.objectWillChange.sink { _ in exp.fulfill() }
        stack.current.searchQuery = "x"
        wait(for: [exp], timeout: 1)
        c.cancel()
    }
}

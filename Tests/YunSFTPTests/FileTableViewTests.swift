import XCTest
@testable import yunsftp

@MainActor
final class FileTableViewTests: XCTestCase {
    func testSortOrderBridgesBothWays() {
        for field in SortField.allCases {
            for ascending in [true, false] {
                let comparators = FileTableView.comparators(for: field, ascending: ascending)
                XCTAssertEqual(comparators.count, 1)
                XCTAssertEqual(FileTableView.sortField(for: comparators[0]), field)
                XCTAssertEqual(comparators[0].order == .forward, ascending)
            }
        }
        XCTAssertNil(FileTableView.sortField(for: KeyPathComparator(\FileItem.posixPermissions)))
    }

    func testTableViewModePersistsAndOldValuesStillDecode() throws {
        XCTAssertEqual(try JSONDecoder().decode(ViewMode.self, from: Data("\"Table\"".utf8)), .table)
        XCTAssertEqual(try JSONDecoder().decode(ViewMode.self, from: Data("\"List\"".utf8)), .list)
        var s = AppSettings(); s.viewMode = .table
        let round = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(round.viewMode, .table)
    }
}

extension FileTableViewTests {
    func testSelectionBridgeKeepsListViewSemantics() {
        let pane = PaneModel(initialURL: FileManager.default.temporaryDirectory, autoLoad: false)
        let a = URL(fileURLWithPath: "/tmp/a"), b = URL(fileURLWithPath: "/tmp/b")
        FileTableView.applySelection([a], to: pane)
        XCTAssertEqual(pane.selectedItemURLs, [a])
        XCTAssertTrue(pane.pinnedSelectionURLs.isEmpty, "a single click is not pinned, so arrows move a plain selection")
        XCTAssertEqual(pane.focusedItemURL, a)
        FileTableView.applySelection([a, b], to: pane)
        XCTAssertEqual(pane.pinnedSelectionURLs, [a, b])
        XCTAssertEqual(pane.focusedItemURL, a, "focus stays when it is still selected")
        FileTableView.applySelection([b], to: pane)
        XCTAssertEqual(pane.focusedItemURL, b)
    }

    func testPrimaryTargetPrefersTheKeyboardCursorAndRefusesAmbiguity() {
        let a = URL(fileURLWithPath: "/a"), b = URL(fileURLWithPath: "/b")
        XCTAssertEqual(FileTableView.primaryTarget(in: [a, b], focused: b), b)
        XCTAssertNil(FileTableView.primaryTarget(in: [a, b], focused: nil))
        XCTAssertNil(FileTableView.primaryTarget(in: [a, b], focused: URL(fileURLWithPath: "/c")))
        XCTAssertEqual(FileTableView.primaryTarget(in: [a], focused: nil), a)
    }
}

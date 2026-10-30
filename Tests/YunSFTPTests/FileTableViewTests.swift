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

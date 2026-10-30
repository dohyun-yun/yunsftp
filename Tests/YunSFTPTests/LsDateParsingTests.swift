import XCTest
@testable import yunsftp

final class LsDateParsingTests: XCTestCase {
    private var cal: Calendar { Calendar.current }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testRecentDateWithoutYearUsesCurrentYear() throws {
        let now = date(2026, 3, 10)
        let parsed = try XCTUnwrap(SFTPService.parseLsDate("Mar 1 09:30", now: now))
        XCTAssertEqual(cal.component(.year, from: parsed), 2026)
    }

    func testFutureMonthWithoutYearRollsBackToPreviousYear() throws {
        // In January, "Dec 31 23:59" is last year's file, not one 11 months in the future.
        let now = date(2026, 1, 5)
        let parsed = try XCTUnwrap(SFTPService.parseLsDate("Dec 31 23:59", now: now))
        XCTAssertEqual(cal.component(.year, from: parsed), 2025)
    }

    func testExplicitYearIsKept() throws {
        let parsed = try XCTUnwrap(SFTPService.parseLsDate("Oct 13 2024", now: date(2026, 1, 5)))
        XCTAssertEqual(cal.component(.year, from: parsed), 2024)
    }
}

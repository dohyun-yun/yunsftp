import XCTest
@testable import yunsftp

final class MigrationServiceTests: XCTestCase {
    func testImportedProtocolUsesBookmarkTypeOrStandardPortOnly() {
        XCTAssertEqual(MigrationService.importedProtocol(type: 200, port: 2222), .sftp)
        XCTAssertEqual(MigrationService.importedProtocol(type: 0, port: 22), .sftp)
        XCTAssertEqual(MigrationService.importedProtocol(type: 0, port: 21), .ftp)
        // No environment-specific port numbers are special-cased
        XCTAssertEqual(MigrationService.importedProtocol(type: 0, port: 2222), .ftp)
    }

    func testImportedConnectionNameIsDerivedFromHostOnly() {
        XCTAssertEqual(MigrationService.importedConnectionName(host: "nas.example.com"), "Nas")
        XCTAssertEqual(MigrationService.importedConnectionName(host: "10.0.0.5"), "10")
        XCTAssertFalse(MigrationService.importedConnectionName(host: "box.local").contains("Synology"))
    }
}

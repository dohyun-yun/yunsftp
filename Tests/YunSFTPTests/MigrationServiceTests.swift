import XCTest
@testable import yunsftp

final class MigrationServiceTests: XCTestCase {
    func testImportedProtocolUsesBookmarkTypeOrStandardPortOnly() {
        XCTAssertEqual(MigrationService.importedProtocol(type: 200, port: 2222), .sftp)
        XCTAssertEqual(MigrationService.importedProtocol(type: 0, port: 22), .sftp)
        XCTAssertEqual(MigrationService.importedProtocol(type: 0, port: 21), .ftp)
        // No environment-specific port numbers are special-cased
        XCTAssertEqual(MigrationService.importedProtocol(type: 0, port: 10022), .ftp)
    }

    func testImportedConnectionNameIsDerivedFromHostOnly() {
        XCTAssertEqual(MigrationService.importedConnectionName(host: "nas.example.com"), "Nas")
        XCTAssertEqual(MigrationService.importedConnectionName(host: "10.0.0.5"), "10")
        XCTAssertFalse(MigrationService.importedConnectionName(host: "box.local").contains("Synology"))
    }
}

extension MigrationServiceTests {
    func testMigrationDoesNotPersistSettingsItself() throws {
        // migrateFromForkLift2() must only *return* settings; saving is the caller's decision.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/YunSFTP/Services/MigrationService.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(source.contains(".save()"))
    }
}

import XCTest
@testable import yunsftp

final class FileItemTests: XCTestCase {
    func testPOSIXPermissionFormatting() {
        XCTAssertEqual(FileItem.formatPOSIXPermissions(0o755), "rwxr-xr-x")
        XCTAssertEqual(FileItem.formatPOSIXPermissions(0o644), "rw-r--r--")
        XCTAssertEqual(FileItem.formatPOSIXPermissions(0o700), "rwx------")
        XCTAssertEqual(FileItem.formatPOSIXPermissions(0o777), "rwxrwxrwx")
        XCTAssertEqual(FileItem.formatPOSIXPermissions(0o000), "---------")
    }

    func testFormattedSize() {
        let dirURL = URL(fileURLWithPath: "/tmp")
        let dirItem = FileItem(virtualURL: dirURL, name: "tmp", isDirectory: true, size: 0, modificationDate: Date(), permissions: "rwxr-xr-x")
        XCTAssertEqual(dirItem.formattedSize, "--")

        let fileURL = URL(fileURLWithPath: "/tmp/sample.txt")
        let fileItem = FileItem(virtualURL: fileURL, name: "sample.txt", isDirectory: false, size: 1048576, modificationDate: Date(), permissions: "rw-r--r--")
        XCTAssertFalse(fileItem.formattedSize.isEmpty)
        XCTAssertNotEqual(fileItem.formattedSize, "--")
    }

    func testKoreanUnicodeNFCPathConstruction() {
        let koreanFolder = "88.부동산"
        let sftpURL = SFTPService.sftpURL(host: "192.168.0.10", port: 22, path: "/video/\(koreanFolder)")

        XCTAssertEqual(sftpURL.scheme, "sftp")
        XCTAssertEqual(sftpURL.host, "192.168.0.10")
        XCTAssertEqual(sftpURL.port, 22)
        XCTAssertTrue(sftpURL.path.precomposedStringWithCanonicalMapping.contains("88.부동산"))
    }
}

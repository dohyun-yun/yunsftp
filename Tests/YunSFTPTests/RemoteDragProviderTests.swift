import XCTest
import UniformTypeIdentifiers
@testable import yunsftp

final class RemoteDragProviderTests: XCTestCase {

    func testFileTypeFromExtensionOrFolder() {
        let dir = FileItem(virtualURL: URL(string: "sftp://h/a")!, name: "a", isDirectory: true, size: 0, modificationDate: Date(), permissions: "")
        XCTAssertEqual(RemoteDragProvider.fileType(for: dir), .folder)
        let png = FileItem(virtualURL: URL(string: "sftp://h/p.png")!, name: "p.png", isDirectory: false, size: 1, modificationDate: Date(), permissions: "")
        XCTAssertEqual(RemoteDragProvider.fileType(for: png), .png)
        let unknown = FileItem(virtualURL: URL(string: "sftp://h/x.zzqq")!, name: "x.zzqq", isDirectory: false, size: 1, modificationDate: Date(), permissions: "")
        XCTAssertTrue(RemoteDragProvider.fileType(for: unknown).conforms(to: .data))
    }

    func testProviderDeliversDownloadedFileToReceivers() async throws {
        guard FileManager.default.fileExists(atPath: "/usr/libexec/sftp-server") else { throw XCTSkip("no sftp-server") }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_drag_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let remote = base.appendingPathComponent("photo.txt")
        try "dragged".write(to: remote, atomically: true, encoding: .utf8)
        let conn = RemoteConnection(name: "Local", host: "local-sftp-server", port: 22, username: NSUserName(), remotePath: base.path, authType: .sshKey)
        let item = FileItem(virtualURL: SFTPService.sftpURL(host: conn.host, port: conn.port, path: remote.path), name: "photo.txt", isDirectory: false, size: 7, modificationDate: Date(), permissions: "")

        let provider = RemoteDragProvider.make(item: item, connection: conn, password: nil)
        XCTAssertEqual(provider.suggestedName, "photo.txt")
        XCTAssertTrue(provider.hasRepresentationConforming(toTypeIdentifier: UTType.plainText.identifier, fileOptions: []))

        // What Finder does on drop: ask for the file representation.
        let content: String = try await withCheckedThrowingContinuation { cont in
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.plainText.identifier) { url, error in
                if let url, let text = try? String(contentsOf: url, encoding: .utf8) { cont.resume(returning: text) }
                else { cont.resume(throwing: error ?? NSError(domain: "test", code: 1)) }
            }
        }
        XCTAssertEqual(content, "dragged")

        // Our own panes still see the sftp URL.
        XCTAssertTrue(provider.canLoadObject(ofClass: NSURL.self))
    }
}

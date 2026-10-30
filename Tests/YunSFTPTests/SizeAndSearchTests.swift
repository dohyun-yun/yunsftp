import XCTest
@testable import yunsftp

final class SizeAndSearchTests: XCTestCase {
    private func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_tree_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/b/c"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 100).write(to: root.appendingPathComponent("top.bin"))
        try Data(repeating: 1, count: 250).write(to: root.appendingPathComponent("a/Report-Final.pdf"))
        try Data(repeating: 1, count: 50).write(to: root.appendingPathComponent("a/b/c/deep-report.txt"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        return root
    }

    func testLocalDirectorySizeSumsRegularFilesOnly() throws {
        let root = try makeTree(); defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(FileSystemService.directorySize(root), 400)
    }

    func testRemoteDirectorySizeAndSearch() async throws {
        guard FileManager.default.fileExists(atPath: "/usr/libexec/sftp-server") else { throw XCTSkip("no sftp-server") }
        let root = try makeTree(); defer { try? FileManager.default.removeItem(at: root) }
        let conn = RemoteConnection(name: "Local", host: "local-sftp-server", port: 22, username: NSUserName(), remotePath: root.path, authType: .sshKey)

        let size = try await SFTPService.shared.directorySize(remotePath: root.path, connection: conn, password: nil)
        XCTAssertEqual(size, 400, "symlinked directories are not followed")

        let hits = try await SFTPService.shared.search(root: root.path, query: "report", connection: conn, password: nil)
        XCTAssertEqual(Set(hits.map(\.name)), ["Report-Final.pdf", "deep-report.txt"], "case-insensitive, recursive")

        let limited = try await SFTPService.shared.search(root: root.path, query: "report", connection: conn, password: nil, maxResults: 1)
        XCTAssertEqual(limited.count, 1)

        let shallow = try await SFTPService.shared.search(root: root.path, query: "deep", connection: conn, password: nil, maxDepth: 1)
        XCTAssertTrue(shallow.isEmpty, "depth limit respected")
    }
}

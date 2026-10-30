import XCTest
@testable import yunsftp

@MainActor
final class PaneNavigationModeTests: XCTestCase {

    private func waitUntil(_ timeout: TimeInterval = 5, _ cond: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    func testLocalFavouriteWhileConnectedSwitchesPaneBackToLocal() async throws {
        guard FileManager.default.fileExists(atPath: "/usr/libexec/sftp-server") else { throw XCTSkip("no sftp-server") }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_nav_\(UUID().uuidString)")
        let remote = base.appendingPathComponent("remote"); let local = base.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try "r".write(to: remote.appendingPathComponent("remote.txt"), atomically: true, encoding: .utf8)
        try "l".write(to: local.appendingPathComponent("local.txt"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: base) }

        let conn = RemoteConnection(name: "Local", host: "local-sftp-server", port: 22, username: NSUserName(), remotePath: remote.path, authType: .sshKey)
        let pane = PaneModel(initialURL: FileManager.default.temporaryDirectory, autoLoad: false)
        pane.connectRemote(connection: conn)
        await waitUntil { !pane.isLoading }
        XCTAssertTrue(pane.isRemote)
        XCTAssertTrue(pane.items.contains { $0.name == "remote.txt" })

        // Sidebar "Devices"/favourite click: a file URL must leave remote mode, not become a remote path.
        pane.navigateTo(local)
        await waitUntil { !pane.isLoading }
        XCTAssertFalse(pane.isRemote)
        XCTAssertNil(pane.remoteConnection)
        XCTAssertEqual(pane.currentURL.standardizedFileURL, local.standardizedFileURL)
        XCTAssertTrue(pane.items.contains { $0.name == "local.txt" })
        XCTAssertNil(pane.errorMessage)

        // Back re-enters the server session at the same path.
        XCTAssertTrue(pane.canGoBack)
        pane.goBack()
        await waitUntil { !pane.isLoading }
        XCTAssertTrue(pane.isRemote)
        XCTAssertEqual(pane.remotePath, SFTPService.normalizeRemotePath(remote.path))
        XCTAssertTrue(pane.items.contains { $0.name == "remote.txt" })
    }

    func testRemoteURLWithoutKnownConnectionIsIgnored() {
        let pane = PaneModel(initialURL: FileManager.default.temporaryDirectory, autoLoad: false)
        let before = pane.currentURL
        pane.navigateTo(SFTPService.sftpURL(host: "nowhere.example", port: 22, path: "/srv"))
        XCTAssertFalse(pane.isRemote)
        XCTAssertEqual(pane.currentURL, before)
    }

    func testNonFileNonSftpURLIsIgnored() {
        let pane = PaneModel(initialURL: FileManager.default.temporaryDirectory, autoLoad: false)
        let before = pane.currentURL
        pane.navigateTo(URL(string: "https://example.com/x")!)
        XCTAssertEqual(pane.currentURL, before)
    }
}

extension PaneNavigationModeTests {
    func testRemoteURLOfAnotherServerIsNotAppliedToTheCurrentSession() {
        let pane = PaneModel(initialURL: FileManager.default.temporaryDirectory, autoLoad: false)
        let a = RemoteConnection(name: "A", host: "a.example", port: 22)
        pane.isRemote = true
        pane.remoteConnection = a
        pane.remotePath = "/data"
        pane.navigateTo(SFTPService.sftpURL(host: "b.example", port: 22, path: "/other"))
        XCTAssertEqual(pane.remoteConnection?.id, a.id)
        XCTAssertEqual(pane.remotePath, "/data", "a history entry from another server is ignored")
    }
}

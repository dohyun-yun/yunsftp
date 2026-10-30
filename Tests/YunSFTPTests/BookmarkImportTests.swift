import XCTest
@testable import yunsftp

final class BookmarkImportTests: XCTestCase {

    func testParsesHostBlocksAndSkipsWildcards() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sshcfg_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("conf.d"), withIntermediateDirectories: true)
        try """
        Host extra
            HostName 10.0.0.9
            User ops
        """.write(to: dir.appendingPathComponent("conf.d/extra.conf"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let text = """
        # comment
        Include conf.d/*.conf

        Host *
            ServerAliveInterval 30

        Host nas home-nas
            HostName nas.example.com
            Port=2222
            User leon
            IdentityFile ~/.ssh/id_nas
            IdentityFile ~/.ssh/other

        Host bastion !bastion-old prod-?
            hostname bastion.example.com

        Match host something
            User ignored
        """
        let conns = SSHConfigImporter.parse(text, baseDirectory: dir)
        let byName = Dictionary(uniqueKeysWithValues: conns.map { ($0.name, $0) })
        XCTAssertEqual(Set(byName.keys), ["extra", "nas", "home-nas", "bastion"])

        let nas = try XCTUnwrap(byName["nas"])
        XCTAssertEqual(nas.host, "nas.example.com")
        XCTAssertEqual(nas.port, 2222)
        XCTAssertEqual(nas.username, "leon")
        XCTAssertEqual(nas.authType, .sshKey)
        XCTAssertEqual(nas.keyFilePath, NSHomeDirectory() + "/.ssh/id_nas", "first IdentityFile wins")

        let bastion = try XCTUnwrap(byName["bastion"])
        XCTAssertEqual(bastion.host, "bastion.example.com")
        XCTAssertEqual(bastion.port, 22)
        XCTAssertEqual(bastion.authType, .password)

        XCTAssertEqual(byName["extra"]?.host, "10.0.0.9")
    }

    func testCyberduckBookmarkParsing() {
        let sftp: [String: Any] = ["Protocol": "sftp", "Hostname": "box.example.com", "Port": "2200", "Username": "me", "Nickname": "Box", "Path": "/srv"]
        let c = CyberduckImporter.connection(from: sftp)
        XCTAssertEqual(c?.name, "Box")
        XCTAssertEqual(c?.port, 2200)
        XCTAssertEqual(c?.remotePath, "/srv")
        XCTAssertNil(CyberduckImporter.connection(from: ["Protocol": "ftp", "Hostname": "x"]), "non-SFTP bookmarks are skipped")
        XCTAssertNil(CyberduckImporter.connection(from: ["Protocol": "sftp"]))
    }

    @MainActor
    func testImportDeduplicatesByHostPortAndUser() {
        let manager = ConnectionManager()
        manager.connections = [RemoteConnection(name: "A", host: "Nas.Example.com", port: 22, username: "u")]
        let added = manager.importConnections([
            RemoteConnection(name: "dup", host: "nas.example.com", port: 22, username: "u"),
            RemoteConnection(name: "other-user", host: "nas.example.com", port: 22, username: "root"),
            RemoteConnection(name: "other-port", host: "nas.example.com", port: 2222, username: "u")
        ])
        XCTAssertEqual(added, 2)
        XCTAssertEqual(manager.connections.count, 3)
    }
}

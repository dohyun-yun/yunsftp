import XCTest
import CryptoKit
@testable import yunsftp

final class KnownHostsTests: XCTestCase {
    private func store(_ contents: String) throws -> KnownHosts {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kh_\(UUID().uuidString)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return KnownHosts(fileURL: url)
    }

    func testPlainEntriesPortsAndMismatch() throws {
        let kh = try store("""
        # comment
        nas.example.com,10.0.0.5 ssh-ed25519 AAAAkey1
        [nas.example.com]:2222 ssh-ed25519 AAAAkey2
        *.lab.example ssh-rsa AAAAkey3
        """)
        XCTAssertEqual(kh.verdict(host: "NAS.example.com", port: 22, keyType: "ssh-ed25519", keyBase64: "AAAAkey1"), .trusted)
        XCTAssertEqual(kh.verdict(host: "10.0.0.5", port: 22, keyType: "ssh-ed25519", keyBase64: "AAAAkey1"), .trusted)
        XCTAssertEqual(kh.verdict(host: "nas.example.com", port: 2222, keyType: "ssh-ed25519", keyBase64: "AAAAkey2"), .trusted)
        XCTAssertEqual(kh.verdict(host: "nas.example.com", port: 22, keyType: "ssh-ed25519", keyBase64: "AAAAother"), .mismatch)
        XCTAssertEqual(kh.verdict(host: "nas.example.com", port: 22, keyType: "ssh-rsa", keyBase64: "AAAAother"), .unknown, "a different key type is not a mismatch")
        XCTAssertEqual(kh.verdict(host: "box.lab.example", port: 22, keyType: "ssh-rsa", keyBase64: "AAAAkey3"), .trusted)
        XCTAssertEqual(kh.verdict(host: "elsewhere", port: 22, keyType: "ssh-ed25519", keyBase64: "x"), .unknown)
    }

    func testHashedEntriesMatchViaHMAC() throws {
        let salt = Data((0..<20).map { UInt8($0) })
        let pattern = KnownHosts.hostPattern(host: "secret.example", port: 2200)
        let mac = Data(HMAC<Insecure.SHA1>.authenticationCode(for: Data(pattern.utf8), using: SymmetricKey(data: salt)))
        let kh = try store("|1|\(salt.base64EncodedString())|\(mac.base64EncodedString()) ssh-ed25519 AAAAhashed\n")
        XCTAssertEqual(kh.verdict(host: "secret.example", port: 2200, keyType: "ssh-ed25519", keyBase64: "AAAAhashed"), .trusted)
        XCTAssertEqual(kh.verdict(host: "secret.example", port: 22, keyType: "ssh-ed25519", keyBase64: "AAAAhashed"), .unknown)
    }

    func testRememberAppendsOpenSSHCompatibleLine() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kh_\(UUID().uuidString)/known_hosts")
        let kh = KnownHosts(fileURL: url)
        try kh.remember(host: "Host.Example", port: 2299, keyType: "ssh-ed25519", keyBase64: "AAAAnew")
        try kh.remember(host: "plain.example", port: 22, keyType: "ssh-rsa", keyBase64: "AAAArsa")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(text, "[host.example]:2299 ssh-ed25519 AAAAnew\nplain.example ssh-rsa AAAArsa\n")
        XCTAssertEqual(kh.verdict(host: "host.example", port: 2299, keyType: "ssh-ed25519", keyBase64: "AAAAnew"), .trusted)
    }
}

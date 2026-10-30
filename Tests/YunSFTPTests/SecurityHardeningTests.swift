import XCTest
@testable import yunsftp

final class SecurityHardeningTests: XCTestCase {

    // MARK: - Item 1/2: host key verification, algorithm defaults, session reuse

    func testSSHOptionsVerifyHostKeys() {
        let opts = SFTPService.commonSSHOptions.joined(separator: " ")
        XCTAssertFalse(opts.contains("StrictHostKeyChecking=no"))
        XCTAssertFalse(opts.contains("UserKnownHostsFile=/dev/null"))
        XCTAssertTrue(opts.contains("StrictHostKeyChecking=accept-new"))
    }

    func testSSHOptionsDoNotEnableWeakAlgorithms() {
        let opts = SFTPService.commonSSHOptions.joined(separator: " ").lowercased()
        XCTAssertFalse(opts.contains("sha1"))
        XCTAssertFalse(opts.contains("+ssh-rsa"))
        XCTAssertFalse(opts.contains("kexalgorithms"))
        XCTAssertFalse(opts.contains("hostkeyalgorithms"))
    }

    func testSSHOptionsReuseSessions() {
        let opts = SFTPService.commonSSHOptions.joined(separator: " ")
        XCTAssertTrue(opts.contains("ControlMaster=auto"))
        XCTAssertTrue(opts.contains("ControlPersist="))
        // Unix socket paths are limited to ~104 bytes; %C expands to 40 hex chars.
        let expanded = SFTPService.controlPath.replacingOccurrences(of: "%C", with: String(repeating: "a", count: 40))
        XCTAssertLessThan(expanded.utf8.count, 104)
    }

    func testHostKeyMismatchProducesActionableError() {
        let raw = "Host key verification failed."
        let msg = SFTPService.translateErrorMessage(raw, exitCode: 255)
        XCTAssertTrue(msg.contains("known_hosts"))
        XCTAssertTrue(msg.contains("ssh-keygen -R"))
    }
}

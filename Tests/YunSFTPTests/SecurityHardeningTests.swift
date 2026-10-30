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

extension SecurityHardeningTests {

    // MARK: - Item 3: authentication failures must not trigger transport fallbacks

    func testAuthenticationFailureIsRecognisedFromSSHOutput() {
        XCTAssertTrue(SFTPService.isAuthenticationFailureText("user@host: Permission denied (publickey,password)."))
        XCTAssertTrue(SFTPService.isAuthenticationFailureText("Received disconnect: Too many authentication failures"))
        XCTAssertFalse(SFTPService.isAuthenticationFailureText("Couldn't stat remote file: No such file or directory"))
        XCTAssertFalse(SFTPService.isAuthenticationFailureText("remote open(\"/root/x\"): Permission denied"))
    }

    func testAuthenticationFailureErrorIsTyped() {
        let auth = NSError(domain: "SFTPService", code: SFTPService.authenticationFailureCode)
        let other = NSError(domain: "SFTPService", code: 1)
        XCTAssertTrue(SFTPService.isAuthenticationFailure(auth))
        XCTAssertFalse(SFTPService.isAuthenticationFailure(other))
    }

    func testFallbackCatchClausesSkipAuthenticationFailures() throws {
        // Every transport fallback in SFTPService must be guarded so that an auth failure
        // propagates instead of retrying with a different transport (= another failed login).
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/YunSFTP/Services/SFTPService.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        let bareCatches = source.components(separatedBy: "\n").filter { $0.trimmingCharacters(in: .whitespaces) == "} catch {" }
        // Only runProcess' own cleanup catches may remain unguarded.
        XCTAssertEqual(bareCatches.count, 2, "unguarded catch blocks: \(bareCatches.count)")
    }
}

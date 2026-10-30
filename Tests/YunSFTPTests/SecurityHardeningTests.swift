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
        // Only runProcess' cleanup catches and download's partial-file cleanup (which rethrows) may remain unguarded.
        XCTAssertEqual(bareCatches.count, 4, "unguarded catch blocks: \(bareCatches.count)")
    }
}

extension SecurityHardeningTests {

    // MARK: - Item 4: Terminal AppleScript must not be injectable through connection fields

    func testSSHCommandQuotesHostileConnectionFields() {
        let conn = RemoteConnection(
            name: "evil",
            host: "example.com; rm -rf ~",
            port: 2222,
            username: "me\"; say pwned; \"",
            authType: .sshKey,
            keyFilePath: "~/my keys/id_ed25519"
        )
        let cmd = ConnectionManager.sshCommand(for: conn)
        XCTAssertEqual(cmd, "ssh -p 2222 -i '\(NSHomeDirectory())/my keys/id_ed25519' -- 'me\"; say pwned; \"@example.com; rm -rf ~'")
    }

    func testSSHCommandBlocksOptionInjectionViaHost() {
        let conn = RemoteConnection(name: "opt", host: "-oProxyCommand=touch /tmp/x", port: 22)
        let cmd = ConnectionManager.sshCommand(for: conn)
        XCTAssertTrue(cmd.hasSuffix("-- '-oProxyCommand=touch /tmp/x'"))
    }

    func testAppleScriptSourceEscapesQuotesAndBackslashes() {
        let src = TerminalService.appleScriptSource(for: "echo 'a\"b\\c'")
        XCTAssertTrue(src.contains("do script \"echo 'a\\\"b\\\\c'\""))
    }
}

extension SecurityHardeningTests {

    // MARK: - Item 5: remote deletion is confirmed and never shells out to rm -rf

    func testRemoteDeleteNeverUsesShellRemove() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/YunSFTP/Services/SFTPService.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(source.contains("rm -rf"))
        XCTAssertFalse(source.contains("rm -f "))
    }

    @MainActor
    func testRemoteDeleteAlertTextMentionsPermanence() {
        let single = MainWindowView.remoteDeleteAlertText(itemNames: ["report.pdf"])
        XCTAssertEqual(single.title, "Delete \"report.pdf\" from the server?")
        XCTAssertTrue(single.message.contains("permanently"))
        let many = MainWindowView.remoteDeleteAlertText(itemNames: ["a", "b", "c"])
        XCTAssertEqual(many.title, "Delete 3 items from the server?")
    }
}

extension SecurityHardeningTests {

    // MARK: - Item 6: askpass helper is created atomically with owner-only permissions

    func testAskpassScriptIsOwnerOnlyAndEchoesPassword() throws {
        let password = "p@ss \"word\" $(touch /tmp/x) 한글"
        let url = try SFTPService.writeAskpassScript(password: password)
        defer { try? FileManager.default.removeItem(at: url) }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = [url.path]
        let out = Pipe()
        proc.standardOutput = out
        try proc.run()
        proc.waitUntilExit()
        let printed = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
        XCTAssertEqual(printed, password)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/x"))
    }
}

extension SecurityHardeningTests {

    // MARK: - Item 21: legacy algorithms are per-connection opt-in

    func testLegacyAlgorithmsAreOffByDefaultAndOptIn() {
        let normal = RemoteConnection(name: "n", host: "h")
        XCTAssertFalse(SFTPService.sshOptions(for: normal).joined(separator: " ").lowercased().contains("sha1"))

        var legacy = normal
        legacy.allowLegacyAlgorithms = true
        let opts = SFTPService.sshOptions(for: legacy).joined(separator: " ")
        XCTAssertTrue(opts.contains("diffie-hellman-group14-sha1"))
        XCTAssertTrue(opts.contains("HostkeyAlgorithms=+ssh-rsa"))
        XCTAssertTrue(opts.contains("StrictHostKeyChecking=accept-new"), "legacy mode must not weaken host key checks")
    }

    func testConnectionsSavedWithoutLegacyFlagStillDecode() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Old","connectionProtocol":"SFTP (SSH File Transfer)","host":"h","port":22,"username":"u","remotePath":"/","authType":"Password","keyFilePath":"","isImportedFromForkLift2":false}
        """
        let conn = try JSONDecoder().decode(RemoteConnection.self, from: Data(json.utf8))
        XCTAssertFalse(conn.allowLegacyAlgorithms)
        let roundTrip = try JSONDecoder().decode(RemoteConnection.self, from: JSONEncoder().encode(conn))
        XCTAssertEqual(roundTrip, conn)
    }

    func testAlgorithmNegotiationFailurePointsToLegacyToggle() {
        let msg = SFTPService.translateErrorMessage("Unable to negotiate with 10.0.0.1 port 22: no matching key exchange method found. Their offer: diffie-hellman-group1-sha1", exitCode: 255)
        XCTAssertTrue(msg.contains("Allow legacy SSH algorithms"))
    }
}

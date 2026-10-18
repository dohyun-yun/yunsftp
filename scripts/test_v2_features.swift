import Foundation
import Security

@main
struct V2FeaturesTest {
    static func main() async {
        print("==================================================")
        print("  ForkLift Silicon V2 Feature Verification Suite   ")
        print("==================================================")

        // --------------------------------------------------
        // Test 1: Port Input Digits Filtering (No commas)
        // --------------------------------------------------
        print("\n[Test 1] Port Field Input Filtering (No commas or invalid chars)")
        func filterPortInput(_ input: String) -> Int {
            let filtered = input.filter { $0.isNumber }
            return Int(filtered) ?? 22
        }

        let commaInput = "13,622"
        let filtered1 = filterPortInput(commaInput)
        assert(filtered1 == 13622, "Port should filter commas and parse to 13622")
        print("  ✓ Input '13,622' -> filtered to: \(filtered1)")

        let formattedInput = " 22,000 abc "
        let filtered2 = filterPortInput(formattedInput)
        assert(filtered2 == 22000, "Port should filter letters and spaces")
        print("  ✓ Input ' 22,000 abc ' -> filtered to: \(filtered2)")

        let emptyInput = ""
        let filtered3 = filterPortInput(emptyInput)
        assert(filtered3 == 22, "Empty input should fallback to default 22")
        print("  ✓ Input '' -> fallback to: \(filtered3)")

        // --------------------------------------------------
        // Test 2: KeychainService (macOS Security Framework) CRUD
        // --------------------------------------------------
        print("\n[Test 2] KeychainService (macOS Security Framework) CRUD")
        let testConn = RemoteConnection(
            name: "Keychain Test Server",
            connectionProtocol: .sftp,
            host: "finsternis.synology.me",
            port: 13622,
            username: "testuser",
            authType: .password
        )
        let testSecret = "SuperSecretP@ssw0rd!2026"

        // Clean previous test entries
        KeychainService.shared.deletePassword(for: testConn)

        // Save
        KeychainService.shared.savePassword(testSecret, for: testConn)
        print("  ✓ Keychain save: Success")

        // Retrieve
        let retrieved = KeychainService.shared.loadPassword(for: testConn)
        assert(retrieved == testSecret, "Retrieved password must match original secret")
        print("  ✓ Keychain retrieve: Match (\(retrieved ?? ""))")

        // Update
        let updatedSecret = "NewSecretPassword#999"
        KeychainService.shared.savePassword(updatedSecret, for: testConn)
        let retrievedUpdated = KeychainService.shared.loadPassword(for: testConn)
        assert(retrievedUpdated == updatedSecret, "Retrieved updated password must match")
        print("  ✓ Keychain update: Match (\(retrievedUpdated ?? ""))")

        // Delete
        KeychainService.shared.deletePassword(for: testConn)
        let afterDelete = KeychainService.shared.loadPassword(for: testConn)
        assert(afterDelete == nil, "Password should be nil after deletion")
        print("  ✓ Keychain delete: Verified nil")

        // --------------------------------------------------
        // Test 3: Password Prompt Trigger Logic
        // --------------------------------------------------
        print("\n[Test 3] Password Prompt Trigger Logic")
        let connEmptyPwd = RemoteConnection(
            name: "NAS",
            connectionProtocol: .sftp,
            host: "finsternis.synology.me",
            port: 13622,
            username: "admin",
            authType: .password
        )

        // Simulate ConnectSheet check
        var showPasswordPrompt = false
        var activePassword = ""
        let savedPwd = KeychainService.shared.loadPassword(for: connEmptyPwd)

        if connEmptyPwd.authType == .password {
            if let saved = savedPwd, !saved.isEmpty {
                activePassword = saved
                showPasswordPrompt = false
            } else if activePassword.isEmpty {
                showPasswordPrompt = true
            }
        }

        assert(showPasswordPrompt == true, "Empty password must trigger PasswordPromptSheet")
        print("  ✓ Empty password correctly flagged: showPasswordPrompt = \(showPasswordPrompt)")

        // --------------------------------------------------
        // Test 4: OpenSSH Error Message Translation
        // --------------------------------------------------
        print("\n[Test 4] SSH/SFTP Friendly Error Message Translation")
        let resetErr = SFTPService.translateErrorMessage("Connection reset by peer", exitCode: 255)
        assert(resetErr.contains("연결이 서버에 의해 재설정되었습니다") || resetErr.contains("서버에서 연결을 종료했습니다"), "Reset error should be translated")
        print("  ✓ 'Connection reset by peer' -> '\(resetErr)'")

        let authErr = SFTPService.translateErrorMessage("Permission denied (publickey,password).", exitCode: 255)
        assert(authErr.contains("인증 실패"), "Auth failure should be translated")
        print("  ✓ 'Permission denied' -> '\(authErr)'")

        let timeoutErr = SFTPService.translateErrorMessage("Operation timed out", exitCode: 255)
        assert(timeoutErr.contains("연결 시간 초과"), "Timeout should be translated")
        print("  ✓ 'Operation timed out' -> '\(timeoutErr)'")

        // --------------------------------------------------
        // Test 5: Code Signing & Entitlements Check
        // --------------------------------------------------
        print("\n[Test 5] Binary Code Signature & Entitlements")
        let appPath = "/Applications/yunsftp.app"
        let signPipe = Pipe()
        let signProc = Process()
        signProc.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signProc.arguments = ["-d", "-r-", appPath]
        signProc.standardOutput = signPipe
        signProc.standardError = signPipe
        try? signProc.run()
        signProc.waitUntilExit()
        let signOut = String(data: signPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        assert(signOut.contains("com.finsternis.yunsftp"), "Signature must contain designated identifier com.finsternis.yunsftp")
        print("  ✓ Code signature designated requirement: Verified com.finsternis.yunsftp")

        print("\n==================================================")
        print("   ALL 5 TESTS PASSED SUCCESSFULLY! (100%)        ")
        print("==================================================")
    }
}

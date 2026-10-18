import XCTest
@testable import yunsftp

final class SFTPTransferAndEscapeTests: XCTestCase {
    
    func testDecodeOctalEscapesKorean() {
        // Octal-escaped UTF-8 bytes for: 테스트 [한글] (2026).txt
        let input = "\\355\\205\\214\\354\\212\\244\\355\\212\\270 [\\355\\225\\234\\352\\270\\200] (2026).txt"
        let decoded = SFTPService.decodeLsEscapes(input)
        XCTAssertEqual(decoded, "테스트 [한글] (2026).txt")
    }

    func testDecodeHexEscapes() {
        // Hex-escaped UTF-8 bytes for: 한글
        let input = "\\xed\\x95\\x9c\\xea\\xb8\\x80"
        let decoded = SFTPService.decodeLsEscapes(input)
        XCTAssertEqual(decoded, "한글")
    }

    func testDecodeStandardCEscapes() {
        let input = "hello\\ world\\\"test\\\\file"
        let decoded = SFTPService.decodeLsEscapes(input)
        XCTAssertEqual(decoded, "hello world\"test\\file")
    }

    func testDecodePreservesCleanKorean() {
        let clean = "한국어_동영상_[2026].mp4"
        let decoded = SFTPService.decodeLsEscapes(clean)
        XCTAssertEqual(decoded, clean)
    }

    func testDecodePathBreadcrumbs() {
        let input = "/volume1/\\355\\225\\234\\352\\270\\200/\\353\\254\\270\\354\\204\\234"
        let decoded = SFTPService.decodeLsEscapes(input)
        XCTAssertEqual(decoded, "/volume1/한글/문서")
    }

    @MainActor
    func testPaneModelConnectingStateClearsGhostItems() {
        let pane = PaneModel(initialURL: FileManager.default.homeDirectoryForCurrentUser)
        // Ensure initial local pane has items
        XCTAssertFalse(pane.isRemote)

        let conn = RemoteConnection(
            name: "Synology NAS",
            host: "192.168.1.100",
            port: 22,
            username: "admin",
            remotePath: "/video"
        )

        // Initiate remote connection
        pane.connectRemote(connection: conn, password: "test")

        // Crucial test: When connecting to remote, old local files (잔상) must be cleared immediately
        XCTAssertTrue(pane.isRemote)
        XCTAssertTrue(pane.items.isEmpty, "Existing items must be cleared immediately when connecting to remote to prevent ghost items")
        XCTAssertTrue(pane.isConnecting, "Pane must be in isConnecting state")
        XCTAssertTrue(pane.isLoading, "Pane must be in isLoading state")
        XCTAssertEqual(pane.connectingMessage, "'Synology NAS' 서버에 연결 중...")

        // Disconnecting must reset states
        pane.disconnectRemote()
        XCTAssertFalse(pane.isRemote)
        XCTAssertFalse(pane.isConnecting)
    }

    func testSFTPLocalServerDownloadWithKoreanAndBrackets() throws {
        // Use macOS built-in sftp-server to verify local SFTP download functionality
        let sftpServerBinary = "/usr/libexec/sftp-server"
        guard FileManager.default.fileExists(atPath: sftpServerBinary) else {
            throw XCTSkip("sftp-server binary not found at /usr/libexec/sftp-server")
        }

        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_test_\(UUID().uuidString)")
        let sourceDir = tempBase.appendingPathComponent("source")
        let destDir = tempBase.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        defer {
            try? FileManager.default.removeItem(at: tempBase)
        }

        let fileName = "테스트 [한글] (2026).txt"
        let fileContent = "안녕하세요! SFTP 로컬 다운로드 및 복사 테스트입니다."
        let sourceFileURL = sourceDir.appendingPathComponent(fileName)
        try fileContent.write(to: sourceFileURL, atomically: true, encoding: .utf8)

        // Execute batch download via sftp -D
        let sftpBatch = """
        lcd \(SFTPService.sftpQuote(destDir.path))
        cd \(SFTPService.sftpQuote(sourceDir.path))
        get -R \(SFTPService.sftpQuote(fileName))
        exit
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        process.arguments = ["-D", sftpServerBinary, "dummy"]
        
        var env = ProcessInfo.processInfo.environment
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        env["LC_CTYPE"] = "UTF-8"
        process.environment = env

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        if let data = sftpBatch.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        try? stdinPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let destFileURL = destDir.appendingPathComponent(fileName)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destFileURL.path), "Downloaded file must exist in dest directory")
        let downloadedContent = try String(contentsOf: destFileURL, encoding: .utf8)
        XCTAssertEqual(downloadedContent, fileContent)
    }
}

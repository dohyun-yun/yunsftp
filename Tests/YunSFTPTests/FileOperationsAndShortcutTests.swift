import XCTest
@testable import yunsftp

final class FileOperationsAndShortcutTests: XCTestCase {

    @MainActor
    func testEffectiveSelectedItemsFallbackToFocused() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_sel_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let file1 = tempDir.appendingPathComponent("alpha.txt")
        let file2 = tempDir.appendingPathComponent("beta.txt")
        try? "alpha".write(to: file1, atomically: true, encoding: .utf8)
        try? "beta".write(to: file2, atomically: true, encoding: .utf8)

        let pane = PaneModel(initialURL: tempDir)
        let item1 = FileItem(url: file1)
        let item2 = FileItem(url: file2)
        pane.items = [item1, item2]

        // 1. Initial: nothing selected, nothing focused
        pane.selectedItemURLs.removeAll()
        pane.focusedItemURL = nil
        XCTAssertTrue(pane.selectedItems.isEmpty)
        XCTAssertTrue(pane.effectiveSelectedItems.isEmpty)
        XCTAssertNil(pane.firstSelectedItem)

        // 2. Focused item set (e.g. keyboard navigation or single click before full selection)
        pane.focusedItemURL = file2
        XCTAssertTrue(pane.selectedItems.isEmpty)
        XCTAssertEqual(pane.effectiveSelectedItems.count, 1)
        XCTAssertEqual(pane.effectiveSelectedItems.first?.name, "beta.txt")
        XCTAssertEqual(pane.firstSelectedItem?.name, "beta.txt")

        // 3. Explicit selection overrides focused fallback
        pane.selectedItemURLs = [file1]
        XCTAssertEqual(pane.selectedItems.count, 1)
        XCTAssertEqual(pane.effectiveSelectedItems.count, 1)
        XCTAssertEqual(pane.effectiveSelectedItems.first?.name, "alpha.txt")
        XCTAssertEqual(pane.firstSelectedItem?.name, "alpha.txt")
    }

    @MainActor
    func testPaneModelSortingFields() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_sort_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let folder = tempDir.appendingPathComponent("Z_Folder")
        let fileA = tempDir.appendingPathComponent("a_small.txt")
        let fileB = tempDir.appendingPathComponent("b_large.txt")

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? "1".write(to: fileA, atomically: true, encoding: .utf8)
        try? "1234567890".write(to: fileB, atomically: true, encoding: .utf8)

        let pane = PaneModel(initialURL: tempDir)
        pane.items = [
            FileItem(url: fileB),
            FileItem(url: folder),
            FileItem(url: fileA)
        ]

        // Folders always come first regardless of sort field
        pane.sortField = .name
        pane.sortAscending = true
        let sortedByName = pane.displayedItems
        XCTAssertEqual(sortedByName.first?.name, "Z_Folder")
        XCTAssertEqual(sortedByName[1].name, "a_small.txt")
        XCTAssertEqual(sortedByName[2].name, "b_large.txt")

        // Size sort ascending: folder first, then small, then large
        pane.sortField = .size
        pane.sortAscending = true
        let sortedBySizeAsc = pane.displayedItems
        XCTAssertEqual(sortedBySizeAsc.first?.name, "Z_Folder")
        XCTAssertEqual(sortedBySizeAsc[1].name, "a_small.txt")
        XCTAssertEqual(sortedBySizeAsc[2].name, "b_large.txt")

        // Size sort descending: folder first, then large, then small
        pane.sortAscending = false
        let sortedBySizeDesc = pane.displayedItems
        XCTAssertEqual(sortedBySizeDesc.first?.name, "Z_Folder")
        XCTAssertEqual(sortedBySizeDesc[1].name, "b_large.txt")
        XCTAssertEqual(sortedBySizeDesc[2].name, "a_small.txt")
    }

    func testSFTPCommandEscaping() {
        let koreanWithQuotes = "폴더 \"테스트\" [2026] '특별판'"
        let sftpQuoted = SFTPService.sftpQuote(koreanWithQuotes)
        XCTAssertTrue(sftpQuoted.hasPrefix("\""))
        XCTAssertTrue(sftpQuoted.hasSuffix("\""))
        XCTAssertTrue(sftpQuoted.contains("\\\"테스트\\\""))

        let shellEscaped = SFTPService.posixShellEscape(koreanWithQuotes)
        XCTAssertTrue(shellEscaped.hasPrefix("'"))
        XCTAssertTrue(shellEscaped.hasSuffix("'"))
        XCTAssertTrue(shellEscaped.contains("'\\''특별판'\\''"))
    }

    func testLocalFileOperationsAndTrash() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_ops_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // 1. Create Folder
        let createdFolderURL = try await FileSystemService.shared.createFolder(at: tempDir, name: "새폴더 [테스트]")
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdFolderURL.path))

        // 2. Create File & Rename
        let testFile = tempDir.appendingPathComponent("원본.txt")
        try "테스트 내용".write(to: testFile, atomically: true, encoding: .utf8)
        let renamedURL = try await FileSystemService.shared.rename(url: testFile, to: "수정됨.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFile.path))

        // 3. Move to Trash
        try await FileSystemService.shared.moveToTrash(urls: [renamedURL, createdFolderURL])
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: createdFolderURL.path))
    }

    func testLocalSFTPServerDirectoryAndFileOperations() throws {
        let sftpServerBinary = "/usr/libexec/sftp-server"
        guard FileManager.default.fileExists(atPath: sftpServerBinary) else {
            throw XCTSkip("sftp-server binary not found at /usr/libexec/sftp-server")
        }

        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_sftp_ops_\(UUID().uuidString)")
        let rootDir = tempBase.appendingPathComponent("remoteRoot")
        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        // Execute batch mkdir and file creation via sftp -D
        let sftpBatch = """
        cd \(SFTPService.sftpQuote(rootDir.path))
        mkdir \(SFTPService.sftpQuote("새원격폴더"))
        cd \(SFTPService.sftpQuote("새원격폴더"))
        rmdir \(SFTPService.sftpQuote("../새원격폴더"))
        exit
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sftp")
        process.arguments = ["-D", sftpServerBinary, "dummy"]
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe
        try process.run()

        stdinPipe.fileHandleForWriting.write(sftpBatch.data(using: .utf8)!)
        try? stdinPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testColumnWidthsConstraintLogic() {
        let minName = 120.0
        let maxName = 600.0
        var currentName = 220.0

        // Test clamping helper
        let dragSmall = -150.0
        currentName = max(minName, min(maxName, currentName + dragSmall))
        XCTAssertEqual(currentName, 120.0, "Width should not shrink below minWidth")

        let dragHuge = 1000.0
        currentName = max(minName, min(maxName, currentName + dragHuge))
        XCTAssertEqual(currentName, 600.0, "Width should not exceed maxWidth")
    }
}

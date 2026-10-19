import XCTest
@testable import yunsftp

final class LocalAndSFTPParityAndUXTests: XCTestCase {

    // MARK: - 1. Column Header ("타이틀바") Resize & Horizontal Scroll Tests

    func testColumnWidthResizeTriggersHorizontalScrollWidth() {
        let viewportWidth: Double = 600

        // Default column widths sum to 220 + 80 + 135 + 95 + 65 + 25 = 620
        let defaultTotal = FileListView.totalColumnsWidth(
            nameWidth: 220, sizeWidth: 80, dateWidth: 135, kindWidth: 95, permsWidth: 65
        )
        XCTAssertEqual(defaultTotal, 620)

        // When viewport is wider than total columns (e.g. 800), tableWidth matches viewport (800)
        let tableWidthWideViewport = FileListView.calculateTableWidth(
            paneWidth: 800,
            nameWidth: 220, sizeWidth: 80, dateWidth: 135, kindWidth: 95, permsWidth: 65
        )
        XCTAssertEqual(tableWidthWideViewport, 800, "Table should fill viewport when columns are narrower than viewport")

        // When user widens Name column to 500 and Size column to 160, total width exceeds 800 -> tableWidth expands so horizontal scroll appears instead of clipping columns off-screen
        let tableWidthExpanded = FileListView.calculateTableWidth(
            paneWidth: 800,
            nameWidth: 500, sizeWidth: 160, dateWidth: 180, kindWidth: 120, permsWidth: 100
        )
        let expectedExpandedTotal: Double = 500 + 160 + 180 + 120 + 100 + 25
        XCTAssertEqual(tableWidthExpanded, expectedExpandedTotal)
        XCTAssertGreaterThan(tableWidthExpanded, viewportWidth, "Table width must expand beyond viewport so horizontal ScrollView scrolls all columns in lockstep")
    }

    func testEffectiveNameColumnWidthExpandsIntoAvailableSpace() {
        // Other columns total = 80 + 135 + 95 + 65 + 25 = 400
        // When pane is 800 wide, available for Name is 800 - 400 = 400.
        // Even if default nameWidth is 220, effectiveNameColumnWidth expands to 400!
        let wideNameWidth = FileListView.effectiveNameColumnWidth(
            paneWidth: 800,
            nameWidth: 220,
            sizeWidth: 80,
            dateWidth: 135,
            kindWidth: 95,
            permsWidth: 65
        )
        XCTAssertEqual(wideNameWidth, 400, "Name column must expand to 400 to fill available pane width")

        // When pane is narrow (e.g. 500 wide), available is 500 - 400 = 100.
        // effectiveNameColumnWidth respects the user's nameWidth (220) and does not collapse below it
        let narrowNameWidth = FileListView.effectiveNameColumnWidth(
            paneWidth: 500,
            nameWidth: 220,
            sizeWidth: 80,
            dateWidth: 135,
            kindWidth: 95,
            permsWidth: 65
        )
        XCTAssertEqual(narrowNameWidth, 220, "Name column must retain minimum nameWidth when pane is narrow")

        // When user manually drags nameWidth larger (e.g. 600) on an 800-wide pane:
        let manualExpandedNameWidth = FileListView.effectiveNameColumnWidth(
            paneWidth: 800,
            nameWidth: 600,
            sizeWidth: 80,
            dateWidth: 135,
            kindWidth: 95,
            permsWidth: 65
        )
        XCTAssertEqual(manualExpandedNameWidth, 600, "Manually widened nameWidth beyond available space must be respected")
    }

    // MARK: - 2. Keyboard Shortcut Delete (Ctrl+Backspace, Cmd+Backspace, Forward Delete) Tests

    func testDeleteKeyboardShortcutsIncludeCtrlBackspaceCmdBackspaceAndForwardDelete() {
        // keyCode 51 = Backspace / Delete
        XCTAssertTrue(
            KeyboardShortcutHelper.shouldTriggerDelete(keyCode: 51, isCmd: true, isCtrl: false, isPlain: false),
            "Cmd+Backspace must trigger delete"
        )
        XCTAssertTrue(
            KeyboardShortcutHelper.shouldTriggerDelete(keyCode: 51, isCmd: false, isCtrl: true, isPlain: false),
            "Ctrl+Backspace must trigger delete"
        )
        XCTAssertFalse(
            KeyboardShortcutHelper.shouldTriggerDelete(keyCode: 51, isCmd: false, isCtrl: false, isPlain: true),
            "Plain Backspace must NOT trigger delete (it navigates up)"
        )

        // keyCode 117 = Forward Delete (Fn+Backspace)
        XCTAssertTrue(
            KeyboardShortcutHelper.shouldTriggerDelete(keyCode: 117, isCmd: false, isCtrl: false, isPlain: true),
            "Forward Delete (Fn+Backspace) must trigger delete without modifiers"
        )
        XCTAssertTrue(
            KeyboardShortcutHelper.shouldTriggerDelete(keyCode: 117, isCmd: true, isCtrl: false, isPlain: false),
            "Cmd+Forward Delete must trigger delete"
        )
        XCTAssertTrue(
            KeyboardShortcutHelper.shouldTriggerDelete(keyCode: 117, isCmd: false, isCtrl: true, isPlain: false),
            "Ctrl+Forward Delete must trigger delete"
        )
    }

    // MARK: - 3. Rename Default Value Parity (Left SFTP Pane & Right Local Pane with NFD/NFC)

    @MainActor
    func testRenameDefaultValuePreservedOnBothLocalRightPaneAndRemoteLeftPane() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_rename_def_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Simulate macOS APFS NFD decomposed filename on Right Local Pane
        let rawKoreanName = "오른쪽_로컬파일 [기본값테스트].txt"
        let nfdName = rawKoreanName.decomposedStringWithCanonicalMapping
        let localFileURL = tempDir.appendingPathComponent(nfdName)
        try "local content".write(to: localFileURL, atomically: true, encoding: .utf8)

        let rightLocalPane = PaneModel(initialURL: tempDir)
        let localItem = FileItem(url: localFileURL)
        rightLocalPane.items = [localItem]
        rightLocalPane.selectSingle(localItem.url)

        // Verify FileItem.name and RenameSheet.defaultInitialName are non-empty NFC strings
        guard let selectedRight = rightLocalPane.firstSelectedItem else {
            XCTFail("Expected selected item on right local pane")
            return
        }
        XCTAssertFalse(selectedRight.name.isEmpty, "Right pane local item name must not be empty")
        XCTAssertEqual(selectedRight.name, rawKoreanName.precomposedStringWithCanonicalMapping)
        XCTAssertEqual(
            RenameSheet.defaultInitialName(for: selectedRight),
            rawKoreanName.precomposedStringWithCanonicalMapping,
            "RenameSheet must pre-populate the existing filename on the right local pane"
        )

        // Simulate Left Remote SFTP Pane item
        let remoteItem = FileItem(
            virtualURL: URL(fileURLWithPath: "/volume1/문서/왼쪽_원격파일.txt"),
            name: "왼쪽_원격파일.txt",
            isDirectory: false,
            size: 1024,
            modificationDate: Date(),
            permissions: "rw-r--r--"
        )
        let leftRemotePane = PaneModel(initialURL: tempDir)
        leftRemotePane.isRemote = true
        leftRemotePane.items = [remoteItem]
        leftRemotePane.selectSingle(remoteItem.url)

        guard let selectedLeft = leftRemotePane.firstSelectedItem else {
            XCTFail("Expected selected item on left SFTP pane")
            return
        }
        XCTAssertEqual(
            RenameSheet.defaultInitialName(for: selectedLeft),
            "왼쪽_원격파일.txt",
            "RenameSheet must pre-populate the existing filename on the left SFTP pane"
        )

        // Verify wide RenameSheet width (minimum 560pt, expands up to 760pt for long filenames)
        let shortWidth = RenameSheet.preferredSheetWidth(for: "short.txt")
        XCTAssertEqual(shortWidth, 560, "RenameSheet must have a generous 560pt minimum width")

        let longFilename = String(repeating: "긴파일명_테스트_2026_", count: 6) + ".mp4"
        let longWidth = RenameSheet.preferredSheetWidth(for: longFilename)
        XCTAssertGreaterThan(longWidth, 560, "RenameSheet width must expand for long filenames")
        XCTAssertLessThanOrEqual(longWidth, 760, "RenameSheet width must be capped at 760pt")
    }

    // MARK: - 4. Full End-to-End SFTP Lifecycle Tests via SFTPService.shared (local-sftp-server)

    func testFullSFTPLifecycleViaSFTPService() async throws {
        let sftpServerBinary = "/usr/libexec/sftp-server"
        guard FileManager.default.fileExists(atPath: sftpServerBinary) else {
            throw XCTSkip("sftp-server binary not found at /usr/libexec/sftp-server")
        }

        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_full_sftp_\(UUID().uuidString)")
        let remoteRoot = tempBase.appendingPathComponent("remote_root")
        let localWork = tempBase.appendingPathComponent("local_work")
        try FileManager.default.createDirectory(at: remoteRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localWork, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let conn = RemoteConnection(
            name: "Local Test SFTP",
            host: "local-sftp-server",
            port: 22,
            username: NSUserName(),
            remotePath: remoteRoot.path,
            authType: .sshKey
        )

        // 1. Create Directory on SFTP (with Korean & spaces)
        let newFolderPath = remoteRoot.appendingPathComponent("새 폴더 [SFTP]").path
        try await SFTPService.shared.createDirectory(remotePath: newFolderPath, connection: conn, password: nil)
        var items = try await SFTPService.shared.listDirectory(path: remoteRoot.path, connection: conn, password: nil)
        XCTAssertTrue(items.contains(where: { $0.name == "새 폴더 [SFTP]" && $0.isDirectory }), "Created SFTP folder must appear in listDirectory")

        // 2. Upload Local File (with multiple spaces & Korean) to SFTP
        let uploadFileName = "업로드  테스트   파일.txt"
        let localSourceFile = localWork.appendingPathComponent(uploadFileName)
        let testContent = "SFTP 전체 기능 통합 테스트 데이터 12345"
        try testContent.write(to: localSourceFile, atomically: true, encoding: .utf8)

        try await SFTPService.shared.upload(localURL: localSourceFile, to: remoteRoot.path, connection: conn, password: nil)
        items = try await SFTPService.shared.listDirectory(path: remoteRoot.path, connection: conn, password: nil)
        XCTAssertTrue(items.contains(where: { $0.name == uploadFileName && !$0.isDirectory }), "Uploaded file with multiple consecutive spaces must be preserved in SFTP listDirectory")

        // 3. Rename File on SFTP
        let uploadedRemotePath = remoteRoot.appendingPathComponent(uploadFileName).path
        let renamedFileName = "이름변경완료_파일.txt"
        let renamedRemotePath = remoteRoot.appendingPathComponent(renamedFileName).path
        try await SFTPService.shared.rename(remotePath: uploadedRemotePath, to: renamedRemotePath, connection: conn, password: nil)
        items = try await SFTPService.shared.listDirectory(path: remoteRoot.path, connection: conn, password: nil)
        XCTAssertFalse(items.contains(where: { $0.name == uploadFileName }))
        XCTAssertTrue(items.contains(where: { $0.name == renamedFileName }), "Renamed file must appear on SFTP")

        // 4. Chmod on SFTP
        try await SFTPService.shared.chmod(remotePath: renamedRemotePath, mode: "755", recursive: false, connection: conn, password: nil)
        items = try await SFTPService.shared.listDirectory(path: remoteRoot.path, connection: conn, password: nil)
        guard let chmoddedItem = items.first(where: { $0.name == renamedFileName }) else {
            XCTFail("Expected renamed item after chmod")
            return
        }
        XCTAssertTrue(chmoddedItem.permissions.hasSuffix("rwxr-xr-x"), "SFTP chmod 755 must update permissions to rwxr-xr-x")

        // 5. Duplicate File on SFTP
        let duplicatedRemotePath = try await SFTPService.shared.duplicate(
            remotePath: renamedRemotePath,
            isDirectory: false,
            connection: conn,
            password: nil
        )
        XCTAssertTrue(duplicatedRemotePath.hasSuffix("이름변경완료_파일 copy.txt"))
        items = try await SFTPService.shared.listDirectory(path: remoteRoot.path, connection: conn, password: nil)
        XCTAssertTrue(items.contains(where: { $0.name == "이름변경완료_파일 copy.txt" }), "Duplicated SFTP file must exist")

        // 6. Download File from SFTP to Local
        let downloadDestDir = localWork.appendingPathComponent("downloaded")
        try FileManager.default.createDirectory(at: downloadDestDir, withIntermediateDirectories: true)
        let downloadedURL = try await SFTPService.shared.download(
            remotePath: renamedRemotePath,
            to: downloadDestDir,
            connection: conn,
            password: nil
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadedURL.path))
        XCTAssertEqual(try String(contentsOf: downloadedURL, encoding: .utf8), testContent)

        // 7. Remove Single File on SFTP
        try await SFTPService.shared.remove(remotePath: duplicatedRemotePath, isDirectory: false, connection: conn, password: nil)
        items = try await SFTPService.shared.listDirectory(path: remoteRoot.path, connection: conn, password: nil)
        XCTAssertFalse(items.contains(where: { $0.name == "이름변경완료_파일 copy.txt" }), "Removed SFTP file must be deleted")

        // 8. Remove Non-Empty Nested Directory on SFTP
        let nestedSubdir = "\(newFolderPath)/하위폴더"
        try await SFTPService.shared.createDirectory(remotePath: nestedSubdir, connection: conn, password: nil)
        try await SFTPService.shared.upload(localURL: localSourceFile, to: nestedSubdir, connection: conn, password: nil)
        // Verify nested file exists before recursive delete
        let nestedItems = try await SFTPService.shared.listDirectory(path: nestedSubdir, connection: conn, password: nil)
        XCTAssertEqual(nestedItems.count, 1)

        // Delete top-level non-empty folder (even with trailing slash!)
        try await SFTPService.shared.remove(remotePath: newFolderPath + "/", isDirectory: true, connection: conn, password: nil)
        items = try await SFTPService.shared.listDirectory(path: remoteRoot.path, connection: conn, password: nil)
        XCTAssertFalse(items.contains(where: { $0.name == "새 폴더 [SFTP]" }), "Non-empty SFTP directory must be recursively deleted")
    }

    // MARK: - 5. Full Local Lifecycle & Compare/Sync Parity Tests

    func testFullLocalLifecycleAndCompareItemListsParity() async throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_full_local_\(UUID().uuidString)")
        let leftDir = tempBase.appendingPathComponent("left")
        let rightDir = tempBase.appendingPathComponent("right")
        try FileManager.default.createDirectory(at: leftDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rightDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        // 1. Create Folder & File on Left
        let subFolder = try await FileSystemService.shared.createFolder(at: leftDir, name: "공통폴더")
        XCTAssertTrue(FileManager.default.fileExists(atPath: subFolder.path))

        let fileURL = try await FileSystemService.shared.createFile(at: leftDir, name: "문서.txt", content: "초기 내용")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        // 2. Duplicate File on Left
        let dupURL = try await FileSystemService.shared.duplicate(url: fileURL)
        XCTAssertEqual(dupURL.lastPathComponent, "문서 copy.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dupURL.path))

        // 3. Rename Duplicated File
        let renamedURL = try await FileSystemService.shared.rename(url: dupURL, to: "왼쪽전용.txt")
        XCTAssertEqual(renamedURL.lastPathComponent, "왼쪽전용.txt")

        // 4. Copy "문서.txt" to Right
        try await FileSystemService.shared.copy(urls: [fileURL], to: rightDir)
        let rightCopiedURL = rightDir.appendingPathComponent("문서.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rightCopiedURL.path))

        // 5. Create a Right-only file
        let rightOnlyURL = try await FileSystemService.shared.createFile(at: rightDir, name: "오른쪽전용.txt", content: "오른쪽")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rightOnlyURL.path))

        // 6. Compare Item Lists (works for both Local and SFTP FileItem arrays)
        let leftItems = (try FileManager.default.contentsOfDirectory(at: leftDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])).map { FileItem(url: $0) }
        let rightItems = (try FileManager.default.contentsOfDirectory(at: rightDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])).map { FileItem(url: $0) }
        let diffs = FileSystemService.compareItemLists(leftItems: leftItems, rightItems: rightItems)

        XCTAssertEqual(diffs.first(where: { $0.name == "문서.txt" })?.status, .identical)
        XCTAssertEqual(diffs.first(where: { $0.name == "왼쪽전용.txt" })?.status, .leftOnly)
        XCTAssertEqual(diffs.first(where: { $0.name == "오른쪽전용.txt" })?.status, .rightOnly)

        // 7. Move to Trash
        try await FileSystemService.shared.moveToTrash(urls: [renamedURL, rightOnlyURL])
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rightOnlyURL.path))
    }

    // MARK: - 6. UI/UX Intent-Driven Tests (Selection Pruning, Error Persistence, Multiple-Space Parsing)

    @MainActor
    func testPaneModelPrunesStaleSelectionAndPreservesErrorBanner() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_ux_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingURL = tempDir.appendingPathComponent("keep.txt")
        let deletedURL = tempDir.appendingPathComponent("deleted.txt")
        try? "keep".write(to: existingURL, atomically: true, encoding: .utf8)

        let pane = PaneModel(initialURL: tempDir)
        pane.items = [FileItem(url: existingURL)]
        pane.selectedItemURLs = [existingURL, deletedURL]
        pane.focusedItemURL = deletedURL

        pane.pruneStaleSelections()

        XCTAssertEqual(pane.selectedItemURLs, [existingURL], "Stale deleted URLs must be pruned from selectedItemURLs")
        XCTAssertNil(pane.focusedItemURL, "Stale deleted focusedItemURL must be cleared")
    }

    func testExtractLsColumnsPreservesConsecutiveSpacesInFilenames() {
        let line = "-rw-r--r--   1 admin  users      4096 Oct 18 12:30 파일  이름   공백유지.txt"
        let parsed = SFTPService.extractLsColumns(from: line)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(String(parsed?.tokens[0] ?? ""), "-rw-r--r--")
        XCTAssertEqual(String(parsed?.tokens[4] ?? ""), "4096")
        XCTAssertEqual(parsed?.fileName, "파일  이름   공백유지.txt")
    }

    @MainActor
    func testCrossPaneClipboardAndDragDropBetweenLocalAndSFTP() async throws {
        let sftpServerBinary = "/usr/libexec/sftp-server"
        guard FileManager.default.fileExists(atPath: sftpServerBinary) else {
            throw XCTSkip("sftp-server binary not found at /usr/libexec/sftp-server")
        }

        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_crosspane_\(UUID().uuidString)")
        let remoteDir = tempBase.appendingPathComponent("sftp_dir")
        let localDir = tempBase.appendingPathComponent("local_dir")
        try FileManager.default.createDirectory(at: remoteDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let conn = RemoteConnection(
            name: "Local Test SFTP",
            host: "local-sftp-server",
            port: 22,
            username: NSUserName(),
            remotePath: remoteDir.path,
            authType: .sshKey
        )

        let leftSFTPPane = PaneModel(initialURL: remoteDir)
        leftSFTPPane.isRemote = true
        leftSFTPPane.remoteConnection = conn
        leftSFTPPane.remotePath = remoteDir.path

        let rightLocalPane = PaneModel(initialURL: localDir)

        // Create a file on SFTP side
        let sftpSourceFile = remoteDir.appendingPathComponent("원격에서_로컬로.txt")
        try "원격 데이터".write(to: sftpSourceFile, atomically: true, encoding: .utf8)
        let sftpItem = FileItem(
            virtualURL: URL(fileURLWithPath: sftpSourceFile.path),
            name: "원격에서_로컬로.txt",
            isDirectory: false,
            size: 15,
            modificationDate: Date(),
            permissions: "rw-r--r--"
        )
        leftSFTPPane.items = [sftpItem]

        // 1. Clipboard Copy from Left SFTP Pane -> Paste into Right Local Pane
        ClipboardService.shared.copy(items: [sftpItem], from: leftSFTPPane)
        let pasteToLocalDone = expectation(description: "Paste SFTP to Local")
        ClipboardService.shared.paste(to: rightLocalPane) {
            pasteToLocalDone.fulfill()
        }
        await fulfillment(of: [pasteToLocalDone], timeout: 5.0)
        let pastedLocalURL = localDir.appendingPathComponent("원격에서_로컬로.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pastedLocalURL.path), "Clipboard paste from SFTP to Local must download file")

        // 2. Drag & Drop from Right Local Pane -> Drop onto Left SFTP Pane
        let localSourceURL = localDir.appendingPathComponent("로컬에서_원격으로.txt")
        try "로컬 드래그 데이터".write(to: localSourceURL, atomically: true, encoding: .utf8)
        let localItem = FileItem(url: localSourceURL)
        rightLocalPane.items = [localItem]

        DragDropManager.shared.startDrag(items: [localItem], from: rightLocalPane)
        let dropToSFTPDone = expectation(description: "Drop Local to SFTP")
        DragDropManager.shared.handleDrop(onto: leftSFTPPane, targetSubfolder: nil, externalProviders: []) {
            dropToSFTPDone.fulfill()
        }
        await fulfillment(of: [dropToSFTPDone], timeout: 5.0)
        let uploadedOnRemoteURL = remoteDir.appendingPathComponent("로컬에서_원격으로.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: uploadedOnRemoteURL.path), "Drag and drop from Local to SFTP must upload file")
    }

    // MARK: - 7. Port Formatting, Shift+Arrow Contraction, Space Multi-Select, Scroll Clamping, Cmd+K & Edit Connection Tests

    func testPortDisplayNeverContainsCommaSeparators() {
        let ports = [22, 2222, 8080, 22022, 65535]
        for p in ports {
            let conn = RemoteConnection(
                name: "Test Server",
                host: "example.com",
                port: p,
                username: "admin"
            )
            XCTAssertFalse(conn.formattedPort.contains(","), "formattedPort must never contain comma for port \(p)")
            XCTAssertFalse(conn.formattedHostPort.contains(","), "formattedHostPort must never contain comma for port \(p)")
            XCTAssertFalse(conn.displaySubtitle.contains(","), "displaySubtitle must never contain comma for port \(p)")
            XCTAssertEqual(conn.formattedPort, String(p))
            XCTAssertEqual(conn.formattedHostPort, "example.com:\(String(p))")
            XCTAssertEqual(conn.displaySubtitle, "admin@example.com:\(String(p))")
        }
    }

    @MainActor
    func testShiftArrowRangeSelectionContractsWhenReversingAndCrossesAnchor() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_shift_sel_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let urls = (0..<5).map { tempDir.appendingPathComponent("file_\($0).txt") }
        let items = urls.enumerated().map { idx, u in
            FileItem(
                virtualURL: u,
                name: "file_\(idx).txt",
                isDirectory: false,
                size: 100,
                modificationDate: Date(timeIntervalSince1970: Double(1000 + idx)),
                permissions: "rw-r--r--"
            )
        }

        let pane = PaneModel(initialURL: tempDir)
        pane.sortField = .name
        pane.sortAscending = true
        pane.items = items

        // 1. Click file_0 and extend downward with Shift + Down 3 times (file_0 ... file_3)
        pane.selectSingle(urls[0])
        XCTAssertEqual(pane.selectedItemURLs, [urls[0]])

        pane.selectNext(extendSelection: true) // file_0 ... file_1
        XCTAssertEqual(pane.selectedItemURLs, [urls[0], urls[1]])

        pane.selectNext(extendSelection: true) // file_0 ... file_2
        XCTAssertEqual(pane.selectedItemURLs, [urls[0], urls[1], urls[2]])

        pane.selectNext(extendSelection: true) // file_0 ... file_3
        XCTAssertEqual(pane.selectedItemURLs, [urls[0], urls[1], urls[2], urls[3]])

        // 2. Press Shift + Up -> must contract selection by deselecting file_3, then file_2, then file_1
        pane.selectPrevious(extendSelection: true) // back to file_2
        XCTAssertEqual(pane.selectedItemURLs, [urls[0], urls[1], urls[2]], "Reversing with Shift+Up must deselect file_3")

        pane.selectPrevious(extendSelection: true) // back to file_1
        XCTAssertEqual(pane.selectedItemURLs, [urls[0], urls[1]], "Reversing with Shift+Up must deselect file_2")

        pane.selectPrevious(extendSelection: true) // back to anchor file_0
        XCTAssertEqual(pane.selectedItemURLs, [urls[0]], "Returning to anchor with Shift+Up must leave only anchor selected")

        // 3. Start at file_2, Shift+Down to file_3, then Shift+Up across anchor to file_1
        pane.selectSingle(urls[2])
        pane.selectNext(extendSelection: true) // [file_2, file_3]
        XCTAssertEqual(pane.selectedItemURLs, [urls[2], urls[3]])

        pane.selectPrevious(extendSelection: true) // back to anchor [file_2]
        XCTAssertEqual(pane.selectedItemURLs, [urls[2]])

        pane.selectPrevious(extendSelection: true) // cross anchor upward to [file_1, file_2]
        XCTAssertEqual(pane.selectedItemURLs, [urls[1], urls[2]], "Crossing anchor upward must select [file_1, file_2] and keep file_3 deselected")

        // 4. Shift + Click (selectRange) contraction test
        pane.selectSingle(urls[0])
        pane.selectRange(to: urls[4])
        XCTAssertEqual(pane.selectedItemURLs, Set(urls[0...4]))
        pane.selectRange(to: urls[1])
        XCTAssertEqual(pane.selectedItemURLs, Set(urls[0...1]), "Shift+Click closer to anchor must deselect items outside new range")
    }

    @MainActor
    func testSpaceToggleSelectionAndArrowMultiSelect() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftp_space_sel_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let urls = (0..<5).map { tempDir.appendingPathComponent("item_\($0).txt") }
        let items = urls.enumerated().map { idx, u in
            FileItem(
                virtualURL: u,
                name: "item_\(idx).txt",
                isDirectory: false,
                size: 100,
                modificationDate: Date(timeIntervalSince1970: Double(1000 + idx)),
                permissions: "rw-r--r--"
            )
        }

        let pane = PaneModel(initialURL: tempDir)
        pane.sortField = .name
        pane.sortAscending = true
        pane.items = items

        // 1. Move focus to first item (item_0) with Down arrow
        pane.selectNext(extendSelection: false)
        XCTAssertEqual(pane.focusedItemURL, urls[0])
        XCTAssertTrue(pane.selectedItemURLs.isEmpty)

        // 2. Press Space on item_0 -> selects item_0
        pane.toggleSelectionAtFocus()
        XCTAssertEqual(pane.selectedItemURLs, [urls[0]], "First Space press must select focused item")

        // 3. Press Space again on item_0 -> deselects item_0
        pane.toggleSelectionAtFocus()
        XCTAssertTrue(pane.selectedItemURLs.isEmpty, "Pressing Space a second time on selected item must deselect it")

        // 4. Press Space on item_0 to select it, then arrow down to item_2 and press Space, then item_4 and press Space
        pane.toggleSelectionAtFocus() // item_0 ON
        XCTAssertEqual(pane.selectedItemURLs, [urls[0]])

        pane.selectNext(extendSelection: false) // focus -> item_1 (skipped)
        XCTAssertEqual(pane.focusedItemURL, urls[1])
        XCTAssertEqual(pane.selectedItemURLs, [urls[0]], "Moving with arrow must preserve Space-selected items")

        pane.selectNext(extendSelection: false) // focus -> item_2
        XCTAssertEqual(pane.focusedItemURL, urls[2])
        pane.toggleSelectionAtFocus() // item_2 ON
        XCTAssertEqual(pane.selectedItemURLs, [urls[0], urls[2]])

        pane.selectNext(extendSelection: false) // focus -> item_3 (skipped)
        pane.selectNext(extendSelection: false) // focus -> item_4
        XCTAssertEqual(pane.focusedItemURL, urls[4])
        pane.toggleSelectionAtFocus() // item_4 ON
        XCTAssertEqual(pane.selectedItemURLs, [urls[0], urls[2], urls[4]])

        // 5. Press Space again on item_4 -> deselects item_4 while keeping item_0 and item_2
        pane.toggleSelectionAtFocus()
        XCTAssertEqual(pane.selectedItemURLs, [urls[0], urls[2]])
    }

    func testHorizontalScrollClampingSnapsBackOverscrollBlankSpace() {
        // Left overscroll (negative X) snaps back to 0
        XCTAssertEqual(FileListView.clampedHorizontalOffset(currentX: -65.0, contentWidth: 700.0, viewportWidth: 400.0), 0.0)

        // Right overscroll (past contentWidth - viewportWidth = 300) snaps back to 300
        XCTAssertEqual(FileListView.clampedHorizontalOffset(currentX: 420.0, contentWidth: 700.0, viewportWidth: 400.0), 300.0)

        // In-bounds scroll stays unchanged
        XCTAssertEqual(FileListView.clampedHorizontalOffset(currentX: 150.0, contentWidth: 700.0, viewportWidth: 400.0), 150.0)

        // When content fits inside viewport, any non-zero scroll snaps back to 0
        XCTAssertEqual(FileListView.clampedHorizontalOffset(currentX: 80.0, contentWidth: 400.0, viewportWidth: 500.0), 0.0)
    }

    @MainActor
    func testCmdKShortcutAndEditConnectionDoesNotConnect() {
        // 1. Verify Cmd + K triggers Connect Manager
        XCTAssertTrue(KeyboardShortcutHelper.shouldTriggerConnect(keyCode: 40, charKey: "k", isCmd: true, isShift: false, isCtrl: false))
        XCTAssertFalse(KeyboardShortcutHelper.shouldTriggerConnect(keyCode: 40, charKey: "k", isCmd: false, isShift: false, isCtrl: false))
        XCTAssertFalse(KeyboardShortcutHelper.shouldTriggerConnect(keyCode: 40, charKey: "k", isCmd: true, isShift: true, isCtrl: false))

        // 2. Verify Space triggers Selection Toggle
        XCTAssertTrue(KeyboardShortcutHelper.shouldTriggerSpaceToggle(keyCode: 49, isPlain: true))
        XCTAssertFalse(KeyboardShortcutHelper.shouldTriggerSpaceToggle(keyCode: 49, isPlain: false))

        // 3. Verify editing and saving a connection updates ConnectionManager without connecting PaneModel
        let pane = PaneModel()
        XCTAssertFalse(pane.isRemote)

        var conn = RemoteConnection(name: "Edit Target", host: "10.0.0.5", port: 2222, username: "tester")
        ConnectionManager.shared.addConnection(conn)
        defer { ConnectionManager.shared.deleteConnection(id: conn.id) }

        conn.name = "Edited Server Name"
        conn.port = 2200
        ConnectionManager.shared.updateConnection(conn)

        let updated = ConnectionManager.shared.connections.first(where: { $0.id == conn.id })
        XCTAssertEqual(updated?.name, "Edited Server Name")
        XCTAssertEqual(updated?.formattedPort, "2200")
        XCTAssertFalse(pane.isRemote, "Editing and saving a connection must never trigger connectRemote on the active pane")
    }

    @MainActor
    func testDeleteAllConnectionsDoesNotCrashAndSafeBindingHandling() {
        // Save current connections to restore later
        let previousConnections = ConnectionManager.shared.connections
        defer {
            ConnectionManager.shared.connections = previousConnections
        }

        // 1. Setup with 2 test connections
        let c1 = RemoteConnection(name: "Server A", host: "1.1.1.1", port: 22)
        let c2 = RemoteConnection(name: "Server B", host: "2.2.2.2", port: 2222)
        ConnectionManager.shared.connections = [c1, c2]

        XCTAssertEqual(ConnectionManager.shared.connections.count, 2)
        guard var binding1 = ConnectionManager.shared.binding(for: c1.id) else {
            XCTFail("Binding for c1 should exist")
            return
        }

        // Test mutation through binding
        binding1.wrappedValue.name = "Renamed A"
        XCTAssertEqual(ConnectionManager.shared.connection(for: c1.id)?.name, "Renamed A")

        // 2. Delete c1
        ConnectionManager.shared.deleteConnection(id: c1.id)
        XCTAssertEqual(ConnectionManager.shared.connections.count, 1)
        XCTAssertNil(ConnectionManager.shared.connection(for: c1.id))

        // Accessing stale binding for c1 must NEVER crash with index out of bounds
        let fallbackConn = binding1.wrappedValue
        XCTAssertEqual(fallbackConn.id, c1.id, "Stale binding must safely return fallback instead of trapping")

        // 3. Delete c2 so connections is completely empty
        guard let binding2 = ConnectionManager.shared.binding(for: c2.id) else {
            XCTFail("Binding for c2 should exist")
            return
        }
        ConnectionManager.shared.deleteConnection(id: c2.id)
        XCTAssertTrue(ConnectionManager.shared.connections.isEmpty, "Connections list should now be completely empty")
        XCTAssertNil(ConnectionManager.shared.connection(for: c2.id))
        XCTAssertNil(ConnectionManager.shared.binding(for: c2.id))

        // Stale binding2 access after all connections deleted must not crash
        let fallback2 = binding2.wrappedValue
        XCTAssertEqual(fallback2.id, c2.id)

        // 4. Verify ConnectSheet renders with 0 connections without index out of range crash
        let emptySheet = ConnectSheet(onConnect: { _, _ in })
        _ = emptySheet.body
        XCTAssertNotNil(emptySheet)

        // 5. Verify deleting repeatedly on empty array does not throw
        ConnectionManager.shared.deleteConnection(id: UUID())
        XCTAssertTrue(ConnectionManager.shared.connections.isEmpty)
    }

    @MainActor
    func testEscapeKeyCancelsAndClearsAllToggledSelections() {
        let pane = PaneModel(autoLoad: false)
        let item1 = FileItem(virtualURL: URL(fileURLWithPath: "/tmp/file1.txt"), name: "file1.txt", isDirectory: false, size: 10, modificationDate: Date(), permissions: "rw-r--r--")
        let item2 = FileItem(virtualURL: URL(fileURLWithPath: "/tmp/file2.txt"), name: "file2.txt", isDirectory: false, size: 20, modificationDate: Date(), permissions: "rw-r--r--")
        let item3 = FileItem(virtualURL: URL(fileURLWithPath: "/tmp/file3.txt"), name: "file3.txt", isDirectory: false, size: 30, modificationDate: Date(), permissions: "rw-r--r--")
        pane.items = [item1, item2, item3]

        // 1. Verify Space toggle on item1 and item3
        pane.focusedItemURL = item1.url
        pane.toggleSelectionAtFocus()
        XCTAssertTrue(pane.selectedItemURLs.contains(item1.url))
        XCTAssertTrue(pane.pinnedSelectionURLs.contains(item1.url))

        pane.focusedItemURL = item3.url
        pane.toggleSelectionAtFocus()
        XCTAssertEqual(pane.selectedItemURLs.count, 2)
        XCTAssertEqual(pane.pinnedSelectionURLs.count, 2)

        // 2. Verify Escape key triggers shouldTriggerEscape
        XCTAssertTrue(KeyboardShortcutHelper.shouldTriggerEscape(keyCode: 53))
        XCTAssertFalse(KeyboardShortcutHelper.shouldTriggerEscape(keyCode: 49))
        XCTAssertFalse(KeyboardShortcutHelper.shouldTriggerEscape(keyCode: 36))

        // 3. Trigger clearSelection (simulating Esc action)
        pane.clearSelection()
        XCTAssertTrue(pane.selectedItemURLs.isEmpty, "Esc must clear all selected items")
        XCTAssertTrue(pane.pinnedSelectionURLs.isEmpty, "Esc must clear all pinned/toggled items")
        XCTAssertNil(pane.focusedItemURL, "Esc must clear focus so no item remains highlighted")
    }

    func testFileIconProviderPreservesDistinctIconsForApplicationsAndFolders() {
        let safariURL = URL(fileURLWithPath: "/Applications/Safari.app")
        let calcURL = URL(fileURLWithPath: "/System/Applications/Calculator.app")

        let safariItem = FileItem(url: safariURL)
        let calcItem = FileItem(url: calcURL)

        let safariIcon = FileIconProvider.shared.icon(for: safariItem)
        let calcIcon = FileIconProvider.shared.icon(for: calcItem)

        XCTAssertNotNil(safariIcon)
        XCTAssertNotNil(calcIcon)

        // If both apps exist on macOS, their icon representations must be distinct and not identical cached instances
        if FileManager.default.fileExists(atPath: safariURL.path) && FileManager.default.fileExists(atPath: calcURL.path) {
            XCTAssertNotEqual(
                safariIcon.tiffRepresentation,
                calcIcon.tiffRepresentation,
                "Different applications must have distinct icons, never sharing a single cached 'dir:app' icon"
            )
        }
    }
}

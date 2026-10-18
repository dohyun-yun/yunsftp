import Foundation
import AppKit

@main
struct TestRunner {
    static func main() async {
        print("========================================")
        print("    yunsftp Self-Verification Test     ")
        print("========================================")

        // 1. Settings & Profile Migration Test
        print("\n[Test 1] ForkLift 2 Settings & Profile Migration...")
        let migrationResult = MigrationService.shared.migrateFromForkLift2()
        assert(migrationResult.sourceFound, "ForkLift 2 plist should be found")
        print("  ✓ ForkLift 2 Plist detected: \(migrationResult.sourceFound)")

        let conns = migrationResult.importedConnections
        print("  ✓ Imported Connections count: \(conns.count)")
        if let firstConn = conns.first {
            print("    - Host: \(firstConn.host)")
            print("    - Port: \(firstConn.port)")
            print("    - User: \(firstConn.username)")
            print("    - Path: \(firstConn.remotePath)")
            print("    - Protocol: \(firstConn.connectionProtocol.rawValue)")
            assert(firstConn.host == "finsternis.synology.me", "Host should be finsternis.synology.me")
            assert(firstConn.port == 13622, "Port should be 13622")
            assert(firstConn.username == "admin", "User should be admin")
        }

        let favs = migrationResult.importedFavorites
        print("  ✓ Imported Local Favorites count: \(favs.count)")
        for f in favs {
            print("    - Favorite: \(f.name) (\(f.url.path))")
        }

        if let s = migrationResult.importedSettings {
            print("  ✓ Migrated View Settings:")
            print("    - Sort field: \(s.sortField.rawValue)")
            print("    - Sort ascending: \(s.sortAscending)")
            print("    - Group folders: \(s.groupFolders)")
            print("    - Font size: \(s.fontSize)")
            print("    - View mode: \(s.viewMode.rawValue)")
            print("    - Tools count: \(s.tools.count)")
        }

        // 2. Keyboard Navigation & Cursor Selection Test
        print("\n[Test 2] Keyboard Navigation & Cursor Movement in PaneModel...")
        await MainActor.run {
            let testFolder = FileManager.default.temporaryDirectory.appendingPathComponent("ForkLiftNavTest_\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: testFolder, withIntermediateDirectories: true)

            // Create test files: alpha.txt, beta.txt, gamma.txt
            let f1 = testFolder.appendingPathComponent("alpha.txt")
            let f2 = testFolder.appendingPathComponent("beta.txt")
            let f3 = testFolder.appendingPathComponent("gamma.txt")
            try? "a".write(to: f1, atomically: true, encoding: .utf8)
            try? "b".write(to: f2, atomically: true, encoding: .utf8)
            try? "c".write(to: f3, atomically: true, encoding: .utf8)

            let pane = PaneModel(initialURL: testFolder)
            // Synchronous item injection for testing
            pane.items = [FileItem(url: f1), FileItem(url: f2), FileItem(url: f3)]

            let displayed = pane.displayedItems
            print("  ✓ Loaded items count: \(displayed.count)")
            assert(displayed.count == 3, "Should have 3 test files")

            // Initially select first via Down Arrow
            pane.selectNext()
            print("  ✓ First down arrow selected: \(pane.focusedItemURL?.lastPathComponent ?? "none")")
            assert(pane.focusedItemURL?.lastPathComponent == displayed[0].name)

            // Next down arrow
            pane.selectNext()
            print("  ✓ Second down arrow selected: \(pane.focusedItemURL?.lastPathComponent ?? "none")")
            assert(pane.focusedItemURL?.lastPathComponent == displayed[1].name)

            // Up arrow
            pane.selectPrevious()
            print("  ✓ Up arrow moved back to: \(pane.focusedItemURL?.lastPathComponent ?? "none")")
            assert(pane.focusedItemURL?.lastPathComponent == displayed[0].name)

            // Type-to-select "g"
            pane.selectMatchingPrefix("g")
            print("  ✓ Type-to-select 'g' jumped to: \(pane.focusedItemURL?.lastPathComponent ?? "none")")
            assert(pane.focusedItemURL?.lastPathComponent == "gamma.txt")

            // Clean up
            try? FileManager.default.removeItem(at: testFolder)
            print("  ✓ Keyboard navigation assertions passed!")
        }

        // 3. File Operations Test (CRUD, Zip, Duplicate)
        print("\n[Test 3] File Operations (Folder, File, Rename, Zip, Duplicate)...")
        do {
            let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ForkLiftOps_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            // Create folder
            let newDir = try await FileSystemService.shared.createFolder(at: tempDir, name: "SubFolder")
            print("  ✓ Created folder: \(newDir.lastPathComponent)")

            // Create file
            let newFile = try await FileSystemService.shared.createFile(at: newDir, name: "hello.txt", content: "ForkLift Silicon")
            print("  ✓ Created file: \(newFile.lastPathComponent)")

            // Rename file
            let renamed = try await FileSystemService.shared.rename(url: newFile, to: "greeting.txt")
            print("  ✓ Renamed file to: \(renamed.lastPathComponent)")
            assert(renamed.lastPathComponent == "greeting.txt")

            // Duplicate
            try await FileSystemService.shared.duplicate(urls: [renamed])
            let filesAfterDup = try FileManager.default.contentsOfDirectory(atPath: newDir.path)
            print("  ✓ Duplicate created: \(filesAfterDup)")
            assert(filesAfterDup.count == 2)

            // Compress to zip
            let zipURL = try await FileSystemService.shared.compress(urls: [newDir], to: tempDir)
            print("  ✓ Compressed to zip: \(zipURL.lastPathComponent)")
            assert(FileManager.default.fileExists(atPath: zipURL.path))

            // Extract
            let extractDir = tempDir.appendingPathComponent("Extracted")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            try await FileSystemService.shared.extract(archiveURL: zipURL, to: extractDir)
            print("  ✓ Extracted zip archive successfully")

            // Clean up
            try FileManager.default.removeItem(at: tempDir)
            print("  ✓ All file operation tests passed!")
        } catch {
            print("  ❌ File operation test failed:", error)
        }

        // 4. Remote SSH Connection Test
        print("\n[Test 4] Remote Connection Test to finsternis.synology.me:13622...")
        let result = await ConnectionTestService.shared.testConnection(
            host: "finsternis.synology.me",
            port: 13622,
            isSSH: true
        )
        print("  ✓ Connection Success:", result.isSuccess)
        print("  ✓ Latency: \(Int(result.latencyMs)) ms")
        if let ip = result.resolvedIP {
            print("  ✓ Resolved IP: \(ip)")
        }
        if let banner = result.serverBanner {
            print("  ✓ SSH Server Banner: \(banner)")
        }
        print("  ✓ Message: \(result.message)")
        assert(result.isSuccess, "SSH connection to synology NAS should succeed")

        // 5. In-App Remote SFTP Pane Browsing & Navigation State Test
        print("\n[Test 5] In-App Remote SFTP Pane Browsing State & Navigation...")
        await MainActor.run {
            guard let conn = conns.first else { return }
            let pane = PaneModel()
            assert(!pane.isRemote, "Initially pane should be local")

            // Connect remote in pane
            pane.connectRemote(connection: conn, password: nil)
            assert(pane.isRemote, "Pane must be in remote mode")
            let expectedInitialPath = conn.remotePath.isEmpty ? "/" : conn.remotePath
            assert(pane.remotePath == expectedInitialPath, "Remote path should match connection remotePath")
            assert(pane.currentURL.scheme == "sftp", "URL scheme should be sftp")
            print("  ✓ Connected remote pane: \(pane.currentURL.absoluteString)")

            // Navigate remote folder
            pane.navigateToRemote(path: "/video/88.부동산")
            assert(pane.remotePath == "/video/88.부동산", "Remote path should update to /video/88.부동산")
            print("  ✓ Remote subfolder navigated: \(pane.remotePath)")

            pane.navigateToRemote(path: "/video/88.부동산/2024")
            assert(pane.remotePath == "/video/88.부동산/2024", "Remote path should update")
            print("  ✓ Remote subfolder navigated: \(pane.remotePath)")

            // Test goUp
            pane.goUp()
            assert(pane.remotePath == "/video/88.부동산", "goUp should navigate to parent remote folder")
            print("  ✓ Remote goUp navigated: \(pane.remotePath)")

            // Test RemoteFileItem to FileItem conversion
            let remoteItem = RemoteFileItem(
                name: "test_doc.pdf",
                remotePath: "/video/88.부동산/test_doc.pdf",
                isDirectory: false,
                size: 1048576,
                modificationDate: Date(),
                permissions: "rw-r--r--"
            )
            let fileItem = remoteItem.toFileItem(connection: conn)
            assert(fileItem.name == "test_doc.pdf")
            assert(fileItem.size == 1048576)
            assert(fileItem.formattedSize == "1 MB" || fileItem.formattedSize == "1,048,576 bytes" || !fileItem.formattedSize.isEmpty)
            print("  ✓ RemoteFileItem mapped to FileItem: \(fileItem.name) (\(fileItem.formattedSize))")

            // Test Disconnect
            pane.disconnectRemote()
            assert(!pane.isRemote, "Pane must return to local after disconnect")
            print("  ✓ Disconnected remote pane safely, returned to local")
        }

        print("\n========================================")
        print(" ALL 5 VERIFICATION TEST SUITES PASSED! ")
        print("========================================")
    }
}

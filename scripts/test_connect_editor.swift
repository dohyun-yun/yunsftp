import Foundation
import AppKit

@main
struct ConnectEditorTest {
    static func main() async {
        print("========================================")
        print(" ConnectSheet & Editor Verification Test")
        print("========================================")

        await MainActor.run {
            let manager = ConnectionManager.shared

            // 1. Initial State Check
            print("\n[Test 1] Verify ConnectionManager connections...")
            assert(!manager.connections.isEmpty, "Should have at least 1 migrated connection")
            let initialCount = manager.connections.count
            print("  ✓ Current connections count: \(initialCount)")
            let firstConn = manager.connections[0]
            print("  ✓ Selected connection: \(firstConn.name) (\(firstConn.host):\(firstConn.port))")

            // 2. Direct In-Place Edit (Reactive Binding Simulation)
            print("\n[Test 2] Test editing connection fields directly...")
            let oldName = manager.connections[0].name
            let testName = "Synology NAS - Edited Test"
            manager.connections[0].name = testName
            manager.connections[0].port = 13622
            manager.connections[0].remotePath = "/video/88.부동산"

            // Verify in-memory mutation
            assert(manager.connections[0].name == testName, "Name must be updated")
            assert(manager.connections[0].port == 13622, "Port must be 13622")
            assert(manager.connections[0].remotePath == "/video/88.부동산", "Path must be /video/88.부동산")
            print("  ✓ In-place mutation succeeded: \(manager.connections[0].name)")

            // Verify persistence via UserDefaults
            let reloadedManager = ConnectionManager()
            assert(reloadedManager.connections[0].name == testName, "Persistence via UserDefaults failed")
            print("  ✓ Persistence verification passed (auto-saved to storage)")

            // Restore original name
            manager.connections[0].name = oldName
            print("  ✓ Restored name to: \(manager.connections[0].name)")

            // 3. Test Add New Connection Button Logic
            print("\n[Test 3] Test 'Create New Connection' button logic...")
            let newConn = RemoteConnection(name: "Test Server", connectionProtocol: .sftp, host: "test.local", port: 2222)
            manager.addConnection(newConn)
            assert(manager.connections.count == initialCount + 1, "Connection count should increase by 1")
            let added = manager.connections.last!
            assert(added.name == "Test Server" && added.port == 2222)
            print("  ✓ New connection created successfully: \(added.name)")

            // 4. Test Duplicate Button Logic
            print("\n[Test 4] Test 'Duplicate' button logic...")
            manager.duplicateConnection(added)
            assert(manager.connections.count == initialCount + 2, "Connection count should increase by 2")
            let duplicated = manager.connections.last!
            assert(duplicated.name == "Test Server Copy")
            print("  ✓ Duplicate created successfully: \(duplicated.name)")

            // 5. Test Delete Button Logic
            print("\n[Test 5] Test 'Delete Connection' button logic...")
            manager.deleteConnection(id: duplicated.id)
            manager.deleteConnection(id: added.id)
            assert(manager.connections.count == initialCount, "Count should return to initialCount")
            print("  ✓ Cleanup delete succeeded, connection count restored to \(initialCount)")
        }

        // 6. Test 'Test Connection' Socket Engine on finsternis.synology.me
        print("\n[Test 6] Test 'Test Connection' button engine...")
        let manager = await ConnectionManager.shared
        let conn = await manager.connections[0]
        let result = await manager.testConnection(conn)
        print("  ✓ Test Connection Result: Success=\(result.isSuccess), Latency=\(Int(result.latencyMs))ms")
        if let banner = result.serverBanner {
            print("  ✓ Server Banner: \(banner)")
        }
        assert(result.isSuccess, "Test connection to Synology NAS should succeed")

        print("\n========================================")
        print(" ALL EDITOR & BUTTON TESTS PASSED (100%)")
        print("========================================")
    }
}

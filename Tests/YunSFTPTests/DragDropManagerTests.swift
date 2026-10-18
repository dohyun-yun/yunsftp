import XCTest
@testable import yunsftp

@MainActor
final class DragDropManagerTests: XCTestCase {
    var manager: DragDropManager!

    override func setUp() async throws {
        try await super.setUp()
        manager = DragDropManager.shared
        manager.endDrag()
    }

    override func tearDown() async throws {
        manager.endDrag()
        try await super.tearDown()
    }

    func testStartAndEndDrag() {
        let dummyURL = URL(fileURLWithPath: "/Users/test/Documents/photo.png")
        let item = FileItem(virtualURL: dummyURL, name: "photo.png", isDirectory: false, size: 5000, modificationDate: Date(), permissions: "rw-r--r--")
        let pane = PaneModel(initialURL: FileManager.default.temporaryDirectory)

        manager.startDrag(items: [item], from: pane)

        XCTAssertEqual(manager.draggedItems.count, 1)
        XCTAssertEqual(manager.draggedItems.first?.name, "photo.png")
        XCTAssertEqual(manager.sourcePaneId, pane.id)
        XCTAssertFalse(manager.sourceIsRemote)

        manager.endDrag()

        XCTAssertEqual(manager.draggedItems.count, 0)
        XCTAssertNil(manager.sourcePaneId)
    }

    func testRemoteDragSourceTracking() {
        let dummyURL = URL(string: "sftp://nas.local:22/volume1/data.bin")!
        let item = FileItem(virtualURL: dummyURL, name: "data.bin", isDirectory: false, size: 8192, modificationDate: Date(), permissions: "rwxr-xr-x")
        let conn = RemoteConnection(name: "My NAS", host: "nas.local", port: 22, username: "user", authType: .password)
        let remotePane = PaneModel()
        remotePane.isRemote = true
        remotePane.remoteConnection = conn

        manager.startDrag(items: [item], from: remotePane)

        XCTAssertEqual(manager.draggedItems.count, 1)
        XCTAssertTrue(manager.sourceIsRemote)
        XCTAssertEqual(manager.sourceConnection?.displayTitle, "My NAS")

        manager.endDrag()
    }
}

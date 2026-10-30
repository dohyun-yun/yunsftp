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


extension DragDropManagerTests {
    func testOnlyOurOwnProvidersCarryTheSessionMarker() {
        let ours = DragDropManager.shared.makeProvider(for: URL(fileURLWithPath: "/tmp/a.txt"))
        let finder = NSItemProvider(object: URL(fileURLWithPath: "/tmp/a.txt") as NSURL)
        XCTAssertTrue(DragDropManager.isInternalDrop(providers: [ours]))
        XCTAssertFalse(DragDropManager.isInternalDrop(providers: [finder]), "same URL from Finder is external")
        XCTAssertFalse(DragDropManager.isInternalDrop(providers: []))
        XCTAssertTrue(ours.canLoadObject(ofClass: NSURL.self), "the file URL is still there for Finder")
    }

    @MainActor
    func testInternalDropTransfersTheWholeSelectionAndStaleStateIsDropped() async throws {
        // handleDrop with the marker must hand over all dragged items; without it the cache is cleared.
        let manager = DragDropManager()
        let pane = PaneModel(initialURL: FileManager.default.temporaryDirectory, autoLoad: false)
        let items = ["a", "b", "c"].map { FileItem(url: URL(fileURLWithPath: "/tmp/\($0).txt")) }
        manager.startDrag(items: items, from: pane)
        XCTAssertEqual(manager.draggedItems.count, 3)
        // A Finder drop (no marker) after an abandoned drag: the stale items must not be replayed.
        manager.handleDrop(onto: pane, externalProviders: [NSItemProvider(object: URL(fileURLWithPath: "/tmp/other.txt") as NSURL)]) {}
        XCTAssertTrue(manager.draggedItems.isEmpty)
    }
}

import XCTest
@testable import yunsftp

@MainActor
final class ClipboardServiceTests: XCTestCase {
    var clipboard: ClipboardService!
    var localPane: PaneModel!

    override func setUp() async throws {
        try await super.setUp()
        clipboard = ClipboardService.shared
        clipboard.clear()
        localPane = PaneModel(initialURL: FileManager.default.temporaryDirectory)
    }

    override func tearDown() async throws {
        clipboard.clear()
        try await super.tearDown()
    }

    func testCopyOperation() {
        let dummyURL = URL(fileURLWithPath: "/tmp/sample_test.txt")
        let dummyItem = FileItem(virtualURL: dummyURL, name: "sample_test.txt", isDirectory: false, size: 1024, modificationDate: Date(), permissions: "rw-r--r--")

        clipboard.copy(items: [dummyItem], from: localPane)

        XCTAssertEqual(clipboard.copiedItems.count, 1)
        XCTAssertEqual(clipboard.copiedItems.first?.name, "sample_test.txt")
        XCTAssertFalse(clipboard.isCut)
        XCTAssertFalse(clipboard.sourceIsRemote)
        XCTAssertTrue(clipboard.canPaste)
    }

    func testCutOperation() {
        let dummyURL = URL(fileURLWithPath: "/tmp/cut_test.txt")
        let dummyItem = FileItem(virtualURL: dummyURL, name: "cut_test.txt", isDirectory: false, size: 2048, modificationDate: Date(), permissions: "rw-r--r--")

        clipboard.cut(items: [dummyItem], from: localPane)

        XCTAssertEqual(clipboard.copiedItems.count, 1)
        XCTAssertEqual(clipboard.copiedItems.first?.name, "cut_test.txt")
        XCTAssertTrue(clipboard.isCut)
        XCTAssertFalse(clipboard.sourceIsRemote)
        XCTAssertTrue(clipboard.canPaste)
    }

    func testClearClipboard() {
        let dummyURL = URL(fileURLWithPath: "/tmp/test.txt")
        let dummyItem = FileItem(virtualURL: dummyURL, name: "test.txt", isDirectory: false, size: 512, modificationDate: Date(), permissions: "rw-r--r--")

        clipboard.copy(items: [dummyItem], from: localPane)
        XCTAssertTrue(clipboard.canPaste)

        clipboard.clear()
        XCTAssertEqual(clipboard.copiedItems.count, 0)
        XCTAssertFalse(clipboard.isCut)
        XCTAssertFalse(clipboard.sourceIsRemote)
    }

    func testRemoteSourceTracking() {
        let dummyURL = URL(string: "sftp://192.168.1.100:22/home/user/file.dat")!
        let dummyItem = FileItem(virtualURL: dummyURL, name: "file.dat", isDirectory: false, size: 4096, modificationDate: Date(), permissions: "rwxr-xr-x")

        let conn = RemoteConnection(name: "NAS Server", host: "192.168.1.100", port: 22, username: "admin", authType: .password)
        let remotePane = PaneModel()
        remotePane.isRemote = true
        remotePane.remoteConnection = conn

        clipboard.copy(items: [dummyItem], from: remotePane)

        XCTAssertEqual(clipboard.copiedItems.count, 1)
        XCTAssertTrue(clipboard.sourceIsRemote)
        XCTAssertEqual(clipboard.sourceConnection?.host, "192.168.1.100")
    }
}

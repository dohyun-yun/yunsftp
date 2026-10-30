import XCTest
@testable import yunsftp

@MainActor
final class TransferPaneFlowTests: XCTestCase {
    private func waitUntil(_ timeout: TimeInterval = 10, _ cond: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !cond() && Date() < deadline { try? await Task.sleep(nanoseconds: 50_000_000) }
    }

    func testF5LikeCopyThroughSharedCoordinatorWithRealPanes() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("f5_\(UUID().uuidString)")
        let src = base.appendingPathComponent("src"), dst = base.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try "payload".write(to: src.appendingPathComponent("f.txt"), atomically: true, encoding: .utf8)

        let left = PaneModel(initialURL: src), right = PaneModel(initialURL: dst)
        await waitUntil { !left.isLoading && !left.items.isEmpty }
        left.selectSingle(left.items[0].url)
        let selected = left.effectiveSelectedItems
        XCTAssertEqual(selected.map(\.name), ["f.txt"])

        let source = try XCTUnwrap(TransferLocation.from(pane: left))
        let destination = try XCTUnwrap(TransferLocation.from(pane: right))
        var finished = false
        let batch = TransferCoordinator.shared.start(TransferRequest(items: selected, source: source, destination: destination, mode: .copy)) {
            right.reload(); finished = true
        }
        await TransferCoordinator.shared.wait(for: batch)
        await waitUntil { finished }
        XCTAssertEqual(try String(contentsOf: dst.appendingPathComponent("f.txt"), encoding: .utf8), "payload")
        let row = TransferManager.shared.transfers.last { $0.batchID == batch }
        XCTAssertEqual(row?.state, .completed, "\(String(describing: row))")
    }
}

extension TransferPaneFlowTests {
    func testF5LikeCopyBetweenRemoteAndLocalPanes() async throws {
        guard FileManager.default.fileExists(atPath: "/usr/libexec/sftp-server") else { throw XCTSkip("no sftp-server") }
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("f5r_\(UUID().uuidString)")
        let remote = base.appendingPathComponent("remote"), local = base.appendingPathComponent("local")
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try "down".write(to: remote.appendingPathComponent("r.txt"), atomically: true, encoding: .utf8)
        try "up".write(to: local.appendingPathComponent("l.txt"), atomically: true, encoding: .utf8)

        let conn = RemoteConnection(name: "Local", host: "local-sftp-server", port: 22, username: NSUserName(), remotePath: remote.path, authType: .password)
        let left = PaneModel(initialURL: local, autoLoad: false); left.connectRemote(connection: conn)
        let right = PaneModel(initialURL: local)
        await waitUntil { !left.isLoading && !right.isLoading && !left.items.isEmpty && !right.items.isEmpty }

        // server -> local (F5 with the remote pane active)
        left.selectSingle(left.items[0].url)
        var batch = TransferCoordinator.shared.start(TransferRequest(items: left.effectiveSelectedItems, source: TransferLocation.from(pane: left)!, destination: TransferLocation.from(pane: right)!, mode: .copy)) { right.reload() }
        await TransferCoordinator.shared.wait(for: batch)
        XCTAssertEqual(try String(contentsOf: local.appendingPathComponent("r.txt"), encoding: .utf8), "down")
        XCTAssertEqual(TransferManager.shared.transfers.last { $0.batchID == batch }?.state, .completed)

        // local -> server (F5 with the local pane active)
        await waitUntil { !right.isLoading }
        let lItem = try XCTUnwrap(right.items.first { $0.name == "l.txt" })
        right.selectSingle(lItem.url)
        batch = TransferCoordinator.shared.start(TransferRequest(items: right.effectiveSelectedItems, source: TransferLocation.from(pane: right)!, destination: TransferLocation.from(pane: left)!, mode: .copy)) { left.reload() }
        await TransferCoordinator.shared.wait(for: batch)
        XCTAssertEqual(try String(contentsOf: remote.appendingPathComponent("l.txt"), encoding: .utf8), "up")
        XCTAssertEqual(TransferManager.shared.transfers.last { $0.batchID == batch }?.state, .completed, "\(String(describing: TransferManager.shared.transfers.last))")
    }
}

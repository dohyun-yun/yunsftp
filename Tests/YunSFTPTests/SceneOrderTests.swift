import XCTest

/// The first scene in `App.body` is the one macOS opens at launch. Keep the browser window first.
final class SceneOrderTests: XCTestCase {
    func testMainWindowGroupIsDeclaredBeforeAuxiliaryScenes() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/YunSFTP/App/YunSFTPApp.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        let body = try XCTUnwrap(src.range(of: "var body: some Scene {"))
        let group = try XCTUnwrap(src.range(of: "WindowGroup {", range: body.upperBound..<src.endIndex))
        let settings = try XCTUnwrap(src.range(of: "Settings {", range: body.upperBound..<src.endIndex))
        let transfers = try XCTUnwrap(src.range(of: "Window(\"Transfers\"", range: body.upperBound..<src.endIndex))
        XCTAssertLessThan(group.lowerBound, settings.lowerBound)
        XCTAssertLessThan(group.lowerBound, transfers.lowerBound)
    }
}

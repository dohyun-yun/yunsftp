import XCTest
@testable import yunsftp

final class FileSystemServiceTests: XCTestCase {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fsTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testMoveIntoSelfIsRejectedButSiblingPrefixIsAllowed() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let b = root.appendingPathComponent("b")
        let bc = root.appendingPathComponent("bc")
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bc, withIntermediateDirectories: true)

        XCTAssertTrue(FileSystemService.isSameOrDescendant(b.appendingPathComponent("x"), of: b))
        XCTAssertFalse(FileSystemService.isSameOrDescendant(bc, of: b))

        // /b -> /bc must work (old hasPrefix check wrongly blocked this)
        try await FileSystemService.shared.move(urls: [b], to: bc)
        XCTAssertTrue(FileManager.default.fileExists(atPath: bc.appendingPathComponent("b").path))

        // moving a folder into its own subfolder must fail
        let moved = bc.appendingPathComponent("b")
        do {
            try await FileSystemService.shared.move(urls: [bc], to: moved)
            XCTFail("expected move-into-self to throw")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("itself"))
        }
    }

    func testCompressHandlesNamesStartingWithDash() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let weird = root.appendingPathComponent("-r")
        try "data".write(to: weird, atomically: true, encoding: .utf8)

        let zip = try await FileSystemService.shared.compress(urls: [weird], to: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path))

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        proc.arguments = ["-l", zip.path]
        let out = Pipe()
        proc.standardOutput = out
        try proc.run()
        proc.waitUntilExit()
        let listing = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertTrue(listing.contains("-r"))
    }
}

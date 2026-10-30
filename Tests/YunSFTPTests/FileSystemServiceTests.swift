import XCTest
@testable import yunsftp

final class FileSystemServiceTests: XCTestCase {

    func makeTempDir() throws -> URL {
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

extension FileSystemServiceTests {
    func testPlannedDestinationMatchesWhatCopyProduces() async throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let src = root.appendingPathComponent("src"); let dst = root.appendingPathComponent("dst")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)
        let file = src.appendingPathComponent("r.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        try "old".write(to: dst.appendingPathComponent("r.txt"), atomically: true, encoding: .utf8)

        let planned = FileSystemService.plannedDestinationURL(fileName: "r.txt", in: dst)
        XCTAssertEqual(planned.lastPathComponent, "r 2.txt")
        try await FileSystemService.shared.copy(urls: [file], to: dst)
        XCTAssertTrue(FileManager.default.fileExists(atPath: planned.path))
    }
}

extension FileSystemServiceTests {
    func testPlannedDestinationDetectsCaseInsensitiveCollisions() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try "x".write(to: dir.appendingPathComponent("Report.pdf"), atomically: true, encoding: .utf8)
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("REPORT.PDF").path) else {
            throw XCTSkip("volume is case-sensitive")
        }
        XCTAssertEqual(FileSystemService.plannedDestinationURL(fileName: "report.pdf", in: dir).lastPathComponent, "report 2.pdf")
    }
}

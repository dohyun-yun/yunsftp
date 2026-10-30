import XCTest

/// Guards against third-party namespaces / pre-rename identifiers creeping back into the sources.
final class RepositoryHygieneTests: XCTestCase {
    private var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    func testNoLegacyIdentifiersInSources() throws {
        let banned = ["ForkLiftSilicon", "com.binarynights.ForkLiftSilicon", "com.forklift", "forklift.icns"]
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for token in banned {
                XCTAssertFalse(text.contains(token), "\(url.lastPathComponent) contains \(token)")
            }
        }
    }
}

extension RepositoryHygieneTests {
    /// User-facing strings are English only (localization, if added, goes through String(localized:)).
    func testNoHangulInSources() throws {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil))
        let hangul = try NSRegularExpression(pattern: "[가-힣]")
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let hits = hangul.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            XCTAssertEqual(hits, 0, "\(url.lastPathComponent) contains Hangul strings")
        }
    }
}

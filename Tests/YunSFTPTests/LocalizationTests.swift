import XCTest
@testable import yunsftp

final class LocalizationTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func catalog() throws -> [String: Any] {
        let url = root.appendingPathComponent("Sources/YunSFTP/Resources/Localizable.xcstrings")
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(obj?["strings"] as? [String: Any])
    }

    /// Every `L("…")` key in the sources has a Korean translation.
    func testEveryLocalizedKeyHasKorean() throws {
        let strings = try catalog()
        let pattern = try NSRegularExpression(pattern: #"\bL\("((?:[^"\\]|\\.)*)""#)
        var missing: [String] = []
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for m in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let raw = String(text[Range(m.range(at: 1), in: text)!])
                let key = raw.replacingOccurrences(of: "\\\"", with: "\"")
                let ko = ((strings[key] as? [String: Any])?["localizations"] as? [String: Any])?["ko"]
                if ko == nil { missing.append(key) }
            }
        }
        XCTAssertTrue(missing.isEmpty, "missing Korean for: \(Set(missing).sorted())")
    }

    func testCatalogIsCompiledIntoTheModuleBundle() throws {
        let koPath = try XCTUnwrap(Bundle.module.path(forResource: "ko", ofType: "lproj"))
        let ko = try XCTUnwrap(Bundle(path: koPath))
        XCTAssertEqual(ko.localizedString(forKey: "Connect", value: nil, table: nil), "연결")
        XCTAssertEqual(ko.localizedString(forKey: "Keep Both", value: nil, table: nil), "둘 다 유지")
    }

    func testFallbackIsTheEnglishKey() {
        XCTAssertEqual(L("String that is not in the catalog"), "String that is not in the catalog")
        XCTAssertEqual(L("Delete %d items from the server?", 3).contains("3"), true)
    }
}

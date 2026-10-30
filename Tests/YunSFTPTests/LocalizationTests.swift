import XCTest
@testable import yunsftp

final class LocalizationTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func koreanStrings() throws -> [String: String] {
        let url = root.appendingPathComponent("Sources/YunSFTP/Resources/ko.lproj/Localizable.strings")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    /// Every `L("…")` key in the sources has a Korean translation.
    func testEveryLocalizedKeyHasKorean() throws {
        let strings = try koreanStrings()
        let pattern = try NSRegularExpression(pattern: #"\bL\("((?:[^"\\]|\\.)*)""#)
        var missing: [String] = []
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for m in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let raw = String(text[Range(m.range(at: 1), in: text)!])
                let key = raw.replacingOccurrences(of: "\\\"", with: "\"")
                if strings[key] == nil { missing.append(key) }
            }
        }
        XCTAssertTrue(missing.isEmpty, "missing Korean for: \(Set(missing).sorted())")
    }

    func testKoreanTableIsFoundByTheAppsOwnLookup() throws {
        // The app must not rely on the toolchain-generated Bundle.module (its search paths vary).
        XCTAssertTrue(L10nBundle.isResourceBundleLoaded, "resource bundle not found from \(L10nBundle.bundle.bundlePath)")
        let bundle = L10nBundle.bundle
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil, localization: "ko"))
        let table = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
        XCTAssertEqual(table["Connect"], "연결")
        XCTAssertEqual(table["Keep Both"], "둘 다 유지")
        XCTAssertTrue(bundle.localizations.contains("ko"))
    }

    func testNoCodeUsesTheGeneratedModuleAccessor() throws {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root.appendingPathComponent("Sources"), includingPropertiesForKeys: nil))
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(text.contains("Bundle.module"), "\(url.lastPathComponent) uses Bundle.module, which traps when the bundle is not where that toolchain expects")
        }
    }

    func testFallbackIsTheEnglishKey() {
        XCTAssertEqual(L("String that is not in the catalog"), "String that is not in the catalog")
        XCTAssertEqual(L("Delete %d items from the server?", 3).contains("3"), true)
    }
}

import XCTest
@testable import yunsftp

final class SettingsTests: XCTestCase {

    func testOlderSettingsPayloadDecodesWithDefaultsForNewFields() throws {
        let legacy = #"{"sortField":"Name","sortAscending":true,"groupFolders":true,"fontSize":12,"viewMode":"List","showRelativeDates":false,"showDateModified":true,"showSize":true,"tools":[]}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(legacy.utf8))
        XCTAssertEqual(s.sortField, .name)
        XCTAssertFalse(s.showRelativeDates)
        XCTAssertTrue(s.showKind)
        XCTAssertFalse(s.showPermissions)
        XCTAssertTrue(s.confirmRemoteDelete)
        XCTAssertEqual(s.terminalApp, .terminal)
        XCTAssertFalse(s.legacyAlgorithmsByDefault)
    }

    func testFontSizeIsClampedOnDecode() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"fontSize":40}"#.utf8))
        XCTAssertEqual(s.fontSize, AppSettings.fontSizeRange.upperBound)
    }

    @MainActor
    func testStorePersistsChangesToItsDefaults() {
        let suite = "yunsftp.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        store.settings.showPermissions = true
        store.settings.terminalApp = .iterm
        let reloaded = AppSettings.load(from: defaults)
        XCTAssertTrue(reloaded.showPermissions)
        XCTAssertEqual(reloaded.terminalApp, .iterm)
    }

    func testRelativeDateFormatting() {
        // Locale-agnostic: a relative "Today …" string has no date digits, the absolute one does.
        let now = Date()
        let relative = FileItem.formatDate(now, relative: true)
        let absolute = FileItem.formatDate(now, relative: false)
        XCTAssertNotEqual(relative, absolute)
        let day = String(Calendar.current.component(.day, from: now))
        XCTAssertTrue(absolute.contains(day), absolute)
        let year = String(Calendar.current.component(.year, from: now) % 100)
        XCTAssertFalse(relative.contains(year), relative)
    }

    func testRemoteKindUsesSystemTypeNames() {
        XCTAssertEqual(FileItem.kindDescription(forRemoteName: "a", isDirectory: true, isSymlink: false), "Folder")
        XCTAssertEqual(FileItem.kindDescription(forRemoteName: "link", isDirectory: false, isSymlink: true), "Alias")
        let pdf = FileItem.kindDescription(forRemoteName: "report.pdf", isDirectory: false, isSymlink: false)
        XCTAssertTrue(pdf.localizedCaseInsensitiveContains("PDF"), pdf)
        XCTAssertEqual(FileItem.kindDescription(forRemoteName: "data.zzqq", isDirectory: false, isSymlink: false), "ZZQQ File")
        XCTAssertEqual(FileItem.kindDescription(forRemoteName: "Makefile", isDirectory: false, isSymlink: false), "Document")
    }

    func testNarrowPanesDropPermissionsThenKind() {
        var s = AppSettings()
        s.showPermissions = true
        XCTAssertEqual(FileListView.visibleColumns(paneWidth: 900, settings: s), .init(size: true, date: true, kind: true, perms: true))
        XCTAssertEqual(FileListView.visibleColumns(paneWidth: 500, settings: s), .init(size: true, date: true, kind: true, perms: false))
        XCTAssertEqual(FileListView.visibleColumns(paneWidth: 400, settings: s), .init(size: true, date: true, kind: false, perms: false))
        s.showSize = false
        XCTAssertFalse(FileListView.visibleColumns(paneWidth: 900, settings: s).size)
    }

    func testTerminalScriptPerApp() {
        XCTAssertTrue(TerminalService.appleScriptSource(for: "ls", app: .terminal).contains("tell application \"Terminal\""))
        let iterm = TerminalService.appleScriptSource(for: "ssh -p 22 -- 'u@h'", app: .iterm)
        XCTAssertTrue(iterm.contains("tell application \"iTerm\""))
        XCTAssertTrue(iterm.contains("create window with default profile command \"ssh -p 22 -- 'u@h'\""))
    }
}

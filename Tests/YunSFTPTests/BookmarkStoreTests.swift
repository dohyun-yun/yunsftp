import XCTest
@testable import yunsftp

@MainActor
final class BookmarkStoreTests: XCTestCase {
    private func makeStore() -> (BookmarkStore, UserDefaults, String) {
        let suite = "yunsftp.bm.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        return (BookmarkStore(defaults: d), d, suite)
    }

    func testToggleAndRemoveBookmarksNormalisePaths() {
        let (store, d, suite) = makeStore(); defer { d.removePersistentDomain(forName: suite) }
        let conn = UUID()
        store.toggle(connectionID: conn, path: "/srv/www/")
        XCTAssertTrue(store.isBookmarked(connectionID: conn, path: "/srv//www"))
        XCTAssertEqual(store.bookmarks(for: conn).first?.name, "www")
        store.toggle(connectionID: conn, path: "/srv/www")
        XCTAssertTrue(store.bookmarks(for: conn).isEmpty)
        store.toggle(connectionID: conn, path: "/")
        XCTAssertEqual(store.bookmarks(for: conn).first?.name, "/")
    }

    func testRecentsAreMostRecentFirstDedupedAndCapped() {
        let (store, d, suite) = makeStore(); defer { d.removePersistentDomain(forName: suite) }
        let conn = UUID()
        store.recordVisit(connectionID: conn, path: "/")            // root is ignored
        for i in 0..<15 { store.recordVisit(connectionID: conn, path: "/d\(i)") }
        store.recordVisit(connectionID: conn, path: "/d3")
        let r = store.recents(for: conn)
        XCTAssertEqual(r.count, BookmarkStore.recentsLimit)
        XCTAssertEqual(r.first, "/d3")
        XCTAssertEqual(Set(r).count, r.count)
        XCTAssertFalse(r.contains("/"))
        XCTAssertFalse(r.contains("/d0"))
    }

    func testPersistenceAndForget() {
        let (store, d, suite) = makeStore(); defer { d.removePersistentDomain(forName: suite) }
        let a = UUID(), b = UUID()
        store.toggle(connectionID: a, path: "/x"); store.recordVisit(connectionID: a, path: "/x")
        store.toggle(connectionID: b, path: "/y")
        let reloaded = BookmarkStore(defaults: d)
        XCTAssertEqual(reloaded.bookmarks.count, 2)
        XCTAssertEqual(reloaded.recents(for: a), ["/x"])
        reloaded.forget(connectionID: a)
        XCTAssertEqual(reloaded.bookmarks.map(\.connectionID), [b])
        XCTAssertTrue(reloaded.recents(for: a).isEmpty)
    }
}

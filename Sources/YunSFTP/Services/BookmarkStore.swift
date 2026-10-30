import Foundation

public struct RemoteBookmark: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var connectionID: UUID
    public var path: String
    public var name: String

    public init(id: UUID = UUID(), connectionID: UUID, path: String, name: String? = nil) {
        self.id = id
        self.connectionID = connectionID
        self.path = SFTPService.normalizeRemotePath(path)
        self.name = name ?? ((self.path as NSString).lastPathComponent.isEmpty ? "/" : (self.path as NSString).lastPathComponent)
    }
}

/// Remote folder bookmarks and per-connection recent folders.
@MainActor
public final class BookmarkStore: ObservableObject {
    public static let shared = BookmarkStore()
    public static let recentsLimit = 10

    @Published public private(set) var bookmarks: [RemoteBookmark] = [] { didSet { persist() } }
    @Published public private(set) var recents: [UUID: [String]] = [:] { didSet { persist() } }

    private let defaults: UserDefaults
    private let bookmarksKey = "yunsftp_RemoteBookmarks"
    private let recentsKey = "yunsftp_RemoteRecents"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Read both before assigning: assigning one triggers didSet/persist, which would write
        // the other (still empty) back to disk.
        let storedBookmarks = defaults.data(forKey: bookmarksKey).flatMap { try? JSONDecoder().decode([RemoteBookmark].self, from: $0) } ?? []
        let storedRecents = defaults.data(forKey: recentsKey).flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        bookmarks = storedBookmarks
        recents = Dictionary(uniqueKeysWithValues: storedRecents.compactMap { k, v in UUID(uuidString: k).map { ($0, v) } })
    }

    public func bookmarks(for connectionID: UUID) -> [RemoteBookmark] {
        bookmarks.filter { $0.connectionID == connectionID }
    }

    public func isBookmarked(connectionID: UUID, path: String) -> Bool {
        let p = SFTPService.normalizeRemotePath(path)
        return bookmarks.contains { $0.connectionID == connectionID && $0.path == p }
    }

    public func toggle(connectionID: UUID, path: String) {
        let p = SFTPService.normalizeRemotePath(path)
        if let idx = bookmarks.firstIndex(where: { $0.connectionID == connectionID && $0.path == p }) {
            bookmarks.remove(at: idx)
        } else {
            bookmarks.append(RemoteBookmark(connectionID: connectionID, path: p))
        }
    }

    public func remove(id: UUID) {
        bookmarks.removeAll { $0.id == id }
    }

    public func recents(for connectionID: UUID) -> [String] {
        recents[connectionID] ?? []
    }

    /// Most recent first, no duplicates, capped. The root is not worth remembering.
    public func recordVisit(connectionID: UUID, path: String) {
        let p = SFTPService.normalizeRemotePath(path)
        guard p != "/" else { return }
        var list = recents[connectionID] ?? []
        list.removeAll { $0 == p }
        list.insert(p, at: 0)
        if list.count > Self.recentsLimit { list = Array(list.prefix(Self.recentsLimit)) }
        recents[connectionID] = list
    }

    public func forget(connectionID: UUID) {
        bookmarks.removeAll { $0.connectionID == connectionID }
        recents[connectionID] = nil
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(bookmarks) { defaults.set(data, forKey: bookmarksKey) }
        let map = Dictionary(uniqueKeysWithValues: recents.map { ($0.key.uuidString, $0.value) })
        if let data = try? JSONEncoder().encode(map) { defaults.set(data, forKey: recentsKey) }
    }
}

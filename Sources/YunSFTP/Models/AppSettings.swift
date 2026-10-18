import Foundation

public struct CustomTool: Identifiable, Codable, Sendable {
    public var id = UUID()
    public var title: String
    public var executablePath: String
    public var arguments: [String]

    public init(title: String, executablePath: String, arguments: [String] = []) {
        self.title = title
        self.executablePath = executablePath
        self.arguments = arguments
    }
}

public struct AppSettings: Codable, Sendable {
    public var sortField: SortField = .date
    public var sortAscending: Bool = false
    public var groupFolders: Bool = true
    public var fontSize: Double = 12.0
    public var viewMode: ViewMode = .list
    public var showRelativeDates: Bool = true
    public var showDateModified: Bool = true
    public var showSize: Bool = true
    public var tools: [CustomTool] = []

    public static let sharedStorageKey = "yunsftp_AppSettings"
    public static let legacyStorageKey = "ForkLiftSilicon_AppSettings"

    public static func load() -> AppSettings {
        if let data = UserDefaults.standard.data(forKey: sharedStorageKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        if let data = UserDefaults.standard.data(forKey: legacyStorageKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings.save()
            return settings
        }
        return AppSettings()
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AppSettings.sharedStorageKey)
        }
    }
}

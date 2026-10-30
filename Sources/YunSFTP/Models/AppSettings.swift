import Foundation
import SwiftUI

public struct CustomTool: Identifiable, Codable, Sendable, Equatable {
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

public enum TerminalApp: String, CaseIterable, Identifiable, Codable, Sendable {
    case terminal = "Terminal"
    case iterm = "iTerm"
    public var id: String { rawValue }
}

public enum TransferEngine: String, CaseIterable, Identifiable, Codable, Sendable {
    case native = "Native"
    case openSSH = "OpenSSH"
    public var id: String { rawValue }
}

public struct AppSettings: Codable, Sendable, Equatable {
    public var sortField: SortField = .date
    public var sortAscending: Bool = false
    public var groupFolders: Bool = true
    /// List font size in points. Rows stay 22pt high, so the range is clamped to 10...14.
    public var fontSize: Double = 12.0
    public var viewMode: ViewMode = .list
    public var showRelativeDates: Bool = true
    public var showDateModified: Bool = true
    public var showSize: Bool = true
    public var showKind: Bool = true
    public var showPermissions: Bool = false
    public var confirmRemoteDelete: Bool = true
    public var terminalApp: TerminalApp = .terminal
    public var legacyAlgorithmsByDefault: Bool = false
    public var checkForUpdates: Bool = true
    /// Native swift-nio-ssh engine by default; OpenSSH command-line tools as fallback or on request.
    public var transferEngine: TransferEngine = .native
    public var tools: [CustomTool] = []

    public static let fontSizeRange: ClosedRange<Double> = 10...14

    public static let sharedStorageKey = "yunsftp_AppSettings"

    public init() {}

    // Every field is optional on decode so settings saved by older builds keep loading.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sortField = try c.decodeIfPresent(SortField.self, forKey: .sortField) ?? sortField
        sortAscending = try c.decodeIfPresent(Bool.self, forKey: .sortAscending) ?? sortAscending
        groupFolders = try c.decodeIfPresent(Bool.self, forKey: .groupFolders) ?? groupFolders
        fontSize = min(max(try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
        viewMode = try c.decodeIfPresent(ViewMode.self, forKey: .viewMode) ?? viewMode
        showRelativeDates = try c.decodeIfPresent(Bool.self, forKey: .showRelativeDates) ?? showRelativeDates
        showDateModified = try c.decodeIfPresent(Bool.self, forKey: .showDateModified) ?? showDateModified
        showSize = try c.decodeIfPresent(Bool.self, forKey: .showSize) ?? showSize
        showKind = try c.decodeIfPresent(Bool.self, forKey: .showKind) ?? showKind
        showPermissions = try c.decodeIfPresent(Bool.self, forKey: .showPermissions) ?? showPermissions
        confirmRemoteDelete = try c.decodeIfPresent(Bool.self, forKey: .confirmRemoteDelete) ?? confirmRemoteDelete
        terminalApp = try c.decodeIfPresent(TerminalApp.self, forKey: .terminalApp) ?? terminalApp
        legacyAlgorithmsByDefault = try c.decodeIfPresent(Bool.self, forKey: .legacyAlgorithmsByDefault) ?? legacyAlgorithmsByDefault
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? checkForUpdates
        transferEngine = try c.decodeIfPresent(TransferEngine.self, forKey: .transferEngine) ?? transferEngine
        tools = try c.decodeIfPresent([CustomTool].self, forKey: .tools) ?? tools
    }

    public static func load(from defaults: UserDefaults = .standard) -> AppSettings {
        if let data = defaults.data(forKey: sharedStorageKey),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        return AppSettings()
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: AppSettings.sharedStorageKey)
        }
    }
}

/// Live, observable settings. Views observe this so the Settings window applies immediately.
@MainActor
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    @Published public var settings: AppSettings {
        didSet {
            settings.save(to: defaults)
            if self === SettingsStore.shared { SFTPService.enginePreference = settings.transferEngine }
        }
    }
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = AppSettings.load(from: defaults)
    }

    /// Read from any thread: the terminal choice is needed by non-isolated AppleScript helpers.
    nonisolated public static var preferredTerminal: TerminalApp {
        return AppSettings.load().terminalApp
    }
}

import Foundation
import AppKit

public struct UpdateInfo: Sendable, Equatable {
    public let version: String
    public let url: URL
    public let notes: String?
}

/// Checks GitHub Releases for a newer tag. No telemetry: a single anonymous GET, at most once a day
/// when enabled in Settings, or on demand from the app menu.
@MainActor
public final class UpdateChecker {
    public static let shared = UpdateChecker()
    public static let releasesAPI = URL(string: "https://api.github.com/repos/dohyun-yun/yunsftp/releases/latest")!
    public static let releasesPage = URL(string: "https://github.com/dohyun-yun/yunsftp/releases")!
    static let interval: TimeInterval = 24 * 3600

    private let defaults: UserDefaults
    private let session: URLSession
    private let lastCheckKey = "yunsftp_UpdateLastCheck"
    private let skippedKey = "yunsftp_UpdateSkippedVersion"

    public init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
    }

    nonisolated public static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Semantic comparison on dotted numeric parts; a leading "v" is ignored.
    nonisolated public static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                .split(separator: "-").first.map(String.init)?
                .split(separator: ".").map { Int($0) ?? 0 } ?? []
        }
        let r = parts(remote), l = parts(local)
        let n = max(r.count, l.count)
        for i in 0..<n {
            let a = i < r.count ? r[i] : 0, b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }

    nonisolated public static func parseLatestRelease(_ data: Data) -> UpdateInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String,
              let urlString = obj["html_url"] as? String, let url = URL(string: urlString) else { return nil }
        if (obj["draft"] as? Bool) == true || (obj["prerelease"] as? Bool) == true { return nil }
        return UpdateInfo(version: tag, url: url, notes: obj["body"] as? String)
    }

    public func isDue(now: Date = Date()) -> Bool {
        guard let last = defaults.object(forKey: lastCheckKey) as? Date else { return true }
        return now.timeIntervalSince(last) >= Self.interval
    }

    public func markChecked(now: Date = Date()) { defaults.set(now, forKey: lastCheckKey) }
    public func skip(version: String) { defaults.set(version, forKey: skippedKey) }
    public var skippedVersion: String? { defaults.string(forKey: skippedKey) }

    /// Returns the newer release, or nil when up to date.
    public func fetchUpdate(currentVersion: String = UpdateChecker.currentVersion) async throws -> UpdateInfo? {
        var request = URLRequest(url: Self.releasesAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let (data, _) = try await session.data(for: request)
        markChecked()
        guard let info = Self.parseLatestRelease(data), Self.isNewer(info.version, than: currentVersion) else { return nil }
        return info
    }

    /// Launch path: silent unless a newer, not-skipped version exists.
    public func checkAtLaunchIfDue() async {
        guard SettingsStore.shared.settings.checkForUpdates, isDue() else { return }
        guard let info = try? await fetchUpdate(), info.version != skippedVersion else { return }
        presentUpdateAlert(info, allowSkip: true)
    }

    /// Menu path: always reports a result.
    public func checkInteractively() async {
        do {
            if let info = try await fetchUpdate() {
                presentUpdateAlert(info, allowSkip: false)
            } else {
                let alert = NSAlert()
                alert.messageText = L("You're up to date")
                alert.informativeText = L("yunsftp %@ is the latest version.", Self.currentVersion)
                alert.runModal()
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Could not check for updates")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func presentUpdateAlert(_ info: UpdateInfo, allowSkip: Bool) {
        let alert = NSAlert()
        alert.messageText = L("yunsftp %@ is available", info.version)
        alert.informativeText = L("You have %@. Download the new version from GitHub Releases.", Self.currentVersion)
        alert.addButton(withTitle: L("Download"))
        alert.addButton(withTitle: L("Later"))
        if allowSkip { alert.addButton(withTitle: L("Skip This Version")) }
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(info.url)
        case .alertThirdButtonReturn: skip(version: info.version)
        default: break
        }
    }
}

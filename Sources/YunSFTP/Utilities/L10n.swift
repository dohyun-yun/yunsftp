import Foundation

/// Locates the SwiftPM resource bundle (`yunsftp_yunsftp.bundle`) without the toolchain-
/// generated module-bundle accessor, whose search paths depend on the toolchain that built the app:
/// the Swift 6.0 accessor only looks next to the executable's bundle and in the build directory,
/// so an app bundle with the resources in `Contents/Resources` crashed at launch. Falls back to
/// the main bundle (English keys) instead of trapping.
public enum L10nBundle {
    static let resourceBundleName = "yunsftp_yunsftp.bundle"

    private final class Marker {}

    public static let bundle: Bundle = {
        var candidates: [URL] = []
        if let r = Bundle.main.resourceURL { candidates.append(r) }
        candidates.append(Bundle.main.bundleURL)
        if let exe = Bundle.main.executableURL { candidates.append(exe.deletingLastPathComponent()) }
        // Tests: the resource bundle sits next to the .xctest bundle in the build directory.
        candidates.append(Bundle(for: Marker.self).bundleURL.deletingLastPathComponent())
        for dir in candidates {
            if let b = Bundle(url: dir.appendingPathComponent(resourceBundleName)) { return b }
        }
        return Bundle.main
    }()

    /// True when a real resource bundle (not the main-bundle fallback) was found.
    public static var isResourceBundleLoaded: Bool { bundle.bundleURL.lastPathComponent == resourceBundleName }
}

/// Looks a user-facing string up in `Resources/<lang>.lproj/Localizable.strings`.
/// The English text is the key, so a missing translation falls back to it unchanged.
public func L(_ key: String) -> String {
    return L10nBundle.bundle.localizedString(forKey: key, value: key, table: nil)
}

/// `L` with `String(format:)` arguments.
public func L(_ key: String, _ args: CVarArg...) -> String {
    return String(format: L(key), locale: Locale.current, arguments: args)
}

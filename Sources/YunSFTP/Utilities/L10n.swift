import Foundation

/// Looks a user-facing string up in `Resources/<lang>.lproj/Localizable.strings`.
/// The English text is the key, so a missing translation falls back to it unchanged.
public func L(_ key: String) -> String {
    return Bundle.module.localizedString(forKey: key, value: key, table: nil)
}

/// `L` with `String(format:)` arguments.
public func L(_ key: String, _ args: CVarArg...) -> String {
    return String(format: L(key), locale: Locale.current, arguments: args)
}

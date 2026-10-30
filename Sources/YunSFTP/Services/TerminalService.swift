import Foundation
import AppKit

public struct TerminalService {
    public static func openInTerminal(at directoryURL: URL) {
        let ok = runInTerminal("cd \(SFTPService.posixShellEscape(directoryURL.path))")
        if !ok {
            // Fallback: open Terminal via NSWorkspace
            NSWorkspace.shared.open([directoryURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    /// Runs an already shell-quoted command in a new Terminal tab. Returns false on AppleScript error.
    @discardableResult
    public static func runInTerminal(_ shellCommand: String) -> Bool {
        let script = appleScriptSource(for: shellCommand)
        guard let appleScript = NSAppleScript(source: script) else { return false }
        var error: NSDictionary?
        appleScript.executeAndReturnError(&error)
        return error == nil
    }

    static func appleScriptSource(for shellCommand: String) -> String {
        return """
        tell application "Terminal"
            activate
            do script \(escapeForAppleScript(shellCommand))
        end tell
        """
    }

    public static func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public static func openItem(url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func escapeForAppleScript(_ string: String) -> String {
        return "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

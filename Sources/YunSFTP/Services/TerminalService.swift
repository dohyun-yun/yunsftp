import Foundation
import AppKit

public struct TerminalService {
    public static func openInTerminal(at directoryURL: URL) {
        let path = directoryURL.path
        let script = """
        tell application "Terminal"
            activate
            do script "cd \(escapeForAppleScript(path))"
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if error != nil {
                // Fallback: open Terminal via NSWorkspace
                NSWorkspace.shared.open([directoryURL], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
            }
        }
    }

    public static func revealInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public static func openItem(url: URL) {
        NSWorkspace.shared.open(url)
    }

    private static func escapeForAppleScript(_ string: String) -> String {
        return "\"" + string.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

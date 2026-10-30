import SwiftUI
import AppKit

enum DemoHelper {
    static var isDemoMode: Bool {
        CommandLine.arguments.contains("--demo-screenshot")
    }

    /// `--appearance light|dark` forces the window appearance for documentation screenshots.
    static var forcedAppearance: NSAppearance? {
        guard let idx = CommandLine.arguments.firstIndex(of: "--appearance"), idx + 1 < CommandLine.arguments.count else { return nil }
        switch CommandLine.arguments[idx + 1] {
        case "dark": return NSAppearance(named: .darkAqua)
        case "light": return NSAppearance(named: .aqua)
        default: return nil
        }
    }

    /// The main browser window: the largest visible one (Settings/Transfers windows are smaller).
    @MainActor
    static var mainWindow: NSWindow? {
        NSApplication.shared.windows.filter { $0.isVisible }.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    static func render(_ view: NSView, to url: URL, scale: CGFloat) -> Bool {
        let s = max(2, scale)   // documentation screenshots are always 2x
        let w = Int(view.bounds.width * s), h = Int(view.bounds.height * s)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return false }
        rep.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }

    /// `--view list|table|grid` picks the pane presentation for documentation screenshots.
    static var demoViewMode: ViewMode? {
        guard let idx = CommandLine.arguments.firstIndex(of: "--view"), idx + 1 < CommandLine.arguments.count else { return nil }
        switch CommandLine.arguments[idx + 1] {
        case "table": return .table
        case "grid": return .grid
        case "list": return .list
        default: return nil
        }
    }

    static var screenshotOutputPath: String? {
        if let idx = CommandLine.arguments.firstIndex(of: "--demo-screenshot"), idx + 1 < CommandLine.arguments.count {
            return CommandLine.arguments[idx + 1]
        }
        return nil
    }

    @MainActor
    static func createDemoPanes() -> (left: PaneModel, right: PaneModel, favs: [FavoriteLocation]) {
        UserDefaults.standard.set(220.0, forKey: "colWidth_name")
        UserDefaults.standard.set(80.0, forKey: "colWidth_size")
        UserDefaults.standard.set(135.0, forKey: "colWidth_date")
        UserDefaults.standard.set(95.0, forKey: "colWidth_kind")
        UserDefaults.standard.set(65.0, forKey: "colWidth_perms")

        let demoConn1 = RemoteConnection(
            name: "Ubuntu Cloud Server (SFTP)",
            host: "sftp.example.com",
            port: 22,
            username: "deploy",
            remotePath: "/var/www/production"
        )
        let demoConn2 = RemoteConnection(
            name: "Staging Server",
            host: "staging.example.com",
            port: 22,
            username: "admin",
            remotePath: "/home/admin"
        )
        ConnectionManager.shared.connections = [demoConn1, demoConn2]

        // Left Pane (SFTP)
        let left = PaneModel(autoLoad: false)
        left.isRemote = true
        left.remoteConnection = demoConn1
        left.remotePath = "/var/www/production"
        let remoteBase = SFTPService.sftpURL(host: demoConn1.host, port: demoConn1.port, path: "/var/www/production")
        left.currentURL = remoteBase

        let now = Date()
        let remoteItems: [FileItem] = [
            FileItem(virtualURL: remoteBase.appendingPathComponent("assets"), name: "assets", isDirectory: true, size: 0, modificationDate: now.addingTimeInterval(-3600 * 2), permissions: "rwxr-xr-x", kind: "Folder"),
            FileItem(virtualURL: remoteBase.appendingPathComponent("config"), name: "config", isDirectory: true, size: 0, modificationDate: now.addingTimeInterval(-3600 * 4), permissions: "rwxr-xr-x", kind: "Folder"),
            FileItem(virtualURL: remoteBase.appendingPathComponent("public"), name: "public", isDirectory: true, size: 0, modificationDate: now.addingTimeInterval(-3600 * 6), permissions: "rwxr-xr-x", kind: "Folder"),
            FileItem(virtualURL: remoteBase.appendingPathComponent("src"), name: "src", isDirectory: true, size: 0, modificationDate: now.addingTimeInterval(-3600 * 8), permissions: "rwxr-xr-x", kind: "Folder"),
            FileItem(virtualURL: remoteBase.appendingPathComponent("backup-2026-10.tar.gz"), name: "backup-2026-10.tar.gz", isDirectory: false, size: 142_800_000, modificationDate: now.addingTimeInterval(-3600 * 12), permissions: "rw-r--r--", kind: "Archive"),
            FileItem(virtualURL: remoteBase.appendingPathComponent("docker-compose.yml"), name: "docker-compose.yml", isDirectory: false, size: 1_420, modificationDate: now.addingTimeInterval(-3600 * 14), permissions: "rw-r--r--", kind: "YAML"),
            FileItem(virtualURL: remoteBase.appendingPathComponent("index.html"), name: "index.html", isDirectory: false, size: 8_240, modificationDate: now.addingTimeInterval(-3600 * 16), permissions: "rw-r--r--", kind: "HTML"),
            FileItem(virtualURL: remoteBase.appendingPathComponent("package.json"), name: "package.json", isDirectory: false, size: 2_150, modificationDate: now.addingTimeInterval(-3600 * 18), permissions: "rw-r--r--", kind: "JSON"),
            FileItem(virtualURL: remoteBase.appendingPathComponent("README.md"), name: "README.md", isDirectory: false, size: 4_520, modificationDate: now.addingTimeInterval(-3600 * 20), permissions: "rw-r--r--", kind: "Markdown"),
            FileItem(virtualURL: remoteBase.appendingPathComponent("server.js"), name: "server.js", isDirectory: false, size: 12_680, modificationDate: now.addingTimeInterval(-3600 * 10), permissions: "rw-r--r--", kind: "JavaScript")
        ]
        left.items = remoteItems
        let selectedRemote = remoteBase.appendingPathComponent("index.html")
        left.selectedItemURLs = [selectedRemote]
        left.focusedItemURL = selectedRemote
        left.isLoading = false
        left.isConnecting = false

        // Right Pane (Local)
        let localBase = URL(fileURLWithPath: "/Users/developer/Projects/yunsftp")
        let right = PaneModel(initialURL: localBase, autoLoad: false)
        right.isRemote = false
        right.currentURL = localBase
        let localItems: [FileItem] = [
            FileItem(virtualURL: localBase.appendingPathComponent("Resources"), name: "Resources", isDirectory: true, size: 0, modificationDate: now.addingTimeInterval(-3600 * 1), permissions: "rwxr-xr-x", kind: "Folder"),
            FileItem(virtualURL: localBase.appendingPathComponent("scripts"), name: "scripts", isDirectory: true, size: 0, modificationDate: now.addingTimeInterval(-3600 * 2), permissions: "rwxr-xr-x", kind: "Folder"),
            FileItem(virtualURL: localBase.appendingPathComponent("Sources"), name: "Sources", isDirectory: true, size: 0, modificationDate: now.addingTimeInterval(-3600 * 3), permissions: "rwxr-xr-x", kind: "Folder"),
            FileItem(virtualURL: localBase.appendingPathComponent("Tests"), name: "Tests", isDirectory: true, size: 0, modificationDate: now.addingTimeInterval(-3600 * 4), permissions: "rwxr-xr-x", kind: "Folder"),
            FileItem(virtualURL: localBase.appendingPathComponent("build_app.sh"), name: "build_app.sh", isDirectory: false, size: 840, modificationDate: now.addingTimeInterval(-3600 * 5), permissions: "rwxr-xr-x", kind: "Shell Script"),
            FileItem(virtualURL: localBase.appendingPathComponent("LICENSE"), name: "LICENSE", isDirectory: false, size: 1_080, modificationDate: now.addingTimeInterval(-3600 * 6), permissions: "rw-r--r--", kind: "Plain Text"),
            FileItem(virtualURL: localBase.appendingPathComponent("Package.swift"), name: "Package.swift", isDirectory: false, size: 1_240, modificationDate: now.addingTimeInterval(-3600 * 7), permissions: "rw-r--r--", kind: "Swift Source"),
            FileItem(virtualURL: localBase.appendingPathComponent("README.md"), name: "README.md", isDirectory: false, size: 6_820, modificationDate: now.addingTimeInterval(-3600 * 8), permissions: "rw-r--r--", kind: "Markdown")
        ]
        right.items = localItems
        let selectedLocal = localBase.appendingPathComponent("Package.swift")
        right.selectedItemURLs = [selectedLocal]
        right.focusedItemURL = selectedLocal
        right.isLoading = false
        right.isConnecting = false

        let favs = [
            FavoriteLocation(name: "Projects", url: URL(fileURLWithPath: "/Users/developer/Projects"), systemIconName: "folder")
        ]

        if let mode = demoViewMode { left.viewMode = mode; right.viewMode = mode }
        return (left, right, favs)
    }
}

@main
struct YunSFTPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// Opens the standard Settings scene (works on macOS 13 and 14+ without the `openSettings` environment action).
    static func openSettings() {
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            if DemoHelper.isDemoMode {
                let demo = DemoHelper.createDemoPanes()
                MainWindowView(leftPane: demo.left, rightPane: demo.right, customFavorites: demo.favs)
            } else {
                MainWindowView()
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await UpdateChecker.shared.checkInteractively() }
                }
            }
            ToolbarCommands()
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { Self.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            SidebarCommands()
            // Single-window app: drop the default File > New items instead of offering a no-op.
            CommandGroup(replacing: .newItem) {}
        }

        // Auxiliary scenes come after the main WindowGroup: the first scene is what opens at launch.
        Settings {
            SettingsView()
        }

        Window("Transfers", id: "transfers") {
            TransfersWindowView()
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
        .defaultSize(width: 620, height: 400)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        if DemoHelper.isDemoMode, let outputPath = DemoHelper.screenshotOutputPath {
            if let appearance = DemoHelper.forcedAppearance {
                NSApplication.shared.appearance = appearance
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                for w in NSApplication.shared.windows where w.isVisible && w != DemoHelper.mainWindow { w.orderOut(nil) }
                if let win = DemoHelper.mainWindow {
                    win.appearance = DemoHelper.forcedAppearance   // windows created before NSApp.appearance took effect
                    win.setFrame(NSRect(x: 100, y: 100, width: 1440, height: 820), display: true, animate: false)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if let win = DemoHelper.mainWindow {
                    // Render the whole window frame (title bar + toolbar + content) in-process:
                    // no Screen Recording permission needed, unlike `screencapture -l`.
                    let frameView = win.contentView?.superview ?? win.contentView!
                    let ok = DemoHelper.render(frameView, to: URL(fileURLWithPath: outputPath), scale: win.backingScaleFactor)
                    print(ok ? "DEMO_SCREENSHOT_CAPTURED_TO: \(outputPath)" : "DEMO_SCREENSHOT_FAILED")
                    exit(ok ? 0 : 1)
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                for w in NSApplication.shared.windows {
                    w.makeKeyAndOrderFront(nil)
                }
            }
            Task.detached(priority: .background) { RemoteDragProvider.cleanUpTempCopies() }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)   // let the window settle first
                await UpdateChecker.shared.checkAtLaunchIfDue()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if let window = sender.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}

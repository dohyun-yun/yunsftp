import SwiftUI
import AppKit

enum DemoHelper {
    static var isDemoMode: Bool {
        CommandLine.arguments.contains("--demo-screenshot")
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
            FileItem(virtualURL: remoteBase.appendingPathComponent("assets"), name: "assets", isDirectory: true, size: 0, modificationDate: now.addingTimeInterval(-3600 * 2), permissions: "rwxr-xr-x", kind: "Remote Folder"),
            FileItem(virtualURL: remoteBase.appendingPathComponent("config"), name: "config", isDirectory: true, size: 0, modificationDate: now.addingTimeInterval(-3600 * 4), permissions: "rwxr-xr-x", kind: "Remote Folder"),
            FileItem(virtualURL: remoteBase.appendingPathComponent("public"), name: "public", isDirectory: true, size: 0, modificationDate: now.addingTimeInterval(-3600 * 6), permissions: "rwxr-xr-x", kind: "Remote Folder"),
            FileItem(virtualURL: remoteBase.appendingPathComponent("src"), name: "src", isDirectory: true, size: 0, modificationDate: now.addingTimeInterval(-3600 * 8), permissions: "rwxr-xr-x", kind: "Remote Folder"),
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

        return (left, right, favs)
    }
}

@main
struct YunSFTPApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
            SidebarCommands()
            // Single-window app: drop the default File > New items instead of offering a no-op.
            CommandGroup(replacing: .newItem) {}
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        if DemoHelper.isDemoMode, let outputPath = DemoHelper.screenshotOutputPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let win = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                    win.setFrame(NSRect(x: 100, y: 100, width: 1440, height: 820), display: true, animate: false)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if let win = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                    let winNum = win.windowNumber
                    let proc = Process()
                    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    proc.arguments = ["-l", "\(winNum)", "-o", outputPath]
                    try? proc.run()
                    proc.waitUntilExit()
                    print("DEMO_SCREENSHOT_CAPTURED_TO:", outputPath)
                    exit(0)
                }
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                for w in NSApplication.shared.windows {
                    w.makeKeyAndOrderFront(nil)
                }
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

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

public final class FileIconProvider: @unchecked Sendable {
    public static let shared = FileIconProvider()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 1000
    }

    public func icon(for item: FileItem) -> NSImage {
        let ext = item.fileExtension.lowercased()
        let isAppOrBundle = (ext == "app" || ext == "pkg" || ext == "dmg" || ext == "prefpane")
        let key: NSString

        if FileManager.default.fileExists(atPath: item.url.path) {
            // Local files: applications, bundles, and directories must be keyed by path to preserve their distinct icons
            if isAppOrBundle || item.isDirectory {
                key = "local_path:\(item.url.path)" as NSString
            } else {
                key = "local_ext:\(ext)" as NSString
            }
        } else {
            // Remote SFTP items (not present locally on Mac)
            if item.isDirectory {
                key = (isAppOrBundle ? "remote_bundle:\(item.url.path)" : "remote_dir") as NSString
            } else {
                key = "remote_ext:\(ext)" as NSString
            }
        }

        if let cached = cache.object(forKey: key) {
            return cached
        }

        let img: NSImage
        if FileManager.default.fileExists(atPath: item.url.path) {
            img = NSWorkspace.shared.icon(forFile: item.url.path)
        } else if item.isDirectory {
            img = NSWorkspace.shared.icon(for: .folder)
        } else if let uttype = UTType(filenameExtension: item.fileExtension) {
            img = NSWorkspace.shared.icon(for: uttype)
        } else {
            img = NSWorkspace.shared.icon(for: .data)
        }

        img.size = NSSize(width: 32, height: 32)
        cache.setObject(img, forKey: key)
        return img
    }

    public func icon(forPath path: String) -> NSImage {
        let key = path as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let img = NSWorkspace.shared.icon(forFile: path)
        img.size = NSSize(width: 32, height: 32)
        cache.setObject(img, forKey: key)
        return img
    }
}

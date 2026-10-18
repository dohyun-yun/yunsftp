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
        let key = (item.isDirectory ? "dir:\(item.fileExtension)" : "file:\(item.fileExtension)") as NSString
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

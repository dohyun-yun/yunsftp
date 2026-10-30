import Foundation
import AppKit

public struct DirectoryComparisonResult: Identifiable {
    public let id = UUID()
    public let name: String
    public let leftItem: FileItem?
    public let rightItem: FileItem?
    public let status: ComparisonStatus

    public enum ComparisonStatus: String {
        case identical = "Identical"
        case leftOnly = "Left Only"
        case rightOnly = "Right Only"
        case differentSize = "Different Size"
        case differentDate = "Different Date"
    }
}

public actor FileSystemService {
    public static let shared = FileSystemService()

    private let fileManager = FileManager.default

    public func createFolder(at parentURL: URL, name: String) throws -> URL {
        let newURL = parentURL.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: newURL, withIntermediateDirectories: false, attributes: nil)
        return newURL
    }

    public func createFile(at parentURL: URL, name: String, content: String = "") throws -> URL {
        let newURL = parentURL.appendingPathComponent(name, isDirectory: false)
        guard let data = content.data(using: .utf8) else {
            throw NSError(domain: "yunsftp", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid text encoding"])
        }
        guard fileManager.createFile(atPath: newURL.path, contents: data, attributes: nil) else {
            throw NSError(domain: "yunsftp", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create file"])
        }
        return newURL
    }

    public func rename(url: URL, to newName: String) throws -> URL {
        let parent = url.deletingLastPathComponent()
        let destination = parent.appendingPathComponent(newName)
        try fileManager.moveItem(at: url, to: destination)
        return destination
    }

    public func chmod(url: URL, posixPermissions: Int) throws {
        try fileManager.setAttributes([.posixPermissions: NSNumber(value: posixPermissions)], ofItemAtPath: url.path)
    }

    public func copy(urls: [URL], to destinationDirectory: URL, overwrite: Bool = false) async throws {
        for src in urls {
            var dest = destinationDirectory.appendingPathComponent(src.lastPathComponent)
            if fileManager.fileExists(atPath: dest.path) {
                if overwrite {
                    try? fileManager.removeItem(at: dest)
                } else {
                    dest = uniqueDestinationURL(for: dest)
                }
            }
            try fileManager.copyItem(at: src, to: dest)
        }
    }

    public func move(urls: [URL], to destinationDirectory: URL, overwrite: Bool = false) async throws {
        for src in urls {
            // Avoid moving folder into itself (component-wise, so /a/b does not block /a/bc)
            if Self.isSameOrDescendant(destinationDirectory, of: src) {
                throw NSError(domain: "yunsftp", code: 3, userInfo: [NSLocalizedDescriptionKey: "Cannot move a folder into itself"])
            }
            var dest = destinationDirectory.appendingPathComponent(src.lastPathComponent)
            if fileManager.fileExists(atPath: dest.path) {
                if overwrite {
                    try? fileManager.removeItem(at: dest)
                } else {
                    dest = uniqueDestinationURL(for: dest)
                }
            }
            try fileManager.moveItem(at: src, to: dest)
        }
    }

    @discardableResult
    public func duplicate(url src: URL) async throws -> URL {
        let parent = src.deletingLastPathComponent()
        let baseName = (src.lastPathComponent as NSString).deletingPathExtension
        let ext = (src.lastPathComponent as NSString).pathExtension
        let copyName = ext.isEmpty ? "\(baseName) copy" : "\(baseName) copy.\(ext)"
        var dest = parent.appendingPathComponent(copyName)
        dest = uniqueDestinationURL(for: dest)
        try fileManager.copyItem(at: src, to: dest)
        return dest
    }

    public func duplicate(urls: [URL]) async throws {
        for src in urls {
            _ = try await duplicate(url: src)
        }
    }

    public func moveToTrash(urls: [URL]) async throws {
        for url in urls {
            try fileManager.trashItem(at: url, resultingItemURL: nil)
        }
    }

    public func deletePermanently(urls: [URL]) async throws {
        for url in urls {
            try fileManager.removeItem(at: url)
        }
    }

    public func compress(urls: [URL], to destinationDirectory: URL) async throws -> URL {
        guard let first = urls.first else {
            throw NSError(domain: "yunsftp", code: 4, userInfo: [NSLocalizedDescriptionKey: "No items to compress"])
        }

        let zipName: String
        if urls.count == 1 {
            let baseName = (first.lastPathComponent as NSString).deletingPathExtension
            zipName = "\(baseName).zip"
        } else {
            zipName = "Archive.zip"
        }

        var zipURL = destinationDirectory.appendingPathComponent(zipName)
        zipURL = uniqueDestinationURL(for: zipURL)

        let parentDir = first.deletingLastPathComponent().path
        let itemNames = urls.map { $0.lastPathComponent }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = URL(fileURLWithPath: parentDir)
        process.arguments = ["-r", zipURL.path, "--"] + itemNames

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(domain: "yunsftp", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Compression failed with code \(process.terminationStatus)"])
        }

        return zipURL
    }

    public func extract(archiveURL: URL, to destinationDirectory: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", archiveURL.path, "-d", destinationDirectory.path]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw NSError(domain: "yunsftp", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "Extraction failed with code \(process.terminationStatus)"])
        }
    }

    public static func compareItemLists(leftItems: [FileItem], rightItems: [FileItem]) -> [DirectoryComparisonResult] {
        var leftDict: [String: FileItem] = [:]
        for item in leftItems {
            leftDict[item.name.precomposedStringWithCanonicalMapping] = item
        }
        var rightDict: [String: FileItem] = [:]
        for item in rightItems {
            rightDict[item.name.precomposedStringWithCanonicalMapping] = item
        }

        let allNames = Set(leftDict.keys).union(rightDict.keys).sorted()
        var results: [DirectoryComparisonResult] = []

        for name in allNames {
            let left = leftDict[name]
            let right = rightDict[name]

            let status: DirectoryComparisonResult.ComparisonStatus
            if let l = left, let r = right {
                if l.size != r.size {
                    status = .differentSize
                } else if abs(l.modificationDate.timeIntervalSince(r.modificationDate)) > 60.0 {
                    status = .differentDate
                } else {
                    status = .identical
                }
            } else if left != nil {
                status = .leftOnly
            } else {
                status = .rightOnly
            }

            results.append(DirectoryComparisonResult(name: name, leftItem: left, rightItem: right, status: status))
        }

        return results
    }

    public func compareDirectories(leftURL: URL, rightURL: URL) async -> [DirectoryComparisonResult] {
        let leftFiles = (try? fileManager.contentsOfDirectory(at: leftURL, includingPropertiesForKeys: nil)) ?? []
        let rightFiles = (try? fileManager.contentsOfDirectory(at: rightURL, includingPropertiesForKeys: nil)) ?? []
        return Self.compareItemLists(
            leftItems: leftFiles.map { FileItem(url: $0) },
            rightItems: rightFiles.map { FileItem(url: $0) }
        )
    }

    static func isSameOrDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
        let a = ancestor.standardizedFileURL.pathComponents
        let c = candidate.standardizedFileURL.pathComponents
        return c.count >= a.count && Array(c.prefix(a.count)) == a
    }

    /// Where a "keep both" copy/download of `fileName` into `directory` will land. Shared by the
    /// local copy path, SFTP downloads and the progress monitors so they all agree on the name.
    public static func plannedDestinationURL(fileName: String, in directory: URL) -> URL {
        let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .map { $0.precomposedStringWithCanonicalMapping })
        let name = SFTPService.uniqueName(fileName.precomposedStringWithCanonicalMapping, existing: existing)
        return directory.appendingPathComponent(name)
    }

    private func uniqueDestinationURL(for url: URL) -> URL {
        return Self.plannedDestinationURL(fileName: url.lastPathComponent, in: url.deletingLastPathComponent())
    }
}

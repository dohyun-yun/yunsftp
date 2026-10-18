import Foundation
import AppKit

public struct FileItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isSymlink: Bool
    public let size: Int64
    public let modificationDate: Date
    public let creationDate: Date?
    public let fileExtension: String
    public let kindDescription: String
    public let posixPermissions: String
    public let isHidden: Bool
    public let symlinkTarget: String?

    public init(url: URL) {
        self.url = url
        let standardizedURL = url.standardized
        self.name = standardizedURL.lastPathComponent.precomposedStringWithCanonicalMapping

        var isDir: ObjCBool = false
        let fileManager = FileManager.default
        _ = fileManager.fileExists(atPath: standardizedURL.path, isDirectory: &isDir)

        let resourceValues = try? standardizedURL.resourceValues(forKeys: [
            .isDirectoryKey,
            .isPackageKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .localizedTypeDescriptionKey,
            .isHiddenKey
        ])

        let isDirVal = resourceValues?.isDirectory ?? isDir.boolValue
        self.isDirectory = isDirVal
        self.isPackage = resourceValues?.isPackage ?? false
        self.isSymlink = resourceValues?.isSymbolicLink ?? false
        self.size = Int64(resourceValues?.fileSize ?? 0)
        self.modificationDate = resourceValues?.contentModificationDate ?? Date()
        self.creationDate = resourceValues?.creationDate
        self.fileExtension = standardizedURL.pathExtension.lowercased()
        self.kindDescription = resourceValues?.localizedTypeDescription ?? (isDirVal ? "Folder" : "File")
        self.isHidden = (resourceValues?.isHidden ?? false) || standardizedURL.lastPathComponent.hasPrefix(".")

        // POSIX Permissions
        if let attrs = try? fileManager.attributesOfItem(atPath: standardizedURL.path),
           let posixNum = attrs[.posixPermissions] as? NSNumber {
            self.posixPermissions = FileItem.formatPOSIXPermissions(posixNum.intValue)
        } else {
            self.posixPermissions = "---"
        }

        // Symlink target
        if self.isSymlink, let destination = try? fileManager.destinationOfSymbolicLink(atPath: standardizedURL.path) {
            self.symlinkTarget = destination
        } else {
            self.symlinkTarget = nil
        }
    }

    public init(virtualURL: URL, name: String, isDirectory: Bool, isSymlink: Bool = false, size: Int64, modificationDate: Date, permissions: String) {
        self.url = virtualURL
        self.name = SFTPService.decodeLsEscapes(name).precomposedStringWithCanonicalMapping
        self.isDirectory = isDirectory
        self.isPackage = false
        self.isSymlink = isSymlink
        self.size = size
        self.modificationDate = modificationDate
        self.creationDate = nil
        self.fileExtension = (name as NSString).pathExtension.lowercased()
        self.kindDescription = isDirectory ? "Remote Folder" : (isSymlink ? "Remote Symlink" : "Remote File")
        self.posixPermissions = permissions
        self.isHidden = name.hasPrefix(".")
        self.symlinkTarget = nil
    }

    public static func formatPOSIXPermissions(_ mode: Int) -> String {
        let chars: [(Int, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]
        var result = ""
        for (mask, char) in chars {
            if (mode & mask) != 0 {
                result.append(char)
            } else {
                result.append("-")
            }
        }
        return result
    }

    public var formattedSize: String {
        if isDirectory {
            return "--"
        }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(url.absoluteString)
    }

    public static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url.absoluteString == rhs.url.absoluteString
    }
}

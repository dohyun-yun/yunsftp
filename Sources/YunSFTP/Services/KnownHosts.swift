import Foundation
import CryptoKit

/// Trust-on-first-use host key store compatible with OpenSSH's `~/.ssh/known_hosts`
/// (plain and hashed `|1|salt|hmac` entries, `[host]:port` for non-standard ports).
public struct KnownHosts: Sendable {
    public enum Verdict: Equatable, Sendable { case trusted, unknown, mismatch }

    public let fileURL: URL

    public init(fileURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh/known_hosts")) {
        self.fileURL = fileURL
    }

    /// OpenSSH writes `host` for port 22 and `[host]:port` otherwise.
    public static func hostPattern(host: String, port: Int) -> String {
        port == 22 ? host.lowercased() : "[\(host.lowercased())]:\(port)"
    }

    /// `keyType` is the wire name (e.g. `ssh-ed25519`), `keyBase64` the base64 blob as in known_hosts.
    public func verdict(host: String, port: Int, keyType: String, keyBase64: String) -> Verdict {
        let pattern = Self.hostPattern(host: host, port: port)
        let matching = entries().filter { $0.matches(pattern) }
        // Revocations win regardless of where they appear in the file (OpenSSH semantics).
        if matching.contains(where: { $0.marker == "@revoked" && $0.keyType == keyType && $0.keyBase64 == keyBase64 }) {
            return .mismatch
        }
        var sawHost = false
        for entry in matching where entry.marker == nil {      // CA lines never vouch for a plain key
            if entry.keyType != keyType { continue }   // a server may legitimately present several key types
            sawHost = true
            if entry.keyBase64 == keyBase64 { return .trusted }
        }
        return sawHost ? .mismatch : .unknown
    }

    /// Appends a plain entry (same format `StrictHostKeyChecking=accept-new` produces).
    public func remember(host: String, port: Int, keyType: String, keyBase64: String) throws {
        let line = "\(Self.hostPattern(host: host, port: port)) \(keyType) \(keyBase64)\n"
        let dir = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forUpdating: fileURL)   // read the last byte, then append
            defer { try? handle.close() }
            let end = try handle.seekToEnd()
            if end > 0 {
                // A hand-edited file may lack the final newline; never glue onto the last entry.
                try handle.seek(toOffset: end - 1)
                if let last = try handle.read(upToCount: 1), last != Data("\n".utf8) {
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data("\n".utf8))
                }
                try handle.seekToEnd()
            }
            try handle.write(contentsOf: Data(line.utf8))
        } else {
            try Data(line.utf8).write(to: fileURL)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
    }

    struct Entry {
        let hosts: String      // comma-separated patterns, or a hashed `|1|salt|hash`
        let keyType: String
        let keyBase64: String
        var marker: String? = nil   // "@revoked" / "@cert-authority"

        func matches(_ pattern: String) -> Bool {
            if hosts.hasPrefix("|1|") {
                let parts = hosts.split(separator: "|").map(String.init)   // ["1", salt, hash]
                guard parts.count == 3, let salt = Data(base64Encoded: parts[1]), let hash = Data(base64Encoded: parts[2]) else { return false }
                let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(pattern.utf8), using: SymmetricKey(data: salt))
                return Data(mac) == hash
            }
            return hosts.split(separator: ",").contains { candidate in
                let c = String(candidate).lowercased()
                if c.hasPrefix("!") { return false }
                return c == pattern || Self.wildcardMatch(pattern: c, value: pattern)
            }
        }

        /// OpenSSH allows `*` and `?` in host patterns.
        static func wildcardMatch(pattern: String, value: String) -> Bool {
            guard pattern.contains("*") || pattern.contains("?") else { return false }
            let regex = "^" + NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: "\\*", with: ".*")
                .replacingOccurrences(of: "\\?", with: ".") + "$"
            return value.range(of: regex, options: .regularExpression) != nil
        }
    }

    func entries() -> [Entry] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        return text.components(separatedBy: .newlines).compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            var fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            var marker: String? = nil
            if fields.first == "@cert-authority" || fields.first == "@revoked" { marker = fields.removeFirst() }
            guard fields.count >= 3 else { return nil }
            return Entry(hosts: fields[0], keyType: fields[1], keyBase64: fields[2], marker: marker)
        }
    }
}

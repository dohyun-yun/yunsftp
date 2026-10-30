import Foundation
import AppKit

public struct RemoteFileItem: Identifiable, Hashable, Sendable {
    public var id: String { remotePath }
    public let name: String
    public let remotePath: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let size: Int64
    public let modificationDate: Date
    public let permissions: String
    public let fileExtension: String

    public init(name: String, remotePath: String, isDirectory: Bool, isSymlink: Bool = false, size: Int64, modificationDate: Date, permissions: String) {
        let nfcName = SFTPService.decodeLsEscapes(name).precomposedStringWithCanonicalMapping
        let nfcRemotePath = SFTPService.decodeLsEscapes(remotePath).precomposedStringWithCanonicalMapping
        self.name = nfcName
        self.remotePath = nfcRemotePath
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.size = size
        self.modificationDate = modificationDate
        self.permissions = permissions
        self.fileExtension = (nfcName as NSString).pathExtension.lowercased()
    }

    public var formattedSize: String {
        if isDirectory { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: modificationDate)
    }

    // Convert to FileItem with virtual sftp URL
    public func toFileItem(connection: RemoteConnection) -> FileItem {
        let cleanPath = remotePath.hasPrefix("/") ? remotePath : "/\(remotePath)"
        let virtualURL = SFTPService.sftpURL(host: connection.host, port: connection.port, path: cleanPath)

        return FileItem(
            virtualURL: virtualURL,
            name: name,
            isDirectory: isDirectory,
            isSymlink: isSymlink,
            size: size,
            modificationDate: modificationDate,
            permissions: permissions
        )
    }
}

/// Tracks the ssh/sftp/scp child processes currently running so a user cancel can stop them.
public final class ProcessRegistry: @unchecked Sendable {
    public static let shared = ProcessRegistry()
    private let lock = NSLock()
    private var processes: [ObjectIdentifier: Process] = [:]

    // Keyed by object identity so registering before run() is safe even if the child exits
    // (and the termination handler fires) immediately.
    func register(_ p: Process) { lock.lock(); processes[ObjectIdentifier(p)] = p; lock.unlock() }
    func unregister(_ p: Process) { lock.lock(); processes.removeValue(forKey: ObjectIdentifier(p)); lock.unlock() }

    /// Sends SIGTERM to every running child. Returns how many were signalled.
    @discardableResult
    public func terminateAll() -> Int {
        lock.lock()
        let running = Array(processes.values)
        lock.unlock()
        running.forEach { if $0.isRunning { $0.terminate() } }
        return running.count
    }
}

public actor SFTPService {
    public static let shared = SFTPService()

    /// Normalizes a remote path: decodes escapes, converts to NFC, collapses multiple slashes, and strips trailing slash
    public static func normalizeRemotePath(_ path: String) -> String {
        let decoded = decodeLsEscapes(path).precomposedStringWithCanonicalMapping
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" {
            return "/"
        }
        let segments = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if segments.isEmpty {
            return "/"
        }
        return "/" + segments.joined(separator: "/")
    }

    /// Creates a safely percent-encoded sftp:// URL that preserves Unicode/Korean characters
    public static func sftpURL(host: String, port: Int, path: String) -> URL {
        let cleanPath = normalizeRemotePath(path)

        var components = URLComponents()
        components.scheme = "sftp"
        components.host = host
        components.port = port
        components.percentEncodedPath = cleanPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanPath

        if let url = components.url {
            return url
        }
        return URL(fileURLWithPath: cleanPath)
    }

    /// "name.ext" -> "name 2.ext", "name 3.ext", ... until it is not in `existing`.
    /// Mirrors the local copy behaviour so SFTP transfers never silently overwrite.
    public static func uniqueName(_ name: String, existing: Set<String>) -> String {
        guard existing.contains(name) else { return name }
        let ext = (name as NSString).pathExtension
        let base = (name as NSString).deletingPathExtension
        var count = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(count)" : "\(base) \(count).\(ext)"
            if !existing.contains(candidate) { return candidate }
            count += 1
        }
    }

    /// POSIX single-quote escaping for remote SSH commands
    public static func posixShellEscape(_ string: String) -> String {
        return "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Double-quote escaping for OpenSSH SFTP batch commands
    public static func sftpQuote(_ string: String) -> String {
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Decodes octal escape sequences (e.g. \355\205\214), hex escapes (\xHH), and C-style escapes (\n, \t, etc.)
    /// emitted by `ls` or OpenSSH `sftp` when running in C/POSIX or non-UTF8 environments.
    public static func decodeLsEscapes(_ string: String) -> String {
        guard string.contains("\\") else { return string.precomposedStringWithCanonicalMapping }
        var utf8Bytes: [UInt8] = []
        let chars = Array(string.utf8)
        var i = 0
        let count = chars.count
        while i < count {
            if chars[i] == UInt8(ascii: "\\") && i + 1 < count {
                // 3-digit octal escape \ooo
                if i + 3 < count &&
                   (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(chars[i + 1]) &&
                   (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(chars[i + 2]) &&
                   (UInt8(ascii: "0")...UInt8(ascii: "7")).contains(chars[i + 3]) {
                    let o1 = chars[i + 1] - UInt8(ascii: "0")
                    let o2 = chars[i + 2] - UInt8(ascii: "0")
                    let o3 = chars[i + 3] - UInt8(ascii: "0")
                    let byteVal = (o1 << 6) | (o2 << 3) | o3
                    utf8Bytes.append(byteVal)
                    i += 4
                    continue
                }
                // 2-digit hex escape \xHH
                if chars[i + 1] == UInt8(ascii: "x") && i + 3 < count {
                    let hexStr = String(decoding: [chars[i + 2], chars[i + 3]], as: UTF8.self)
                    if let byteVal = UInt8(hexStr, radix: 16) {
                        utf8Bytes.append(byteVal)
                        i += 4
                        continue
                    }
                }
                // C-style escapes
                switch chars[i + 1] {
                case UInt8(ascii: "a"): utf8Bytes.append(0x07); i += 2
                case UInt8(ascii: "b"): utf8Bytes.append(0x08); i += 2
                case UInt8(ascii: "t"): utf8Bytes.append(0x09); i += 2
                case UInt8(ascii: "n"): utf8Bytes.append(0x0A); i += 2
                case UInt8(ascii: "v"): utf8Bytes.append(0x0B); i += 2
                case UInt8(ascii: "f"): utf8Bytes.append(0x0C); i += 2
                case UInt8(ascii: "r"): utf8Bytes.append(0x0D); i += 2
                case UInt8(ascii: "\\"): utf8Bytes.append(UInt8(ascii: "\\")); i += 2
                case UInt8(ascii: "\""): utf8Bytes.append(UInt8(ascii: "\"")); i += 2
                case UInt8(ascii: "'"): utf8Bytes.append(UInt8(ascii: "'")); i += 2
                case UInt8(ascii: " "): utf8Bytes.append(UInt8(ascii: " ")); i += 2
                default:
                    utf8Bytes.append(chars[i])
                    i += 1
                }
            } else {
                utf8Bytes.append(chars[i])
                i += 1
            }
        }
        if let decoded = String(bytes: utf8Bytes, encoding: .utf8) {
            return decoded.precomposedStringWithCanonicalMapping
        }
        return String(decoding: utf8Bytes, as: UTF8.self).precomposedStringWithCanonicalMapping
    }

    /// Shared OpenSSH options. Host keys are verified against the default known_hosts file
    /// (trust-on-first-use via `accept-new`); algorithms are left at OpenSSH defaults.
    /// Sessions are multiplexed through a ControlMaster socket so each operation does not
    /// pay for a new handshake + authentication.
    static let controlPath: String = (NSTemporaryDirectory() as NSString).appendingPathComponent("ys-%C")

    static var commonSSHOptions: [String] {
        return [
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "PreferredAuthentications=publickey,password,keyboard-interactive",
            "-o", "NumberOfPasswordPrompts=1",
            "-o", "BatchMode=no",
            "-o", "ControlMaster=auto",
            "-o", "ControlPath=\(controlPath)",
            "-o", "ControlPersist=60"
        ]
    }

    public func listDirectory(path: String, connection: RemoteConnection, password: String?) async throws -> [RemoteFileItem] {
        guard !connection.host.isEmpty else {
            throw NSError(domain: "SFTPService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid host address"])
        }

        let targetPath = Self.normalizeRemotePath(path)

        // 1. Primary approach: SFTP Batch using 'cd' then bare 'ls -la' with -o BatchMode=no
        // This natively respects SFTP root/chroot shares (e.g. /video on Synology) and works for Korean, spaces, brackets, etc.
        do {
            let sftpCommands: [String]
            if targetPath == "/" {
                sftpCommands = ["cd /", "ls -la"]
            } else {
                sftpCommands = [
                    "cd \(Self.sftpQuote(targetPath))",
                    "ls -la"
                ]
            }
            let sftpOutput = try await executeSFTPBatch(commands: sftpCommands, connection: connection, password: password)
            let items = parseLsOutput(sftpOutput, parentPath: targetPath)
            if !items.isEmpty || sftpOutput.contains("total") || sftpOutput.contains("drwx") || sftpOutput.contains("-rw") || sftpOutput.contains("sftp>") {
                return items
            }
        } catch where !Self.isAuthenticationFailure(error) {
            // If cd failed in SFTP, try direct 'ls -la "path"' via SFTP batch
            do {
                let fallbackOutput = try await executeSFTPBatch(commands: ["ls -la \(Self.sftpQuote(targetPath))"], connection: connection, password: password)
                let items = parseLsOutput(fallbackOutput, parentPath: targetPath)
                if !items.isEmpty || fallbackOutput.contains("total") || fallbackOutput.contains("drwx") || fallbackOutput.contains("-rw") || fallbackOutput.contains("sftp>") {
                    return items
                }
            } catch where !Self.isAuthenticationFailure(error) {
                if connection.host == "local-sftp-server" {
                    throw error
                }
                // If SFTP batch failed on remote, proceed to direct SSH ls fallback
            }
        }

        // 2. Direct SSH ls command with UTF-8 locale and POSIX quoting (for servers with direct shell access)
        let sshCmd = "export LC_ALL=en_US.utf8 LANG=en_US.utf8 2>/dev/null || export LC_ALL=ko_KR.utf8 LANG=ko_KR.utf8 2>/dev/null || export LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 2>/dev/null || export LC_ALL=C.UTF-8 LANG=C.UTF-8 2>/dev/null; ls -la \(Self.posixShellEscape(targetPath))"
        let output = try await executeSSH(command: sshCmd, connection: connection, password: password)
        return parseLsOutput(output, parentPath: targetPath)
    }

    public func resolvePassword(password: String?, connection: RemoteConnection) -> String? {
        if let pwd = password, !pwd.isEmpty {
            return pwd
        }
        if connection.authType == .password {
            return KeychainService.shared.loadPassword(for: connection)
        }
        return nil
    }

    /// Downloads `remotePath` into `localDirectory`. Unless `overwrite` is set, an existing
    /// local item with the same name is kept and the download gets a " 2" suffix.
    public func download(remotePath: String, to localDirectory: URL, connection: RemoteConnection, password: String?, overwrite: Bool = false) async throws -> URL {
        let cleanRemotePath = Self.normalizeRemotePath(remotePath)
        let fileName = (cleanRemotePath as NSString).lastPathComponent
        let parentDir = (cleanRemotePath as NSString).deletingLastPathComponent
        let remoteParent = parentDir.isEmpty ? "/" : parentDir
        let effectivePwd = resolvePassword(password: password, connection: connection)

        try? FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)

        let localNames = Set(((try? FileManager.default.contentsOfDirectory(atPath: localDirectory.path)) ?? []).map { $0.precomposedStringWithCanonicalMapping })
        let destName = overwrite ? fileName : Self.uniqueName(fileName, existing: localNames)
        let localDestURL = localDirectory.appendingPathComponent(destName)

        let destPath = localDestURL.path.precomposedStringWithCanonicalMapping

        // 1. Primary: SFTP batch using lcd (local dest) + cd (remote parent) + get -R (filename)
        let sftpCommands: [String] = [
            "lcd \(Self.sftpQuote(localDirectory.path))",
            "cd \(Self.sftpQuote(remoteParent))",
            "get -R \(Self.sftpQuote(fileName)) \(Self.sftpQuote(destName))"
        ]
        do {
            _ = try await executeSFTPBatch(commands: sftpCommands, connection: connection, password: effectivePwd)
        } catch where !Self.isAuthenticationFailure(error) {
            if FileManager.default.fileExists(atPath: destPath) || FileManager.default.fileExists(atPath: localDestURL.path) {
                return localDestURL
            }
        }
        if FileManager.default.fileExists(atPath: destPath) || FileManager.default.fileExists(atPath: localDestURL.path) {
            return localDestURL
        }

        // 2. Direct get with quotes if remoteParent cd failed
        let directCmds = [
            "lcd \(Self.sftpQuote(localDirectory.path))",
            "get -R \(Self.sftpQuote(cleanRemotePath)) \(Self.sftpQuote(destName))"
        ]
        do {
            _ = try await executeSFTPBatch(commands: directCmds, connection: connection, password: effectivePwd)
        } catch where !Self.isAuthenticationFailure(error) {
            if FileManager.default.fileExists(atPath: destPath) || FileManager.default.fileExists(atPath: localDestURL.path) {
                return localDestURL
            }
        }
        if FileManager.default.fileExists(atPath: destPath) || FileManager.default.fileExists(atPath: localDestURL.path) {
            return localDestURL
        }

        // 3. Fallback to scp (quoting remoteSpec for remote shell execution)
        var args = ["-P", "\(connection.port)"]
        args.append(contentsOf: Self.commonSSHOptions)

        if connection.authType == .sshKey && !connection.keyFilePath.isEmpty {
            let expandedKey = (connection.keyFilePath as NSString).expandingTildeInPath
            args.append(contentsOf: ["-i", expandedKey])
        }

        let userPart = connection.username.isEmpty ? "" : "\(connection.username)@"
        let remoteSpec = "\(userPart)\(connection.host):\(Self.posixShellEscape(cleanRemotePath))"
        args.append(contentsOf: ["-r", remoteSpec, localDestURL.path])

        _ = try await runProcess(executable: "/usr/bin/scp", arguments: args, password: effectivePwd)

        if !FileManager.default.fileExists(atPath: destPath) && !FileManager.default.fileExists(atPath: localDestURL.path) {
            throw NSError(domain: "SFTPService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Download failed: \(fileName) was not written to the local destination."
            ])
        }
        return localDestURL
    }

    /// Uploads `localURL` into `remoteDirectoryPath`. Unless `overwrite` is set, an existing
    /// remote item with the same name is kept and the upload gets a " 2" suffix.
    public func upload(localURL: URL, to remoteDirectoryPath: String, connection: RemoteConnection, password: String?, overwrite: Bool = false) async throws {
        let cleanRemoteDir = Self.normalizeRemotePath(remoteDirectoryPath)
        let fileName = localURL.lastPathComponent.precomposedStringWithCanonicalMapping
        let localParentDir = localURL.deletingLastPathComponent().path
        let effectivePwd = resolvePassword(password: password, connection: connection)

        var remoteName = fileName
        if !overwrite {
            let siblings = (try? await listDirectory(path: cleanRemoteDir, connection: connection, password: effectivePwd)) ?? []
            remoteName = Self.uniqueName(fileName, existing: Set(siblings.map { $0.name }))
        }
        let remoteDest = cleanRemoteDir == "/" ? "/\(remoteName)" : "\(cleanRemoteDir)/\(remoteName)"

        // 1. Primary: SFTP batch using lcd (local parent) + cd (remote dir) + put -R (filename)
        let sftpCommands: [String] = [
            "lcd \(Self.sftpQuote(localParentDir))",
            "cd \(Self.sftpQuote(cleanRemoteDir))",
            "put -R \(Self.sftpQuote(fileName)) \(Self.sftpQuote(remoteName))"
        ]
        do {
            _ = try await executeSFTPBatch(commands: sftpCommands, connection: connection, password: effectivePwd)
        } catch where !Self.isAuthenticationFailure(error) {
            // 2. Direct put with remote path
            let directCmds = [
                "lcd \(Self.sftpQuote(localParentDir))",
                "put -R \(Self.sftpQuote(fileName)) \(Self.sftpQuote(remoteDest))"
            ]
            do {
                _ = try await executeSFTPBatch(commands: directCmds, connection: connection, password: effectivePwd)
            } catch where !Self.isAuthenticationFailure(error) {
                // 3. Fallback to scp (quoting remoteDest for remote shell execution)
                var args = ["-P", "\(connection.port)"]
                args.append(contentsOf: Self.commonSSHOptions)

                if connection.authType == .sshKey && !connection.keyFilePath.isEmpty {
                    let expandedKey = (connection.keyFilePath as NSString).expandingTildeInPath
                    args.append(contentsOf: ["-i", expandedKey])
                }

                let userPart = connection.username.isEmpty ? "" : "\(connection.username)@"
                let remoteSpec = "\(userPart)\(connection.host):\(Self.posixShellEscape(remoteDest))"
                args.append(contentsOf: ["-r", localURL.path, remoteSpec])

                _ = try await runProcess(executable: "/usr/bin/scp", arguments: args, password: effectivePwd)
            }
        }
    }

    public func createDirectory(remotePath: String, connection: RemoteConnection, password: String?) async throws {
        let effectivePwd = resolvePassword(password: password, connection: connection)
        let nfc = Self.normalizeRemotePath(remotePath)
        let parent = (nfc as NSString).deletingLastPathComponent
        let dirName = (nfc as NSString).lastPathComponent
        let cleanParent = parent.isEmpty ? "/" : parent

        // 1. Primary: SFTP batch (cd parent + mkdir) so chroot paths are respected
        let cmds = [
            "cd \(Self.sftpQuote(cleanParent))",
            "mkdir \(Self.sftpQuote(dirName))"
        ]
        do {
            _ = try await executeSFTPBatch(commands: cmds, connection: connection, password: effectivePwd)
            return
        } catch where !Self.isAuthenticationFailure(error) {
            do {
                _ = try await executeSFTPBatch(commands: ["mkdir \(Self.sftpQuote(nfc))"], connection: connection, password: effectivePwd)
                return
            } catch where !Self.isAuthenticationFailure(error) {
                if connection.host == "local-sftp-server" {
                    throw error
                }
                let cmd = "test -d \(Self.posixShellEscape(cleanParent)) && mkdir -p \(Self.posixShellEscape(nfc))"
                _ = try await executeSSH(command: cmd, connection: connection, password: effectivePwd)
            }
        }
    }

    public func remove(remotePath: String, isDirectory: Bool, connection: RemoteConnection, password: String?) async throws {
        let effectivePwd = resolvePassword(password: password, connection: connection)
        let nfc = Self.normalizeRemotePath(remotePath)
        let parent = (nfc as NSString).deletingLastPathComponent
        let targetName = (nfc as NSString).lastPathComponent
        let cleanParent = parent.isEmpty ? "/" : parent

        // 1. Primary: SFTP batch (respects SFTP chroot such as Synology NAS /video, /home, etc.)
        if !isDirectory {
            let cdRmCmds = [
                "cd \(Self.sftpQuote(cleanParent))",
                "rm \(Self.sftpQuote(targetName))"
            ]
            do {
                _ = try await executeSFTPBatch(commands: cdRmCmds, connection: connection, password: effectivePwd)
                return
            } catch where !Self.isAuthenticationFailure(error) {
                _ = try await executeSFTPBatch(commands: ["rm \(Self.sftpQuote(nfc))"], connection: connection, password: effectivePwd)
                return
            }
        } else {
            let cdRmdirCmds = [
                "cd \(Self.sftpQuote(cleanParent))",
                "rmdir \(Self.sftpQuote(targetName))"
            ]
            do {
                _ = try await executeSFTPBatch(commands: cdRmdirCmds, connection: connection, password: effectivePwd)
                return
            } catch where !Self.isAuthenticationFailure(error) {
                // Deletion stays inside the SFTP subsystem on purpose: no recursive shell removal.
                try await removeDirectoryRecursivelySFTP(remotePath: nfc, connection: connection, password: effectivePwd)
            }
        }
    }

    public func removeDirectoryRecursivelySFTP(remotePath: String, connection: RemoteConnection, password: String?) async throws {
        let nfc = Self.normalizeRemotePath(remotePath)
        let items = (try? await listDirectory(path: nfc, connection: connection, password: password)) ?? []

        let subdirs = items.filter { $0.isDirectory && !$0.isSymlink }
        let files = items.filter { !$0.isDirectory || $0.isSymlink }

        // 1. Recursively remove subdirectories
        for subdir in subdirs {
            try await removeDirectoryRecursivelySFTP(remotePath: subdir.remotePath, connection: connection, password: password)
        }

        // 2. Batch-remove all files in this directory in a single SFTP session
        if !files.isEmpty {
            var batchCmds = ["cd \(Self.sftpQuote(nfc))"]
            for f in files {
                batchCmds.append("rm \(Self.sftpQuote(f.name))")
            }
            do {
                _ = try await executeSFTPBatch(commands: batchCmds, connection: connection, password: password)
            } catch where !Self.isAuthenticationFailure(error) {
                // Fallback to individual removal if batch had a hiccup
                for f in files {
                    try await remove(remotePath: f.remotePath, isDirectory: false, connection: connection, password: password)
                }
            }
        }

        // 3. Remove the now-empty directory itself
        let parent = (nfc as NSString).deletingLastPathComponent
        let targetName = (nfc as NSString).lastPathComponent
        let cleanParent = parent.isEmpty ? "/" : parent
        let cmds = [
            "cd \(Self.sftpQuote(cleanParent))",
            "rmdir \(Self.sftpQuote(targetName))"
        ]
        do {
            _ = try await executeSFTPBatch(commands: cmds, connection: connection, password: password)
        } catch where !Self.isAuthenticationFailure(error) {
            _ = try await executeSFTPBatch(commands: ["rmdir \(Self.sftpQuote(nfc))"], connection: connection, password: password)
        }
    }

    public func rename(remotePath: String, to newRemotePath: String, connection: RemoteConnection, password: String?) async throws {
        let effectivePwd = resolvePassword(password: password, connection: connection)
        let nfcSrc = Self.normalizeRemotePath(remotePath)
        let nfcDst = Self.normalizeRemotePath(newRemotePath)

        let parentSrc = (nfcSrc as NSString).deletingLastPathComponent
        let parentDst = (nfcDst as NSString).deletingLastPathComponent
        let nameSrc = (nfcSrc as NSString).lastPathComponent
        let nameDst = (nfcDst as NSString).lastPathComponent
        let cleanParent = parentSrc.isEmpty ? "/" : parentSrc

        // 1. Primary: SFTP batch (cd parent + rename oldName newName when in same directory)
        if parentSrc == parentDst {
            let cmds = [
                "cd \(Self.sftpQuote(cleanParent))",
                "rename \(Self.sftpQuote(nameSrc)) \(Self.sftpQuote(nameDst))"
            ]
            do {
                _ = try await executeSFTPBatch(commands: cmds, connection: connection, password: effectivePwd)
                return
            } catch where !Self.isAuthenticationFailure(error) {
                // Fallback to full path rename below
            }
        }

        do {
            _ = try await executeSFTPBatch(commands: ["rename \(Self.sftpQuote(nfcSrc)) \(Self.sftpQuote(nfcDst))"], connection: connection, password: effectivePwd)
            return
        } catch where !Self.isAuthenticationFailure(error) {
            if connection.host == "local-sftp-server" {
                throw error
            }
            let cmd = "test -e \(Self.posixShellEscape(nfcSrc)) && mv \(Self.posixShellEscape(nfcSrc)) \(Self.posixShellEscape(nfcDst))"
            _ = try await executeSSH(command: cmd, connection: connection, password: effectivePwd)
        }
    }

    public func chmod(remotePath: String, mode: String, recursive: Bool = false, connection: RemoteConnection, password: String?) async throws {
        let effectivePwd = resolvePassword(password: password, connection: connection)
        let nfc = Self.normalizeRemotePath(remotePath)
        let parent = (nfc as NSString).deletingLastPathComponent
        let targetName = (nfc as NSString).lastPathComponent
        let cleanParent = parent.isEmpty ? "/" : parent

        if !recursive {
            let cmds = [
                "cd \(Self.sftpQuote(cleanParent))",
                "chmod \(mode) \(Self.sftpQuote(targetName))"
            ]
            do {
                _ = try await executeSFTPBatch(commands: cmds, connection: connection, password: effectivePwd)
                return
            } catch where !Self.isAuthenticationFailure(error) {
                do {
                    _ = try await executeSFTPBatch(commands: ["chmod \(mode) \(Self.sftpQuote(nfc))"], connection: connection, password: effectivePwd)
                    return
                } catch where !Self.isAuthenticationFailure(error) {
                    if connection.host == "local-sftp-server" {
                        throw error
                    }
                }
            }
        }

        if connection.host == "local-sftp-server" {
            _ = try await executeSFTPBatch(commands: ["chmod \(mode) \(Self.sftpQuote(nfc))"], connection: connection, password: effectivePwd)
            return
        }

        let recFlag = recursive ? "-R " : ""
        let cmd = "test -e \(Self.posixShellEscape(nfc)) && chmod \(recFlag)\(mode) \(Self.posixShellEscape(nfc))"
        do {
            _ = try await executeSSH(command: cmd, connection: connection, password: effectivePwd)
        } catch where !Self.isAuthenticationFailure(error) {
            _ = try await executeSFTPBatch(commands: ["chmod \(mode) \(Self.sftpQuote(nfc))"], connection: connection, password: effectivePwd)
        }
    }

    public func duplicate(remotePath: String, isDirectory: Bool, connection: RemoteConnection, password: String?) async throws -> String {
        let effectivePwd = resolvePassword(password: password, connection: connection)
        let nfc = Self.normalizeRemotePath(remotePath)
        let parent = (nfc as NSString).deletingLastPathComponent
        let cleanParent = parent.isEmpty ? "/" : parent
        let fileName = (nfc as NSString).lastPathComponent
        let baseName = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension

        let siblings = (try? await listDirectory(path: cleanParent, connection: connection, password: effectivePwd)) ?? []
        let existingNames = Set(siblings.map { $0.name })

        var copyName = ext.isEmpty ? "\(baseName) copy" : "\(baseName) copy.\(ext)"
        var count = 2
        while existingNames.contains(copyName) {
            copyName = ext.isEmpty ? "\(baseName) copy \(count)" : "\(baseName) copy \(count).\(ext)"
            count += 1
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("yunsftpDup_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let downloadedURL = try await download(remotePath: nfc, to: tempDir, connection: connection, password: effectivePwd)
        let renamedTempURL = tempDir.appendingPathComponent(copyName)
        if downloadedURL != renamedTempURL {
            try FileManager.default.moveItem(at: downloadedURL, to: renamedTempURL)
        }

        try await upload(localURL: renamedTempURL, to: cleanParent, connection: connection, password: effectivePwd)
        return cleanParent == "/" ? "/\(copyName)" : "\(cleanParent)/\(copyName)"
    }

    private func executeSSH(command: String, connection: RemoteConnection, password: String?) async throws -> String {
        let effectivePwd = resolvePassword(password: password, connection: connection)
        var args = ["-p", "\(connection.port)"]
        args.append(contentsOf: Self.commonSSHOptions)

        if connection.authType == .sshKey && !connection.keyFilePath.isEmpty {
            let expandedKey = (connection.keyFilePath as NSString).expandingTildeInPath
            args.append(contentsOf: ["-i", expandedKey])
        }

        let userPart = connection.username.isEmpty ? "" : "\(connection.username)@"
        args.append("\(userPart)\(connection.host)")
        args.append(command)

        return try await runProcess(executable: "/usr/bin/ssh", arguments: args, password: effectivePwd)
    }

    private func executeSFTPBatch(commands: [String], connection: RemoteConnection, password: String?) async throws -> String {
        let effectivePwd = resolvePassword(password: password, connection: connection)
        var args: [String] = []
        if connection.host == "local-sftp-server" {
            let sftpServerPath = FileManager.default.fileExists(atPath: "/usr/libexec/sftp-server") ? "/usr/libexec/sftp-server" : "/usr/sbin/sshd"
            args.append(contentsOf: ["-D", sftpServerPath, "-b", "-", "dummy"])
        } else {
            args.append(contentsOf: ["-P", "\(connection.port)"])
            args.append(contentsOf: Self.commonSSHOptions)
            args.append(contentsOf: ["-b", "-"])

            if connection.authType == .sshKey && !connection.keyFilePath.isEmpty {
                let expandedKey = (connection.keyFilePath as NSString).expandingTildeInPath
                args.append(contentsOf: ["-i", expandedKey])
            }

            let userPart = connection.username.isEmpty ? "" : "\(connection.username)@"
            args.append("\(userPart)\(connection.host)")
        }

        let inputString = commands.joined(separator: "\n") + "\nexit\n"
        return try await runProcess(executable: "/usr/bin/sftp", arguments: args, inputData: inputString.data(using: .utf8), password: effectivePwd)
    }

    /// Creates the SSH_ASKPASS helper in the per-user temp dir. The file is created in one
    /// step with mode 0700 (no window where it is world-readable) and removed after the
    /// process exits. The password is base64-wrapped only to survive shell quoting.
    static func writeAskpassScript(password: String) throws -> URL {
        let base64Pwd = Data(password.utf8).base64EncodedString()
        let script = "#!/bin/sh\necho \"\(base64Pwd)\" | /usr/bin/base64 -d\n"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("askpass_\(UUID().uuidString).sh")
        guard FileManager.default.createFile(atPath: url.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o700]) else {
            throw NSError(domain: "SFTPService", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create the password helper"])
        }
        return url
    }

    func runProcess(executable: String, arguments: [String], inputData: Data? = nil, password: String?) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        environment["LANG"] = "en_US.UTF-8"
        environment["LC_ALL"] = "en_US.UTF-8"
        environment["LC_CTYPE"] = "UTF-8"
        var tempAskPassURL: URL? = nil

        // If password is provided, hand it to ssh through a one-shot SSH_ASKPASS helper
        if let pwd = password, !pwd.isEmpty {
            let tmpScript = try Self.writeAskpassScript(password: pwd)
            tempAskPassURL = tmpScript

            environment["SSH_ASKPASS"] = tmpScript.path
            environment["SSH_ASKPASS_REQUIRE"] = "force"
            environment["DISPLAY"] = ":0"
        }

        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        final class ProcessState: @unchecked Sendable {
            var resumed = false
            let lock = NSLock()
        }
        let procState = ProcessState()

        let stdoutTask = Task.detached {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        let stderrTask = Task.detached {
            stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { p in
                    ProcessRegistry.shared.unregister(p)
                    procState.lock.lock()
                    defer { procState.lock.unlock() }
                    if !procState.resumed {
                        procState.resumed = true
                        continuation.resume()
                    }
                }
                do {
                    ProcessRegistry.shared.register(process)
                    try process.run()
                    if let input = inputData {
                        stdinPipe.fileHandleForWriting.write(input)
                    }
                    try? stdinPipe.fileHandleForWriting.close()
                } catch {
                    ProcessRegistry.shared.unregister(process)
                    procState.lock.lock()
                    defer { procState.lock.unlock() }
                    if !procState.resumed {
                        procState.resumed = true
                        continuation.resume(throwing: error)
                    }
                }
            }

            let outData = await stdoutTask.value
            let errData = await stderrTask.value

            if let tmp = tempAskPassURL {
                try? FileManager.default.removeItem(at: tmp)
            }

            let output = String(data: outData, encoding: .utf8) ?? ""
            let errorMsg = String(data: errData, encoding: .utf8) ?? ""

            if process.terminationStatus != 0 {
                let cleanErr = errorMsg.components(separatedBy: .newlines)
                    .filter { !$0.contains("WARNING") && !$0.isEmpty }
                    .joined(separator: " ")
                let friendly = Self.translateErrorMessage(cleanErr, exitCode: Int(process.terminationStatus))
                let code = Self.isAuthenticationFailureText(cleanErr) ? Self.authenticationFailureCode : Int(process.terminationStatus)
                throw NSError(domain: "SFTPService", code: code, userInfo: [
                    NSLocalizedDescriptionKey: friendly
                ])
            }

            return output
        } catch {
            if let tmp = tempAskPassURL {
                try? FileManager.default.removeItem(at: tmp)
            }
            throw error
        }
    }

    /// Error code used when the SSH server rejected the credentials. Callers must not retry
    /// with alternative transports on this error: every retry is another failed login that
    /// can trigger fail2ban / NAS auto-block.
    static let authenticationFailureCode = -1001

    static func isAuthenticationFailure(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == "SFTPService" && ns.code == authenticationFailureCode
    }

    static func isAuthenticationFailureText(_ rawError: String) -> Bool {
        let lower = rawError.lowercased()
        return lower.contains("permission denied (publickey") ||
            lower.contains("permission denied (password") ||
            lower.contains("permission denied (keyboard-interactive") ||
            lower.contains("authentication failed") ||
            lower.contains("too many authentication failures")
    }

    static func translateErrorMessage(_ rawError: String, exitCode: Int) -> String {
        let lower = rawError.lowercased()

        // 0. Host key mismatch (possible MITM or reinstalled server)
        if lower.contains("remote host identification has changed") || lower.contains("host key verification failed") {
            return "Host key verification failed: the server's key does not match the one saved in ~/.ssh/known_hosts. If the server was reinstalled, remove its entry with `ssh-keygen -R <host>`; otherwise the connection may be intercepted."
        }

        // 1. Connection-level errors
        if lower.contains("connection reset") {
            return "The server closed the connection (connection reset). Check the credentials, SFTP port and firewall settings."
        } else if lower.contains("connection refused") {
            return "Connection refused. Check that the SSH/SFTP service is running and the port number is correct."
        } else if lower.contains("timed out") || lower.contains("timeout") {
            return "Connection timed out. Check the server address and your network connection."
        } else if lower.contains("host is down") || lower.contains("no route to host") {
            return "Host unreachable (no route to host)."
        }

        // 2. Authentication failure (strictly when SSH/SFTP rejects login credentials)
        if isAuthenticationFailureText(rawError) {
            return "Authentication failed: the username or password is incorrect (permission denied)."
        }

        // 3. File or Directory permission denial (e.g. ls, cd, get, put failed due to filesystem permissions)
        if lower.contains("permission denied") {
            return "Permission denied. Check the read/write permissions of the target file or folder."
        }

        // 4. File or Directory not found
        if lower.contains("no such file or directory") || lower.contains("couldn't stat") || lower.contains("not found") {
            return "Path not found (no such file or directory). The folder may have been moved or renamed."
        }

        return rawError.isEmpty ? "SSH/SFTP command failed (exit code \(exitCode))" : rawError
    }

    static func extractLsColumns(from line: String) -> (tokens: [Substring], fileName: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        var tokens: [Substring] = []
        var idx = trimmed.startIndex
        let end = trimmed.endIndex

        while idx < end && tokens.count < 8 {
            while idx < end && (trimmed[idx] == " " || trimmed[idx] == "\t") {
                idx = trimmed.index(after: idx)
            }
            guard idx < end else { break }
            let tokenStart = idx
            while idx < end && trimmed[idx] != " " && trimmed[idx] != "\t" {
                idx = trimmed.index(after: idx)
            }
            tokens.append(trimmed[tokenStart..<idx])
        }

        guard tokens.count == 8, idx < end else { return nil }
        if trimmed[idx] == " " || trimmed[idx] == "\t" {
            idx = trimmed.index(after: idx)
        }
        guard idx < end else { return nil }
        let fileName = String(trimmed[idx..<end])
        return (tokens, fileName)
    }

    private func parseLsOutput(_ output: String, parentPath: String) -> [RemoteFileItem] {
        var items: [RemoteFileItem] = []
        let lines = output.components(separatedBy: .newlines)
        let normalizedParent = Self.normalizeRemotePath(parentPath)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("total") || trimmed.hasPrefix("sftp>") {
                continue
            }

            // Standard ls -la format:
            // drwxr-xr-x  14 finsternis staff  448 Oct 11 12:34 FolderName
            guard let extracted = Self.extractLsColumns(from: trimmed) else { continue }
            let parts = extracted.tokens
            var name = extracted.fileName

            let perms = String(parts[0])
            let isDir = perms.hasPrefix("d")
            let isLink = perms.hasPrefix("l")
            let size = Int64(parts[4]) ?? 0

            // Handle symlinks: "linkName -> targetPath"
            if let arrowRange = name.range(of: " -> ") {
                name = String(name[..<arrowRange.lowerBound])
            }

            // Handle quoted filenames from GNU ls
            if (name.hasPrefix("'") && name.hasSuffix("'")) || (name.hasPrefix("\"") && name.hasSuffix("\"")) {
                if name.count >= 2 {
                    name = String(name.dropFirst().dropLast())
                }
            }

            // Decode octal, hex, and C-style escape sequences (e.g. \355\205\214)
            name = Self.decodeLsEscapes(name).precomposedStringWithCanonicalMapping
            if name == "." || name == ".." {
                continue
            }

            let fullRemotePath: String
            if normalizedParent == "/" {
                fullRemotePath = "/\(name)"
            } else {
                fullRemotePath = "\(normalizedParent)/\(name)"
            }

            // Parse date if possible (parts 5, 6, 7)
            let dateStr = "\(parts[5]) \(parts[6]) \(parts[7])"
            let modDate = Self.parseLsDate(dateStr, now: Date()) ?? Date()

            let item = RemoteFileItem(
                name: name,
                remotePath: fullRemotePath.precomposedStringWithCanonicalMapping,
                isDirectory: isDir,
                isSymlink: isLink,
                size: size,
                modificationDate: modDate,
                permissions: perms
            )
            items.append(item)
        }

        return items
    }

    static func parseLsDate(_ string: String, now: Date) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // Format 1: "Oct 13 14:00" (ls omits the year for the last ~6 months). Assume the
        // current year, but a resulting date in the future means it was last year.
        formatter.dateFormat = "MMM d HH:mm"
        if let d = formatter.date(from: string) {
            let calendar = Calendar.current
            var components = calendar.dateComponents([.month, .day, .hour, .minute], from: d)
            components.year = calendar.component(.year, from: now)
            guard let candidate = calendar.date(from: components) else { return nil }
            if candidate > now.addingTimeInterval(86_400) {
                return calendar.date(byAdding: .year, value: -1, to: candidate)
            }
            return candidate
        }

        // Format 2: "Oct 13 2024"
        formatter.dateFormat = "MMM d yyyy"
        if let d = formatter.date(from: string) {
            return d
        }

        return nil
    }
}

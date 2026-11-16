import Darwin
import Foundation

/// A workspace may already contain hooks owned by the user. Only create a new
/// file or remove the exact configuration generated for this executable.
public struct GeminiWorkspaceHooks {
    public enum Status { case available, installed, occupied }
    public let contents: Data
    private let directory: URL
    private let file: URL

    public init(workspace: URL, executable: URL) throws {
        directory = workspace.resolvingSymlinksInPath().appendingPathComponent(".agents")
        file = directory.appendingPathComponent("hooks.json")
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let binary = quote(executable.path)
        let argument = quote(workspace.resolvingSymlinksInPath().path)
        var hooks: [String: [[String: Any]]] = [:]
        for event in ["PreInvocation", "Stop"] {
            hooks[event] = [["type": "command", "timeout": 2, "command": binary + " --gemini-hook " + event + " " + argument]]
        }
        contents = try JSONSerialization.data(withJSONObject: ["bamboo-pulse-gemini": hooks],
                                              options: [.sortedKeys, .prettyPrinted])
    }

    public func status() throws -> Status {
        var info = stat()
        if lstat(directory.path, &info) != 0 {
            if errno == ENOENT { return .available }
            throw POSIXError(.EACCES)
        }
        guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o022 == 0
        else { throw POSIXError(.EACCES) }
        return try status(of: file)
    }

    private func status(of target: URL) throws -> Status {
        var info = stat()
        let fd = open(target.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard fd >= 0 else {
            if errno == ENOENT { return .available }
            throw POSIXError(.EACCES)
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid(),
              info.st_mode & 0o022 == 0 else { throw POSIXError(.EACCES) }
        guard info.st_size == contents.count else { return .occupied }
        return try handle.read(upToCount: contents.count + 1) == contents ? .installed : .occupied
    }

    public func install() throws {
        if mkdir(directory.path, 0o700) != 0 && errno != EEXIST { throw POSIXError(.EACCES) }
        guard try status() == .available else { throw POSIXError(.EEXIST) }
        // Publish a complete inode exclusively; a concurrent creator always wins.
        let staging = directory.appendingPathComponent(".pulse-" + UUID().uuidString)
        try contents.write(to: staging, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: staging) }
        guard link(staging.path, file.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    public func remove() throws {
        guard try status() == .installed else { throw POSIXError(.EEXIST) }
        // Claim the file first, so an editor replacing hooks.json between the
        // check and removal can never cause its new configuration to be deleted.
        let claimed = directory.appendingPathComponent(".pulse-recovery-" + UUID().uuidString)
        try FileManager.default.moveItem(at: file, to: claimed)
        do {
            guard try status(of: claimed) == .installed else { throw POSIXError(.EBUSY) }
            try FileManager.default.removeItem(at: claimed)
        } catch {
            // An independently recreated hooks.json wins. Preserve both versions.
            if renamex_np(claimed.path, file.path, UInt32(RENAME_EXCL)) != 0 {
                throw NSError(domain: "GeminiHooks", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "The hooks file changed during removal. The concurrent file is preserved at " + claimed.path])
            }
            throw error
        }
    }
}

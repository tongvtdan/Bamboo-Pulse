import CoreFoundation
import CryptoKit
import Darwin
import Foundation

/// A local navigation target carried only by IDE events and retained in memory.
public struct GeminiDestination: Codable, Equatable, Sendable {
    public let conversationID: String
    public let workspace: String

    public var sessionID: String {
        let digest = SHA256.hash(data: Data(("gemini-ide/" + conversationID).utf8)).prefix(16)
            .map { String(format: "%02x", $0) }.joined()
        return "gemini:" + digest
    }

    public var url: URL? {
        guard UUID(uuidString: conversationID)?.uuidString.lowercased() == conversationID,
              workspace.hasPrefix("/"), workspace.utf8.count <= 1024,
              !workspace.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              URL(fileURLWithPath: workspace).standardizedFileURL.path == workspace else { return nil }
        var parts = URLComponents()
        parts.scheme = "antigravity-ide"
        parts.host = "google.google-antigravity"
        parts.path = "/open-conversation"
        parts.queryItems = [URLQueryItem(name: "cascadeId", value: conversationID),
                            URLQueryItem(name: "path", value: workspace)]
        return parts.url
    }
}

/// Reduces an IDE hook to a provider-scoped pseudonym and an observed state.
/// Never opens transcriptPath or sends the incoming JSON to the monitor.
public struct GeminiHook: Codable, Equatable {
    let id: String
    let state: SessionState
    let observed: Double
    var destination: GeminiDestination? = nil

    public static func project(_ data: Data, event: String, workspace: String, home: String, now: Double) -> Self? {
        guard ["PreInvocation", "Stop"].contains(event),
              let object = try? StrictJSON.object(data) as? [String: Any],
              let conversation = object["conversationId"] as? String,
              UUID(uuidString: conversation)?.uuidString.lowercased() == conversation,
              let model = object["modelName"] as? String, model.utf8.count <= 100,
              workspace.hasPrefix("/"), let paths = object["workspacePaths"] as? [String],
              paths.contains(workspace), let transcript = object["transcriptPath"] as? String
        else { return nil }
        let log = "/brain/" + conversation + "/.system_generated/logs/"
        let documented = home + "/.gemini/antigravity-ide" + log + "transcript.jsonl"
        let observed = home + "/.gemini/antigravity" + log + "transcript_full.jsonl"
        guard transcript == documented || transcript == observed else { return nil }
        let id = SHA256.hash(data: Data(("gemini-ide/" + conversation).utf8)).prefix(16)
            .map { String(format: "%02x", $0) }.joined()
        let gemini = model.lowercased().wholeMatch(of: /^gemini[- ][a-z0-9][a-z0-9 ._()-]*$/) != nil
        // A model switch explicitly invalidates a previously observed Gemini turn.
        var state = SessionState.unknown
        if gemini && event == "PreInvocation" { state = .working }
        if gemini && event == "Stop", let idle = object["fullyIdle"] as? NSNumber,
           CFGetTypeID(idle) == CFBooleanGetTypeID(), idle.boolValue { state = .turnEnded }
        let destination = GeminiDestination(conversationID: conversation, workspace: workspace)
        guard destination.url != nil else { return nil }
        return Self(id: id, state: state, observed: now,
                    destination: state == .unknown ? nil : destination)
    }

    // CLI frames also carry the prompt and model response.
    public static let cliFrameLimit = 2 * 1024 * 1024

    public static func projectCLI(_ data: Data, event: String) -> Self? {
        guard let object = try? StrictJSON.object(data, byteLimit: cliFrameLimit) as? [String: Any],
              object["hook_event_name"] as? String == event,
              let session = object["session_id"] as? String,
              let uuid = UUID(uuidString: session), uuid.uuidString.lowercased() == session.lowercased(),
              let stamp = object["timestamp"] as? String, stamp.utf8.count <= 29,
              stamp.wholeMatch(of: /[0-9]{4}-[0-9]{2}-[0-9]{2}T(?:[01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](?:\.[0-9]{1,3})?(?:Z|[+-](?:[01][0-9]|2[0-3]):[0-5][0-9])/) != nil else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = stamp.contains(".") ? "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX" : "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        formatter.isLenient = false
        guard let date = formatter.date(from: stamp) else { return nil }
        let state: SessionState
        switch event {
        case "AfterAgent": state = .turnEnded
        case "Notification" where object["notification_type"] as? String == "ToolPermission": state = .needsAttention
        default: return nil
        }
        let digest = SHA256.hash(data: Data(("gemini-cli/" + uuid.uuidString).utf8)).prefix(16)
            .map { String(format: "%02x", $0) }.joined()
        return Self(id: "cli-" + digest, state: state, observed: date.timeIntervalSince1970 * 1000)
    }

    var valid: Bool {
        let cli = id.hasPrefix("cli-")
        let digest = cli ? id.dropFirst(4) : id[...]
        let states: [SessionState] = cli ? [.turnEnded, .needsAttention] : [.working, .turnEnded, .unknown]
        return digest.utf8.count == 32 && digest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            && states.contains(state) && observed.isFinite
            && (destination == nil || (!cli && state != .unknown && destination?.sessionID == "gemini:" + id && destination?.url != nil))
    }
}

/// A private, nonblocking datagram endpoint. Dropped hooks cannot stall the IDE.
/// Only the live app holds the lock; crash leftovers are recovered under that lock.
public final class GeminiHookSocket {
    private let fd: Int32
    private let lock: Int32
    private let path: String
    private static let packetLimit = 8192
    public static var directory: String { "/tmp/bamboo-pulse-gemini-" + String(getuid()) }

    private static func privateNode(_ path: String, _ type: mode_t, _ mode: mode_t) -> Bool {
        var s = stat()
        return lstat(path, &s) == 0 && s.st_uid == getuid() && s.st_mode & S_IFMT == type && s.st_mode & 0o777 == mode
    }

    private static func address(_ path: String, _ body: (UnsafePointer<sockaddr>, socklen_t) -> Bool) -> Bool {
        var a = sockaddr_un()
        let bytes = path.utf8CString
        guard bytes.count <= MemoryLayout.size(ofValue: a.sun_path) else { return false }
        a.sun_family = sa_family_t(AF_UNIX)
        a.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &a.sun_path) { $0.copyBytes(from: bytes.map { UInt8(bitPattern: $0) }) }
        return withUnsafePointer(to: &a) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    public init?(directory: String = GeminiHookSocket.directory) {
        guard mkdir(directory, 0o700) == 0 || errno == EEXIST,
              Self.privateNode(directory, S_IFDIR, 0o700) else { return nil }
        let lockPath = directory + "/owner.lock"
        let lock = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard lock >= 0 else { return nil }
        guard Self.privateNode(lockPath, S_IFREG, 0o600), flock(lock, LOCK_EX | LOCK_NB) == 0
        else { close(lock); return nil }
        let path = directory + "/events.sock"
        if Self.privateNode(path, S_IFSOCK, 0o600) { unlink(path) }
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { close(lock); return nil }
        guard fcntl(fd, F_SETFD, FD_CLOEXEC) == 0, fcntl(fd, F_SETFL, O_NONBLOCK) == 0,
              Self.address(path, { bind(fd, $0, $1) == 0 }) else { close(fd); close(lock); return nil }
        guard chmod(path, 0o600) == 0 else { unlink(path); close(fd); close(lock); return nil }
        self.fd = fd
        self.path = path
        self.lock = lock
    }

    public static func send(_ event: GeminiHook, directory: String = directory) {
        let path = directory + "/events.sock"
        guard event.valid, privateNode(directory, S_IFDIR, 0o700), privateNode(path, S_IFSOCK, 0o600),
              let data = try? JSONEncoder().encode(event), data.count <= packetLimit else { return }
        let fd = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = address(path) { addr, size in
            data.withUnsafeBytes { sendto(fd, $0.baseAddress, $0.count, MSG_DONTWAIT, addr, size) == $0.count }
        }
    }

    public func drain() -> [GeminiHook] {
        var events = [GeminiHook]()
        var buffer = [UInt8](repeating: 0, count: Self.packetLimit + 1)
        for _ in 0..<128 {
            let size = recv(fd, &buffer, buffer.count, MSG_DONTWAIT)
            if size < 0 { break }
            guard size > 0, size <= Self.packetLimit else { continue }
            let data = Data(buffer.prefix(size))
            guard let fields = try? StrictJSON.object(data) as? [String: Any],
                  Set(fields.keys).subtracting(["destination"]) == ["id", "state", "observed"],
                  let event = try? JSONDecoder().decode(GeminiHook.self, from: data), event.valid else { continue }
            if let target = fields["destination"], !(target is NSNull) {
                guard let target = target as? [String: Any],
                      Set(target.keys) == ["conversationID", "workspace"] else { continue }
            }
            events.append(event)
        }
        return events
    }

    deinit { unlink(path); close(fd); close(lock) }
}

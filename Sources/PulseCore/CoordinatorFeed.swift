import Foundation
import CryptoKit
import CoreFoundation
import Darwin

/// Read-only status and click-triggered navigation, same-user private socket. No startup or USB access.
public struct CoordinatorFeed: NowFeed {
    public let path: String
    public init(path: String = "/tmp/bamboox-\(getuid())/coordinator.sock") { self.path = path }

    public func read() async throws -> Data {
        try await Task.detached { try exchange() }.value
    }

    public func chatThreadID(for sessionID: String) async throws -> String? {
        guard sessionID.utf8.count == 32, sessionID.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { throw FeedError.invalidData }
        return try await Task.detached {
            let bytes = try exchange(sessionID: sessionID)
            let result = try JSONSerialization.jsonObject(with: bytes) as? [String: Any]
            return result?["thread_id"] as? String
        }.value
    }

    private func exchange(sessionID: String? = nil) throws -> Data {
        guard path.hasPrefix("/"), path.utf8.count < 104, !path.utf8.contains(0) else { throw FeedError.unavailable }
        var directory = stat(), endpoint = stat()
        let parent = (path as NSString).deletingLastPathComponent
        guard lstat(parent, &directory) == 0, directory.st_uid == getuid(), directory.st_mode & S_IFMT == S_IFDIR,
              directory.st_mode & 0o777 == 0o700, lstat(path, &endpoint) == 0,
              endpoint.st_uid == getuid(), endpoint.st_mode & S_IFMT == S_IFSOCK,
              endpoint.st_mode & 0o777 == 0o600 else { throw FeedError.unavailable }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw FeedError.unavailable }
        defer { close(fd) }
        var noPipe: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout.size(ofValue: noPipe))) == 0,
              fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw FeedError.unavailable }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if result != 0 {
            guard errno == EINPROGRESS else { throw FeedError.unavailable }
            try wait(fd, events: Int16(POLLOUT), deadline: deadline)
            var error: Int32 = 0, size = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &size) == 0, error == 0 else { throw FeedError.unavailable }
        }
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { throw FeedError.unavailable }
        let identifier = UUID().uuidString
        let method = sessionID == nil ? "getActivityNow" : "getActivityChatLink"
        let params: [String: String] = sessionID.map { ["session_id": $0] } ?? [:]
        var bytes = try JSONSerialization.data(withJSONObject: ["id": identifier, "method": method, "params": params] as [String: Any])
        bytes.append(10)
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                try wait(fd, events: Int16(POLLOUT), deadline: deadline)
                let count = send(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, 0)
                if count < 0 && [EINTR, EAGAIN].contains(errno) { continue }
                guard count > 0 else { throw FeedError.unavailable }
                offset += count
            }
        }
        var received = Data(), chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            try wait(fd, events: Int16(POLLIN), deadline: deadline)
            let count = recv(fd, &chunk, chunk.count, 0)
            if count < 0 && [EINTR, EAGAIN].contains(errno) { continue }
            guard count > 0 else { throw FeedError.unavailable }
            received.append(contentsOf: chunk.prefix(count))
            if let sessionID {
                if let result = try Self.decodeChatLinkResponse(received, identifier: identifier, sessionID: sessionID) { return result }
            } else if let result = try Self.decodeResponse(received, identifier: identifier) { return result }
        }
    }

    /// Bounded newline-delimited envelope; also used by deterministic framing tests.
    public static func decodeResponse(_ data: Data, identifier: String) throws -> Data? {
        guard let result = try responseObject(data, identifier: identifier) else { return nil }
        let payload = try JSONSerialization.data(withJSONObject: result)
        _ = try NowPacket.parse(payload)
        return payload
    }

    public static func decodeChatLinkResponse(_ data: Data, identifier: String, sessionID: String) throws -> Data? {
        guard let result = try responseObject(data, identifier: identifier) else { return nil }
        if Set(result.keys) == ["state", "reason"], result["state"] as? String == "REJECTED",
           result["reason"] as? String == "METHOD_NOT_ALLOWED" {
            throw FeedError.unsupportedMethod
        }
        guard Set(result.keys) == ["version", "session_id", "thread_id"],
              let version = result["version"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(), version == 1,
              result["session_id"] as? String == sessionID else { throw FeedError.invalidData }
        if !(result["thread_id"] is NSNull) {
            guard let id = result["thread_id"] as? String, id.utf8.count == 36,
                  UUID(uuidString: id)?.uuidString.lowercased() == id,
                  SHA256.hash(data: Data(id.utf8)).prefix(16).map({ String(format: "%02x", $0) }).joined() == sessionID
            else { throw FeedError.invalidData }
        }
        return try JSONSerialization.data(withJSONObject: result)
    }

    private static func responseObject(_ data: Data, identifier: String) throws -> [String: Any]? {
        guard data.count <= 131072 else { throw FeedError.invalidData }
        guard let newline = data.firstIndex(of: 10) else { return nil }
        guard newline == data.count - 1,
              let value = (try? StrictJSON.object(Data(data.prefix(upTo: newline)))) as? [String: Any],
              Set(value.keys) == ["id", "result"], value["id"] as? String == identifier,
              let result = value["result"] as? [String: Any] else { throw FeedError.invalidData }
        return result
    }

    private func wait(_ fd: Int32, events: Int16, deadline: ContinuousClock.Instant) throws {
        while true {
            let remaining = ContinuousClock.now.duration(to: deadline).components
            let ms = Double(remaining.seconds) * 1000 + Double(remaining.attoseconds) / 1e15
            guard ms > 0 else { throw FeedError.unavailable }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = poll(&descriptor, 1, Int32(min(2000, ceil(ms))))
            if result < 0 && errno == EINTR { continue }
            guard result > 0, descriptor.revents & events != 0 else { throw FeedError.unavailable }
            return
        }
    }
}

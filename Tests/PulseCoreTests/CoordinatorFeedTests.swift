import Darwin
import Foundation
import Testing
@testable import PulseCore

struct CoordinatorFeedTests {
    @Test func readsOnlyNowFromPrivateFixtureSocketWithFragmentedResponse() async throws {
        let server = try FixtureSocket()
        defer { server.close() }
        let reply = Task.detached { try server.respond() }
        let received = try await CoordinatorFeed(path: server.path).read()
        #expect(try NowPacket.parse(received).sessions.first?.state == .working)
        try await reply.value
    }

    @Test func resolvesOnlySelectedSessionOverPrivateFixtureSocket() async throws {
        let server = try FixtureSocket()
        defer { server.close() }
        let sessionID = "bd7662a5eeb41614e720d477abfcb227"
        let threadID = "11111111-1111-4111-8111-111111111111"
        let reply = Task.detached {
            try server.respond(method: "getActivityChatLink", params: ["session_id": sessionID],
                result: ["version": 1, "session_id": sessionID, "thread_id": threadID])
        }
        #expect(try await CoordinatorFeed(path: server.path).chatThreadID(for: sessionID) == threadID)
        try await reply.value
    }

    @Test func rejectsUnsafeSocketAndDirectoryModesAndSymlinks() async throws {
        let server = try FixtureSocket()
        defer { server.close() }
        chmod(server.path, 0o666)
        await #expect(throws: (any Error).self) { try await CoordinatorFeed(path: server.path).read() }
        chmod(server.path, 0o600)
        chmod(server.directory, 0o755)
        await #expect(throws: (any Error).self) { try await CoordinatorFeed(path: server.path).read() }
        chmod(server.directory, 0o700)
        let alias = server.directory + "/alias.sock"
        try FileManager.default.createSymbolicLink(atPath: alias, withDestinationPath: server.path)
        await #expect(throws: (any Error).self) { try await CoordinatorFeed(path: alias).read() }
    }

    @Test func boundedTimeoutDoesNotWaitForeverForSilentPeer() async throws {
        let server = try FixtureSocket()
        defer { server.close() }
        let start = ContinuousClock.now
        await #expect(throws: (any Error).self) { try await CoordinatorFeed(path: server.path).read() }
        #expect(start.duration(to: .now) < .seconds(4))
    }
}

/// Fresh same-user fixture only. Never uses the real runtime path or opens USB.
private final class FixtureSocket: @unchecked Sendable {
    let directory = "/private/tmp/pulse-fixture-" + UUID().uuidString
    let path: String
    let descriptor: Int32

    init() throws {
        path = directory + "/now.sock"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, chmod(path, 0o600) == 0, listen(descriptor, 2) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            Darwin.close(descriptor)
            try? FileManager.default.removeItem(atPath: directory)
            throw error
        }
    }

    func close() {
        Darwin.close(descriptor)
        try? FileManager.default.removeItem(atPath: directory)
    }

    func respond(method: String = "getActivityNow", params expectedParams: [String: String] = [:], result: [String: Any] = packet()) throws {
        var available = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&available, 1, 2000) > 0 else { throw FeedError.unavailable }
        let client = accept(descriptor, nil, nil)
        guard client >= 0 else { throw FeedError.unavailable }
        defer { Darwin.close(client) }
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        var buffer = [UInt8](repeating: 0, count: 4096), request = Data()
        while !request.contains(10) {
            let count = recv(client, &buffer, buffer.count, 0)
            guard count > 0, request.count + count <= 4096 else { throw FeedError.invalidData }
            request.append(contentsOf: buffer.prefix(count))
        }
        guard let object = try JSONSerialization.jsonObject(with: request) as? [String: Any],
              Set(object.keys) == ["id", "method", "params"],
              object["method"] as? String == method,
              let params = object["params"] as? [String: String], params == expectedParams,
              let id = object["id"] as? String else { throw FeedError.invalidData }
        let response = try JSONSerialization.data(withJSONObject: ["id": id, "result": result]) + Data([10])
        for part in [Data(response.prefix(7)), Data(response.dropFirst(7))] {
            try part.withUnsafeBytes { bytes in
                guard send(client, bytes.baseAddress!, bytes.count, 0) == bytes.count else { throw FeedError.unavailable }
            }
        }
    }
}

import Foundation
import Darwin
import Testing
@testable import PulseCore

@MainActor
struct ReviewFixTests {
    @Test func duplicateLeaseIsRejectedAndReleasedOnExit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-lease-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("instance.lock")
        var first: SingleInstanceLease? = try SingleInstanceLease(lockURL: path)
        try withExtendedLifetime(first) {
            do {
                _ = try SingleInstanceLease(lockURL: path)
                Issue.record("A second app-instance lease was admitted")
            } catch let error as POSIXError {
                #expect(error.code == .EWOULDBLOCK)
            }
        }
        first = nil
        let second = try SingleInstanceLease(lockURL: path)
        withExtendedLifetime(second) {
            #expect(FileManager.default.fileExists(atPath: path.path))
        }
    }

    @Test func unsafeLockFilesAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-lease-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("instance.lock")
        try Data().write(to: path)
        chmod(path.path, 0o644)
        #expect(throws: POSIXError.self) { try SingleInstanceLease(lockURL: path) }
        let alias = directory.appendingPathComponent("alias.lock")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: path)
        #expect(throws: POSIXError.self) { try SingleInstanceLease(lockURL: alias) }
    }
}

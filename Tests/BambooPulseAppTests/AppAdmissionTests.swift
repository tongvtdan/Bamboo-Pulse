import AppKit
import PulseCore
import Testing

@Suite("Visible app admission") @MainActor
struct AppAdmissionTests {
    @Test func duplicateShowsMessageBeforeExitAndNeverStarts() throws {
        let (directory, path) = try lockFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let owner = try SingleInstanceLease(lockURL: path)
        var events: [String] = []
        let admission = AppAdmission(acquireLease: { try SingleInstanceLease(lockURL: path) },
            presentFailure: { failure in
                #expect(failure == .alreadyRunning)
                #expect(failure.message.contains("menu bar"))
                events.append("present")
            }, terminate: { events.append("exit") })
        withExtendedLifetime(owner) { admission.start { events.append("started") } }
        #expect(events == ["present", "exit"])
        // The rejected copy did not release or replace the first copy's lease.
        withExtendedLifetime(owner) {
            #expect(throws: POSIXError.self) { try SingleInstanceLease(lockURL: path) }
        }
    }

    @Test(arguments: [POSIXErrorCode.EACCES, .ELOOP, .ENOENT, .EIO])
    func ownershipErrorsShowSafeMessageAndNeverStart(_ code: POSIXErrorCode) {
        var events: [String] = []
        let admission = AppAdmission(acquireLease: { throw POSIXError(code) },
            presentFailure: { failure in
                #expect(failure == .unsafeStart)
                #expect(!failure.message.contains("already running"))
                events.append("present")
            }, terminate: { events.append("exit") })
        admission.start { events.append("started") }
        #expect(events == ["present", "exit"])
    }

    @Test func unexpectedErrorDoesNotExposePrivateDetails() {
        var presented: AppAdmission.Failure?
        var exits = 0, starts = 0
        let admission = AppAdmission(acquireLease: {
            throw NSError(domain: "private /Users/example/secret", code: 123,
                          userInfo: [NSLocalizedDescriptionKey: "private failure"])
        }, presentFailure: { presented = $0 }, terminate: { exits += 1 })
        admission.start { starts += 1 }
        #expect(presented == .unsafeStart)
        #expect(presented?.title.contains("safely") == true)
        #expect(presented?.message.contains("private") == false)
        #expect(exits == 1)
        #expect(starts == 0)
    }

    @Test func missingPresentationStillExitsWithoutStarting() {
        var exits = 0, starts = 0
        let admission = AppAdmission(acquireLease: { throw POSIXError(.EACCES) },
            presentFailure: { _ in }, terminate: { exits += 1 })
        admission.start { starts += 1 }
        #expect(exits == 1)
        #expect(starts == 0)
    }

    @Test func validLaunchRetainsLeaseUntilAdmissionOwnerExits() throws {
        let (directory, path) = try lockFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var starts = 0, failures = 0, exits = 0
        var admission: AppAdmission? = AppAdmission(acquireLease: { try SingleInstanceLease(lockURL: path) },
            presentFailure: { _ in failures += 1 }, terminate: { exits += 1 })
        admission?.start { starts += 1 }
        withExtendedLifetime(admission) {
            #expect(throws: POSIXError.self) { try SingleInstanceLease(lockURL: path) }
        }
        #expect(starts == 1)
        #expect(failures == 0)
        #expect(exits == 0)
        admission = nil
        let next = try SingleInstanceLease(lockURL: path)
        withExtendedLifetime(next) { #expect(FileManager.default.fileExists(atPath: path.path)) }
    }

    private func lockFixture() throws -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("pulse-admission-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return (directory, directory.appendingPathComponent("instance.lock"))
    }
}

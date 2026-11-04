import AppKit
import PulseCore

@MainActor
final class AppAdmission {
    enum Failure: Equatable {
        case alreadyRunning, unsafeStart

        init(error: Error) {
            if let error = error as? POSIXError, error.code == .EWOULDBLOCK {
                self = .alreadyRunning
            } else {
                self = .unsafeStart
            }
        }

        var title: String {
            switch self {
            case .alreadyRunning: "Bamboo Pulse is already running"
            case .unsafeStart: "Bamboo Pulse couldn’t start safely"
            }
        }

        var message: String {
            switch self {
            case .alreadyRunning: "Use the Pulse icon in the menu bar, or quit the other copy before opening this one."
            case .unsafeStart: "Close this copy and try again. If the problem continues, contact support."
            }
        }
    }

    private let acquireLease: @MainActor () throws -> SingleInstanceLease
    private let presentFailure: @MainActor (Failure) -> Void
    private let terminate: @MainActor () -> Void
    private var lease: SingleInstanceLease?

    init(acquireLease: @escaping @MainActor () throws -> SingleInstanceLease = {
        let identifier = Bundle.main.bundleIdentifier ?? "local.bamboox.BambooPulse.debug"
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(identifier).instance.lock")
        return try SingleInstanceLease(lockURL: lockURL)
    }, presentFailure: @escaping @MainActor (Failure) -> Void = AppAdmission.present,
         terminate: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }) {
        self.acquireLease = acquireLease
        self.presentFailure = presentFailure
        self.terminate = terminate
    }

    func start(_ admitted: @MainActor () -> Void) {
        do {
            lease = try acquireLease()
        } catch {
            presentFailure(Failure(error: error))
            terminate()
            return
        }
        admitted()
    }

    static func present(_ failure: Failure) {
        let application = NSApplication.shared
        if application.activationPolicy() == .prohibited {
            guard application.setActivationPolicy(.accessory) else { return }
        }
        application.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = failure.title
        alert.informativeText = failure.message
        alert.addButton(withTitle: "Close")
        alert.runModal()
    }
}

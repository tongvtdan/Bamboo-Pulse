import Foundation
import Observation
import OSLog
import PulseCore
import UserNotifications

enum AttentionAuthorization: Sendable { case notDetermined, allowed, denied, alertsDisabled }
enum AttentionNotificationKind { case needsYou, test }

@MainActor
protocol AttentionNotificationCenter: AnyObject {
    func authorization() async -> AttentionAuthorization
    func requestPermission() async throws
    func add(identifier: String, kind: AttentionNotificationKind) async throws
    func remove(identifiers: [String])
    func clearOwned() async
}

@MainActor
final class NativeAttentionNotificationCenter: AttentionNotificationCenter {
    static let prefix = "bamboo-pulse.needs-you."
    private let center = UNUserNotificationCenter.current()
    private let logger = Logger(subsystem: "com.dantino.bamboo-pulse", category: "Notifications")
    private var lastSettings: [Int] = []

    func authorization() async -> AttentionAuthorization {
        let (authorization, values): (AttentionAuthorization, [Int]) = await withCheckedContinuation { continuation in
            center.getNotificationSettings { @Sendable settings in
                let authorization: AttentionAuthorization
                switch settings.authorizationStatus {
                case .notDetermined: authorization = .notDetermined
                case .authorized, .provisional:
                    authorization = settings.alertSetting == .enabled ? .allowed : .alertsDisabled
                default: authorization = .denied
                }
                let values = [settings.authorizationStatus.rawValue, settings.alertSetting.rawValue, settings.alertStyle.rawValue]
                continuation.resume(returning: (authorization, values))
            }
        }
        if values != lastSettings {
            lastSettings = values
            logger.info("Notification settings: authorization=\(values[0], privacy: .public) alerts=\(values[1], privacy: .public) style=\(values[2], privacy: .public)")
        }
        return authorization
    }

    func requestPermission() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.requestAuthorization(options: [.alert]) { @Sendable _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func add(identifier: String, kind: AttentionNotificationKind) async throws {
        let content = UNMutableNotificationContent()
        content.title = kind == .test ? "Pulse notification test" : "Needs you"
        content.body = kind == .test ? "Click this notification to open Pulse." : "An observed session needs your attention. Open Pulse to check."
        content.threadIdentifier = "bamboo-pulse.attention"
        logger.info("Submitting local notification; test=\(kind == .test, privacy: .public)")
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            center.add(request) { @Sendable error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        logger.info("macOS accepted local notification; test=\(kind == .test, privacy: .public)")
    }

    func remove(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func clearOwned() async {
        let pending: [String] = await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { @Sendable requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
        let delivered: [String] = await withCheckedContinuation { continuation in
            center.getDeliveredNotifications { @Sendable notifications in
                continuation.resume(returning: notifications.map { $0.request.identifier })
            }
        }
        remove(identifiers: (pending + delivered).filter { $0.hasPrefix(Self.prefix) })
    }
}

@MainActor @Observable
final class NeedsYouNotifications: NSObject, UNUserNotificationCenterDelegate {
    private(set) var isEnabled: Bool
    private(set) var authorization: AttentionAuthorization = .notDetermined
    private(set) var isRequestingPermission = false
    private(set) var deliveryFailed = false
    private(set) var permissionRequestFailed = false
    private(set) var isSendingTest = false
    private(set) var testStatus: String?
    var navigationNotice: String?
    @ObservationIgnored private let store: MonitorStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let center: any AttentionNotificationCenter
    @ObservationIgnored private let clock: () -> MonitorTime
    @ObservationIgnored private let openPulse: () -> Void
    @ObservationIgnored private var policy = NeedsYouPolicy()
    @ObservationIgnored private var active: [String: Episode] = [:]
    @ObservationIgnored private var intent: UInt64 = 0
    @ObservationIgnored private var stopped = false
    @ObservationIgnored private var ready = false
    @ObservationIgnored private var starting = false
    @ObservationIgnored private var nextPermissionCheck: Double = 0
    @ObservationIgnored private var permissionCheckInFlight = false
    @ObservationIgnored private var testIdentifier: String?
    @ObservationIgnored private let logger = Logger(subsystem: "com.dantino.bamboo-pulse", category: "Notifications")

    private struct Episode {
        let sessionID: String
        let generation: String?
        let epoch: UInt64
        let continuity: UInt64
    }

    init(store: MonitorStore, defaults: UserDefaults = .standard,
         center: any AttentionNotificationCenter = NativeAttentionNotificationCenter(),
         clock: @escaping () -> MonitorTime = { .now }, openPulse: @escaping () -> Void) {
        self.store = store
        self.defaults = defaults
        self.center = center
        self.clock = clock
        self.openPulse = openPulse
        isEnabled = defaults.bool(forKey: "attention.notifyNeedsYou")
        super.init()
    }

    var statusMessage: String {
        if store.isSynthetic { return "Notifications are unavailable in Preview." }
        if isRequestingPermission { return "Waiting for notification permission…" }
        if !isEnabled { return "Off. Enable to be notified when a session needs you." }
        if permissionRequestFailed { return "macOS couldn’t request notification permission for this build. Registration failed before macOS could list Pulse. Retry with a signed build." }
        if authorization == .alertsDisabled { return "Turn on banners or alerts for Bamboo Pulse in macOS notification settings." }
        if authorization != .allowed { return "Allow Bamboo Pulse notifications in macOS System Settings." }
        if deliveryFailed { return "Couldn’t deliver a notification. Check macOS notification settings." }
        return "Notifies when a session changes to Needs you. Focus may silence or delay notifications."
    }

    func start() async {
        guard !store.isSynthetic, !stopped, !starting, !ready else { return }
        starting = true
        await center.clearOwned()
        guard !stopped else { return }
        ready = true
        await refreshAuthorization()
    }

    func refreshAuthorization() async {
        guard !store.isSynthetic, !stopped, !isRequestingPermission else { return }
        let token = intent
        let next = await center.authorization()
        guard !stopped, token == intent, !isRequestingPermission else { return }
        if next != authorization { policy.reset() }
        authorization = next
        nextPermissionCheck = clock().continuousMS + 5000
        if next != .notDetermined { permissionRequestFailed = false }
        update()
    }

    func setEnabled(_ enabled: Bool) async {
        guard !store.isSynthetic, !stopped else { return }
        intent &+= 1
        let token = intent
        isEnabled = enabled
        defaults.set(enabled, forKey: "attention.notifyNeedsYou")
        policy.reset()
        removeAllActive()
        deliveryFailed = false
        permissionRequestFailed = false
        testStatus = nil
        guard enabled else { isRequestingPermission = false; return }
        isRequestingPermission = true
        let status = await center.authorization()
        guard token == intent, !stopped else { return }
        do {
            if status == .notDetermined { try await center.requestPermission() }
        } catch {
            guard token == intent, !stopped else { return }
            permissionRequestFailed = true
            let failure = error as NSError
            let domain = ["UNErrorDomain", NSCocoaErrorDomain, NSOSStatusErrorDomain].contains(failure.domain) ? failure.domain : "Other"
            logger.error("Notification permission request failed: domain=\(domain, privacy: .public) code=\(failure.code, privacy: .public)")
        }
        let current = await center.authorization()
        guard token == intent, !stopped else { return }
        authorization = current
        nextPermissionCheck = clock().continuousMS + 5000
        if current != .notDetermined { permissionRequestFailed = false }
        isRequestingPermission = false
        policy.reset()
        update()
    }

    func update() {
        guard !stopped else { return }
        checkPermissionIfDue()
        if let identifier = testIdentifier, !isCurrent(identifier) {
            center.remove(identifiers: [identifier])
            testIdentifier = nil
        }
        let enabled = ready && isEnabled && authorization == .allowed && !isRequestingPermission
        let stale = active.keys.filter { !isCurrent($0) }
        if !stale.isEmpty { center.remove(identifiers: stale) }
        for id in stale { active.removeValue(forKey: id) }
        let sessions = policy.update(sessions: store.sessions, health: store.health,
            generation: store.observationGeneration, epoch: store.epoch, enabled: enabled, synthetic: store.isSynthetic)
        for sessionID in sessions {
            guard let continuity = store.sessions.first(where: { $0.id == sessionID })?.observationContinuity else { continue }
            let identifier = NativeAttentionNotificationCenter.prefix + UUID().uuidString
            active[identifier] = Episode(sessionID: sessionID, generation: store.observationGeneration,
                epoch: store.epoch, continuity: continuity)
            Task { @MainActor [weak self] in await self?.deliver(identifier) }
        }
    }

    private func checkPermissionIfDue() {
        guard ready, isEnabled, !store.isSynthetic, !isRequestingPermission, !permissionCheckInFlight,
              clock().continuousMS >= nextPermissionCheck else { return }
        permissionCheckInFlight = true
        nextPermissionCheck = clock().continuousMS + 5000
        Task { @MainActor [weak self] in
            guard let self else { return }
            await refreshAuthorization()
            permissionCheckInFlight = false
        }
    }

    func sendTestNotification() async {
        guard ready, !stopped, !store.isSynthetic, isEnabled, !isSendingTest, !isRequestingPermission else { return }
        isSendingTest = true
        defer { isSendingTest = false }
        let token = intent
        await refreshAuthorization()
        guard token == intent, !stopped, isEnabled, !isRequestingPermission else { return }
        guard authorization == .allowed else {
            testStatus = authorization == .alertsDisabled ? "Banners or alerts are turned off for Pulse." : "macOS hasn’t allowed notifications for Pulse."
            return
        }
        if let testIdentifier { center.remove(identifiers: [testIdentifier]) }
        let identifier = NativeAttentionNotificationCenter.prefix + "test." + UUID().uuidString
        testIdentifier = identifier
        do {
            try await center.add(identifier: identifier, kind: .test)
            if isCurrent(identifier) { testStatus = "Test submitted to macOS. If no banner appears, check Focus and notification display settings." }
            else { center.remove(identifiers: [identifier]) }
        } catch {
            center.remove(identifiers: [identifier])
            if testIdentifier == identifier { testIdentifier = nil }
            if !stopped && isEnabled { testStatus = "macOS couldn’t accept the test notification." }
            logger.error("Test notification submission failed")
        }
    }

    private func isCurrent(_ identifier: String) -> Bool {
        if identifier == testIdentifier {
            return ready && !stopped && !store.isSynthetic && isEnabled && !isRequestingPermission && authorization == .allowed
        }
        store.refresh(at: clock())
        guard ready, !stopped, !store.isSynthetic, isEnabled, !isRequestingPermission, authorization == .allowed,
              store.health == .monitoring, let episode = active[identifier], episode.epoch == store.epoch,
              episode.generation == store.observationGeneration else { return false }
        return store.sessions.contains {
            $0.id == episode.sessionID && $0.state == .needsAttention && $0.observationContinuity == episode.continuity
        }
    }

    private func deliver(_ identifier: String) async {
        guard isCurrent(identifier) else { return }
        let permission = await center.authorization()
        guard isCurrent(identifier) else { return }
        if permission != .allowed {
            authorization = permission
            update()
            return
        }
        do {
            try await center.add(identifier: identifier, kind: .needsYou)
            if !isCurrent(identifier) { center.remove(identifiers: [identifier]) }
            else { deliveryFailed = false }
        } catch {
            active.removeValue(forKey: identifier)
            center.remove(identifiers: [identifier])
            if !stopped { deliveryFailed = true }
            logger.error("Attention notification submission failed")
        }
    }

    func openNotification(identifier: String) {
        guard !stopped, !store.isSynthetic, identifier.hasPrefix(NativeAttentionNotificationCenter.prefix) else { return }
        navigationNotice = isCurrent(identifier) ? nil : "This notification is no longer current. Showing the latest session status."
        active.removeValue(forKey: identifier)
        if testIdentifier == identifier { testIdentifier = nil }
        center.remove(identifiers: [identifier])
        openPulse()
    }

    func shouldPresent(identifier: String) -> Bool { isCurrent(identifier) }

    private func removeAllActive() {
        center.remove(identifiers: Array(active.keys) + (testIdentifier.map { [$0] } ?? []))
        active.removeAll()
        testIdentifier = nil
    }

    func stop() {
        stopped = true
        intent &+= 1
        policy.reset()
        removeAllActive()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let id = notification.request.identifier
        let present = await shouldPresent(identifier: id)
        await logPresentation(present)
        return present ? [.banner, .list] : []
    }

    private func logPresentation(_ present: Bool) {
        logger.info("Foreground notification presentation allowed=\(present, privacy: .public)")
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let id = response.notification.request.identifier
        await openNotification(identifier: id)
    }
}

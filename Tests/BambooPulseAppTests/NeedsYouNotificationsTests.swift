import Foundation
import PulseCore
import Testing

@MainActor
private final class FakeAttentionCenter: AttentionNotificationCenter {
    var permission: AttentionAuthorization = .allowed
    var grantOnRequest = true
    var failPermission = false
    var denialOnFailure = false
    var authorizationReads = 0
    var permissionRequests = 0
    var cleared = 0
    var added: [String] = []
    var kinds: [AttentionNotificationKind] = []
    var removed: [String] = []
    var holdPermission = false
    var permissionContinuation: CheckedContinuation<Void, Never>?
    var holdAdd = false
    var failAdd = false
    var addContinuation: CheckedContinuation<Void, Never>?
    func authorization() async -> AttentionAuthorization { authorizationReads += 1; return permission }
    func requestPermission() async throws {
        permissionRequests += 1
        if failPermission {
            if denialOnFailure { permission = .denied }
            throw NSError(domain: "UNErrorDomain", code: 1)
        }
        if holdPermission { await withCheckedContinuation { permissionContinuation = $0 } }
        permission = grantOnRequest ? .allowed : .denied
    }
    func add(identifier: String, kind: AttentionNotificationKind) async throws {
        if failAdd { throw CocoaError(.fileWriteUnknown) }
        added.append(identifier)
        kinds.append(kind)
        if holdAdd { await withCheckedContinuation { addContinuation = $0 } }
    }
    func remove(identifiers: [String]) { removed += identifiers }
    func clearOwned() async { cleared += 1 }
}

@Suite("Needs you notifications") @MainActor
struct NeedsYouNotificationsTests {
    private func make(synthetic: Bool = false) -> (MonitorStore, NeedsYouNotifications, FakeAttentionCenter, UserDefaults) {
        let store = MonitorStore(synthetic: synthetic), center = FakeAttentionCenter()
        let defaults = UserDefaults(suiteName: "needs-you-test-" + UUID().uuidString)!
        let notifications = NeedsYouNotifications(store: store, defaults: defaults, center: center, clock: { time() }, openPulse: {})
        return (store, notifications, center, defaults)
    }

    private func receive(_ state: String, sequence: Int, generation: String = String(repeating: "b", count: 32),
                         store: MonitorStore, notifications: NeedsYouNotifications) throws {
        store.receive(try data(packet(sequence: sequence, generation: generation, rows: [row(state)])), at: time(), epoch: store.epoch)
        notifications.update()
    }

    private func settle() async { for _ in 0..<50 { await Task.yield() } }

    @Test func defaultsOffPersistsChoiceAndNeverPromptsOnLaunch() async {
        let (_, notifications, center, defaults) = make()
        #expect(!notifications.isEnabled)
        await notifications.start()
        #expect(center.permissionRequests == 0)
        await notifications.setEnabled(true)
        #expect(defaults.bool(forKey: "attention.notifyNeedsYou"))
        #expect(center.permissionRequests == 0)
        await notifications.setEnabled(false)
        #expect(!defaults.bool(forKey: "attention.notifyNeedsYou"))
    }

    @Test func oneEpisodeDeduplicatesAndResolutionRemovesNotification() async throws {
        let (store, notifications, center, _) = make()
        await notifications.start()
        await notifications.setEnabled(true)
        try receive("WORKING", sequence: 1, store: store, notifications: notifications)
        try receive("NEEDS_ATTENTION", sequence: 2, store: store, notifications: notifications)
        await settle()
        #expect(center.added.count == 1)
        try receive("NEEDS_ATTENTION", sequence: 3, store: store, notifications: notifications)
        await settle()
        #expect(center.added.count == 1)
        try receive("TURN_ENDED", sequence: 4, store: store, notifications: notifications)
        #expect(center.removed.contains(center.added[0]))
        try receive("NEEDS_ATTENTION", sequence: 5, store: store, notifications: notifications)
        await settle()
        #expect(center.added.count == 2)
    }

    @Test func queuedNotificationCannotSurviveLossOrHealthyGenerationReplacement() async throws {
        for boundary in ["loss", "generation", "disable", "expiry", "epoch"] {
            let (store, notifications, center, _) = make()
            await notifications.start()
            await notifications.setEnabled(true)
            try receive("WORKING", sequence: 1, store: store, notifications: notifications)
            try receive("NEEDS_ATTENTION", sequence: 2, store: store, notifications: notifications)
            switch boundary {
            case "loss": store.fail(.unavailable)
            case "generation": try receive("NEEDS_ATTENTION", sequence: 1, generation: String(repeating: "c", count: 32), store: store, notifications: notifications)
            case "disable": await notifications.setEnabled(false)
            case "expiry": store.refresh(at: time(2000))
            default: store.beginEpoch()
            }
            notifications.update()
            await settle()
            #expect(center.added.isEmpty)
        }
    }

    @Test func interruptedNativeAddIsRemovedAfterDisable() async throws {
        let (store, notifications, center, _) = make()
        center.holdAdd = true
        await notifications.start()
        await notifications.setEnabled(true)
        try receive("WORKING", sequence: 1, store: store, notifications: notifications)
        try receive("NEEDS_ATTENTION", sequence: 2, store: store, notifications: notifications)
        await settle()
        #expect(center.addContinuation != nil)
        await notifications.setEnabled(false)
        center.addContinuation?.resume()
        await settle()
        #expect(center.removed.contains(center.added[0]))
    }

    @Test(arguments: [true, false])
    func queuedAlertCannotReviveAfterExpiryRecoveryBeforeTick(wholePacket: Bool) async throws {
        let store = MonitorStore(), center = FakeAttentionCenter()
        let defaults = UserDefaults(suiteName: "needs-you-expiry-" + UUID().uuidString)!
        var now = time(), opens = 0
        let notifications = NeedsYouNotifications(store: store, defaults: defaults, center: center,
            clock: { now }, openPulse: { opens += 1 })
        defer { notifications.stop() }
        func receive(_ state: String, sequence: Int, delta: Int, remaining: Int) throws {
            now = time(Double(delta))
            store.receive(try data(packet(sequence: sequence, timestamp: 100000 + delta,
                rows: [row(state, remaining: remaining)])), at: now, epoch: store.epoch)
            notifications.update()
        }
        await notifications.start()
        await notifications.setEnabled(true)
        try receive("WORKING", sequence: 1, delta: 0, remaining: 120000)
        center.holdAdd = true
        try receive("NEEDS_ATTENTION", sequence: 2, delta: 100, remaining: wholePacket ? 5000 : 300)
        await settle()
        let identifier = try #require(center.added.first)
        #expect(center.addContinuation != nil)
        let recovery = wholePacket ? 2200 : 500
        try receive("NEEDS_ATTENTION", sequence: 3, delta: recovery, remaining: 5000)
        #expect(!notifications.shouldPresent(identifier: identifier))
        #expect(center.removed.contains(identifier))
        center.holdAdd = false
        center.addContinuation?.resume()
        await settle()
        #expect(center.added.count == 1)
        notifications.openNotification(identifier: identifier)
        #expect(opens == 1)
        #expect(notifications.navigationNotice?.contains("no longer current") == true)
        try receive("WORKING", sequence: 4, delta: recovery + 100, remaining: 120000)
        try receive("NEEDS_ATTENTION", sequence: 5, delta: recovery + 200, remaining: 5000)
        await settle()
        #expect(center.added.count == 2)
        try receive("NEEDS_ATTENTION", sequence: 6, delta: recovery + 300, remaining: 5000)
        await settle()
        #expect(center.added.count == 2)
    }

    @Test func deniedPermissionHasNoPromptLoopAndPreviewTouchesNoNativeCenter() async throws {
        let (store, notifications, center, _) = make()
        center.permission = .denied
        await notifications.start()
        await notifications.setEnabled(true)
        try receive("WORKING", sequence: 1, store: store, notifications: notifications)
        try receive("NEEDS_ATTENTION", sequence: 2, store: store, notifications: notifications)
        await settle()
        #expect(center.permissionRequests == 0)
        #expect(center.added.isEmpty)
        #expect(notifications.statusMessage.contains("System Settings"))
        let (_, preview, previewCenter, _) = make(synthetic: true)
        await preview.start()
        await preview.setEnabled(true)
        preview.update()
        #expect(previewCenter.authorizationReads == 0)
        #expect(previewCenter.permissionRequests == 0)
        #expect(previewCenter.cleared == 0)
        #expect(previewCenter.added.isEmpty)
    }

    @Test func disablingWhilePermissionIsPendingCannotReenableOrBackfill() async {
        let (_, notifications, center, defaults) = make()
        center.permission = .notDetermined
        center.holdPermission = true
        await notifications.start()
        let enable = Task { await notifications.setEnabled(true) }
        await settle()
        #expect(center.permissionRequests == 1)
        await notifications.setEnabled(false)
        center.permissionContinuation?.resume()
        await enable.value
        #expect(!notifications.isEnabled)
        #expect(!defaults.bool(forKey: "attention.notifyNeedsYou"))
        #expect(center.added.isEmpty)
    }

    @Test func explicitPermissionRequestIsNotRepeatedAfterDenialAndExistingAttentionStaysSilent() async throws {
        let (store, notifications, center, _) = make()
        center.permission = .notDetermined
        center.grantOnRequest = false
        await notifications.start()
        try receive("NEEDS_ATTENTION", sequence: 1, store: store, notifications: notifications)
        await notifications.setEnabled(true)
        #expect(center.permissionRequests == 1)
        #expect(notifications.authorization == .denied)
        await notifications.setEnabled(false)
        await notifications.setEnabled(true)
        #expect(center.permissionRequests == 1)
        center.permission = .allowed
        await notifications.refreshAuthorization()
        try receive("NEEDS_ATTENTION", sequence: 2, store: store, notifications: notifications)
        await settle()
        #expect(center.added.isEmpty)
        try receive("WORKING", sequence: 3, store: store, notifications: notifications)
        try receive("NEEDS_ATTENTION", sequence: 4, store: store, notifications: notifications)
        await settle()
        #expect(center.added.count == 1)
    }

    @Test func permissionRequestErrorIsDistinctFromUserDenialAndCanRecover() async {
        let (_, notifications, center, _) = make()
        center.permission = .notDetermined
        center.failPermission = true
        await notifications.start()
        await notifications.setEnabled(true)
        #expect(notifications.permissionRequestFailed)
        #expect(!notifications.deliveryFailed)
        #expect(notifications.statusMessage.contains("couldn’t request notification permission"))
        #expect(!notifications.statusMessage.contains("System Settings"))
        #expect(center.permissionRequests == 1)
        notifications.update()
        #expect(center.permissionRequests == 1)
        center.permission = .allowed
        await notifications.refreshAuthorization()
        #expect(!notifications.permissionRequestFailed)
        #expect(!notifications.statusMessage.contains("couldn’t request notification permission"))
    }

    @Test func currentClickConsumesTheAlertWithoutOpeningCodexOrRearmingIt() async throws {
        let store = MonitorStore(), center = FakeAttentionCenter()
        let defaults = UserDefaults(suiteName: "needs-you-current-click-" + UUID().uuidString)!
        var opens = 0
        let notifications = NeedsYouNotifications(store: store, defaults: defaults, center: center, clock: { time() }) { opens += 1 }
        await notifications.start()
        await notifications.setEnabled(true)
        try receive("WORKING", sequence: 1, store: store, notifications: notifications)
        try receive("NEEDS_ATTENTION", sequence: 2, store: store, notifications: notifications)
        await settle()
        let identifier = try #require(center.added.first)
        #expect(notifications.shouldPresent(identifier: identifier))
        notifications.openNotification(identifier: identifier)
        #expect(opens == 1)
        #expect(notifications.navigationNotice == nil)
        #expect(!notifications.shouldPresent(identifier: identifier))
        try receive("NEEDS_ATTENTION", sequence: 3, store: store, notifications: notifications)
        await settle()
        #expect(center.added.count == 1)
    }

    @Test func staleClickOpensCurrentPulseWithExplanationAndForeignIDsDoNothing() async {
        let store = MonitorStore(), center = FakeAttentionCenter()
        let defaults = UserDefaults(suiteName: "needs-you-click-" + UUID().uuidString)!
        var opens = 0
        let notifications = NeedsYouNotifications(store: store, defaults: defaults, center: center, clock: { time() }) { opens += 1 }
        await notifications.start()
        notifications.openNotification(identifier: "foreign")
        #expect(opens == 0)
        notifications.openNotification(identifier: NativeAttentionNotificationCenter.prefix + "old-process")
        #expect(opens == 1)
        #expect(notifications.navigationNotice?.contains("no longer current") == true)
    }

    @Test func deliveryErrorDoesNotLoopAndNextGenuineEpisodeCanRecover() async throws {
        let (store, notifications, center, _) = make()
        center.failAdd = true
        await notifications.start()
        await notifications.setEnabled(true)
        try receive("WORKING", sequence: 1, store: store, notifications: notifications)
        try receive("NEEDS_ATTENTION", sequence: 2, store: store, notifications: notifications)
        await settle()
        #expect(notifications.deliveryFailed)
        #expect(center.removed.count == 1)
        try receive("NEEDS_ATTENTION", sequence: 3, store: store, notifications: notifications)
        await settle()
        #expect(center.removed.count == 1)
        center.failAdd = false
        try receive("WORKING", sequence: 4, store: store, notifications: notifications)
        try receive("NEEDS_ATTENTION", sequence: 5, store: store, notifications: notifications)
        await settle()
        #expect(center.added.count == 1)
        #expect(!notifications.deliveryFailed)
    }

    @Test func macOSPermissionChangeRefreshesWhileAppRemainsInBackground() async {
        let store = MonitorStore(), center = FakeAttentionCenter()
        let defaults = UserDefaults(suiteName: "needs-you-background-" + UUID().uuidString)!
        var now = time()
        center.permission = .denied
        let notifications = NeedsYouNotifications(store: store, defaults: defaults, center: center, clock: { now }, openPulse: {})
        await notifications.start()
        await notifications.setEnabled(true)
        let prior = center.authorizationReads
        center.permission = .allowed
        for _ in 0..<100 { notifications.update() }
        await settle()
        #expect(center.authorizationReads == prior)
        now = time(5000)
        for _ in 0..<100 { notifications.update() }
        await settle()
        #expect(notifications.authorization == .allowed)
        #expect(center.authorizationReads == prior + 1)
        #expect(center.permissionRequests == 0)
    }

    @Test func testNotificationIsExplicitAndIndependentOfSessionAvailability() async throws {
        let store = MonitorStore(), center = FakeAttentionCenter()
        let defaults = UserDefaults(suiteName: "needs-you-test-click-" + UUID().uuidString)!
        var opens = 0
        let notifications = NeedsYouNotifications(store: store, defaults: defaults, center: center, clock: { time() }) { opens += 1 }
        await notifications.start()
        await notifications.setEnabled(true)
        #expect(store.health != .monitoring)
        await notifications.sendTestNotification()
        #expect(center.kinds == [.test])
        let identifier = try #require(center.added.first)
        #expect(notifications.shouldPresent(identifier: identifier))
        #expect(notifications.testStatus?.contains("submitted") == true)
        notifications.openNotification(identifier: identifier)
        #expect(opens == 1)
        #expect(notifications.navigationNotice == nil)
        #expect(!notifications.shouldPresent(identifier: identifier))
        await notifications.setEnabled(false)
        await notifications.sendTestNotification()
        #expect(center.added.count == 1)
    }

    @Test func previewTestButtonDoesNothingAndDenialDoesNotSubmit() async {
        let (_, preview, previewCenter, _) = make(synthetic: true)
        await preview.start()
        await preview.sendTestNotification()
        #expect(previewCenter.authorizationReads == 0)
        #expect(previewCenter.added.isEmpty)
        let (_, notifications, center, _) = make()
        center.permission = .denied
        await notifications.start()
        await notifications.setEnabled(true)
        await notifications.sendTestNotification()
        #expect(center.added.isEmpty)
        #expect(notifications.testStatus?.contains("hasn’t allowed") == true)
    }

    @Test func macOSRefusalWithDeniedStatusAndDisabledBannersHaveSpecificGuidance() async {
        let (_, notifications, center, _) = make()
        center.permission = .notDetermined
        center.failPermission = true
        center.denialOnFailure = true
        await notifications.start()
        await notifications.setEnabled(true)
        #expect(notifications.authorization == .denied)
        #expect(!notifications.permissionRequestFailed)
        #expect(notifications.statusMessage.contains("System Settings"))
        center.permission = .alertsDisabled
        await notifications.refreshAuthorization()
        #expect(notifications.statusMessage.contains("banners or alerts"))
        await notifications.sendTestNotification()
        #expect(center.added.isEmpty)
        #expect(notifications.testStatus?.contains("turned off") == true)
    }
}

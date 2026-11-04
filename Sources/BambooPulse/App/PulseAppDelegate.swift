import AppKit
import PulseCore
import UserNotifications

@MainActor
final class PulseAppDelegate: NSObject, NSApplicationDelegate {
    let store = MonitorStore(synthetic: ProcessInfo.processInfo.arguments.contains("--preview"))
    private let preferences = DisplayPreferences()
    private var settings: SettingsWindowController?
    private var navigation: SessionNavigationController?
    private var applicationMenu: PulseApplicationMenu?
    private var driver: MonitorDriver?
    private var menuBar: MenuBarController?
    private var attention: NeedsYouNotifications?
    private var configuring = false
    private var observerProcess: Process?
    private let runtime = Bundle.main.url(forResource: "PulseRuntime", withExtension: nil)
    private let source = MonitoringSource.selected()
    private let admission: AppAdmission

    init(admission: AppAdmission = AppAdmission()) {
        self.admission = admission
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        admission.start { startMonitoring() }
    }

    private func startMonitoring() {
        // Deliberately menu-bar-only; the app does not need a Dock icon or open window.
        NSApp.setActivationPolicy(.accessory)
        let attention = NeedsYouNotifications(store: store) { [weak self] in self?.menuBar?.presentFromNotification() }
        self.attention = attention
        if !store.isSynthetic { UNUserNotificationCenter.current().delegate = attention }
        let packaged = runtime != nil && !store.isSynthetic && source == .standalone
        let feed = packaged ? CoordinatorFeed(path: "/tmp/bamboo-pulse-\(getuid())/feed.sock") : CoordinatorFeed()
        driver = MonitorDriver(store: store, feed: feed, onUpdate: { [weak attention] in attention?.update() })
        let navigation = SessionNavigationController(lookup: { try await feed.chatThreadID(for: $0) })
        self.navigation = navigation
        settings = SettingsWindowController(store: store, preferences: preferences, attention: attention,
            manageSetup: runtime != nil && !store.isSynthetic ? { [weak self] in
                guard let self else { return }
                if self.source == .existing { self.manageExistingMonitoring() }
                else { Task { await self.configureMonitoring(manage: true) } }
            } : nil,
            usesExistingMonitoring: source == .existing)
        menuBar = MenuBarController(store: store, preferences: preferences, navigation: navigation, attention: attention) { [weak self] in
            self?.settings?.present()
        }
        applicationMenu = PulseApplicationMenu { [weak self] in self?.settings?.present() }
        NSApp.mainMenu = applicationMenu?.menu
        driver?.start()
        if packaged { Task { await configureMonitoring() } }
        Task { @MainActor [weak attention] in await attention?.start() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func manageExistingMonitoring() {
        let alert = NSAlert()
        alert.messageText = "Using existing local monitoring"
        alert.informativeText = "Pulse reads the existing service. The service keeps its current configuration. You can choose Pulse setup for the next launch."
        alert.addButton(withTitle: "Done")
        alert.addButton(withTitle: "Use Pulse setup after restart")
        if alert.runModal() == .alertSecondButtonReturn {
            MonitoringSource.standalone.save()
        }
    }

    private func offerExistingMonitoring() async throws {
        let feed = CoordinatorFeed()
        let packet = try NowPacket.parse(await feed.read())
        let age = Date().timeIntervalSince1970 * 1000 - packet.timestampMS
        guard packet.monitoringAvailable, age >= 0, age < packet.validForMS else {
            throw FeedError.unavailable
        }
        let alert = NSAlert()
        alert.messageText = "Use existing local monitoring?"
        alert.informativeText = "A compatible local monitoring service is available. Pulse can read its session status and chat links. Its configuration stays under your control."
        alert.addButton(withTitle: "Use existing monitoring")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        MonitoringSource.existing.save()
        let saved = NSAlert()
        saved.messageText = "Monitoring source saved"
        saved.informativeText = "Quit and reopen Bamboo Pulse to connect to existing monitoring."
        saved.addButton(withTitle: "OK")
        saved.runModal()
    }

    private func helper(_ operation: String, runtime: URL) -> Process {
        let process = Process()
        process.executableURL = runtime.appendingPathComponent("python/bin/python3")
        process.arguments = ["-I", "-S", "-B", "-c",
            "import os,runpy,sys; p=sys.argv[1]; sys.argv=sys.argv[1:]; sys.path.append(os.path.dirname(p)); runpy.run_path(p,run_name='__main__')",
            runtime.appendingPathComponent("status-service/setup.py").path, operation]
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        return process
    }

    private func result(_ operation: String, runtime: URL) async throws -> String {
        let process = helper(operation, runtime: runtime)
        return try await Task.detached {
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                if process.isRunning { process.terminate() }
            }
            let data = output.fileHandleForReading.readData(ofLength: 4096)
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return "SETUP_BLOCKED" }
            return (try JSONSerialization.jsonObject(with: data) as? [String: String])?["state"] ?? "SETUP_BLOCKED"
        }.value
    }

    private func configureMonitoring(manage: Bool = false) async {
        guard let runtime, !configuring else { return }
        configuring = true
        defer { configuring = false }
        do {
            var state = try await result("status", runtime: runtime)
            if manage && (state == "CONFIGURED" || state == "UPDATE_REQUIRED") {
                let alert = NSAlert()
                alert.messageText = "Remove Codex monitoring?"
                alert.informativeText = "Pulse will remove its own Codex hooks and shell startup block. Reopen Codex normally to finish disconnecting."
                alert.addButton(withTitle: "Cancel")
                alert.addButton(withTitle: "Remove monitoring")
                guard alert.runModal() == .alertSecondButtonReturn else { return }
                guard try await result("remove", runtime: runtime) == "NOT_CONFIGURED" else {
                    throw NSError(domain: "PulseSetup", code: 3, userInfo: [NSLocalizedDescriptionKey: "Removal stopped. The monitoring configuration could not be verified."])
                }
                observerProcess?.terminationHandler = nil
                observerProcess?.terminate()
                observerProcess = nil
                return
            }
            if state == "NOT_CONFIGURED" || state == "RECOVERY_REQUIRED" || state == "UPDATE_REQUIRED" {
                let alert = NSAlert()
                alert.messageText = state == "UPDATE_REQUIRED" ? "Update Codex monitoring" : "Set up Codex monitoring"
                alert.informativeText = "Pulse adds local activity hooks to Codex and a startup block to your shell profile. It reads chat titles and status on this Mac. Quit and reopen ChatGPT. In a local Codex chat, click the Hooks icon beside the message box and review the seven Bamboo Pulse commands. If you have a local project open, Settings → Hooks also lists them."
                alert.addButton(withTitle: "Enable monitoring")
                alert.addButton(withTitle: "Set up later")
                NSApp.activate()
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                guard Bundle.main.bundleURL.standardizedFileURL.path == "/Applications/Bamboo Pulse.app" else {
                    throw NSError(domain: "PulseSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: "Drag Bamboo Pulse to Applications, then reopen it to enable monitoring."])
                }
                state = try await result("install", runtime: runtime)
            }
            if state == "EXISTING_OBSERVER" {
                do {
                    try await offerExistingMonitoring()
                    return
                } catch {}
                throw NSError(domain: "PulseSetup", code: 4, userInfo: [NSLocalizedDescriptionKey: "Pulse found an existing observer or a folder from an earlier setup. Quit ChatGPT and Pulse, then try again. If this repeats, keep the existing files and contact support."])
            }
            guard state == "CONFIGURED" else {
                throw NSError(domain: "PulseSetup", code: 2, userInfo: [NSLocalizedDescriptionKey: "Setup could not verify the monitoring files. Check the installed app and existing Codex configuration before trying again."])
            }
            let process = helper("monitor", runtime: runtime)
            process.terminationHandler = { [weak self] child in
                Task { @MainActor in
                    guard self?.observerProcess === child else { return }
                    self?.observerProcess = nil
                    let alert = NSAlert()
                    alert.messageText = "Codex monitoring stopped"
                    alert.informativeText = "Open Pulse Settings and choose Manage monitoring to retry. If another observer is running, close it first."
                    alert.runModal()
                }
            }
            try process.run()
            observerProcess = process
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func willSleep() { driver?.stop() }
    @objc private func didWake() { driver?.start() }

    func applicationDidBecomeActive(_ notification: Notification) {
        Task { @MainActor [weak attention] in await attention?.refreshAuthorization() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        driver?.stop()
        observerProcess?.terminationHandler = nil
        if observerProcess?.isRunning == true { observerProcess?.terminate() }
        attention?.stop()
        menuBar?.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}

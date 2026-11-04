import AppKit
import Observation
import SwiftUI
import PulseCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private let preferences: DisplayPreferences

    init(store: MonitorStore, preferences: DisplayPreferences, attention: NeedsYouNotifications, manageSetup: (() -> Void)? = nil, usesExistingMonitoring: Bool = false) {
        self.preferences = preferences
        let content = NSHostingController(rootView: SettingsView(preferences: preferences, store: store, attention: attention, manageSetup: manageSetup, usesExistingMonitoring: usesExistingMonitoring))
        content.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: content)
        window.title = "Bamboo Pulse Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.center()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(store:preferences:)") }

    func present() {
        NSApp.activate()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func updateAppearance() {
        withObservationTracking {
            window?.appearance = preferences.appearance.nativeAppearance
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.updateAppearance() }
        }
    }
}

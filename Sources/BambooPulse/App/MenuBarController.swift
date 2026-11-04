import AppKit
import Observation
import SwiftUI
import PulseCore

@MainActor
final class MenuBarController: NSObject {
    private let store: MonitorStore
    private let preferences: DisplayPreferences
    private let attention: NeedsYouNotifications
    private let item: NSStatusItem
    private let button = NSButton()
    private let popover = NSPopover()
    private var stopped = false
    private var displayedSummary: MenuBarSummary?
    private var animationTimer: Timer?
    private var systemAwake = true
    private var screensAwake = true

    init(store: MonitorStore, preferences: DisplayPreferences, navigation: SessionNavigationController,
         attention: NeedsYouNotifications, openSettings: @escaping () -> Void) {
        self.store = store
        self.preferences = preferences
        self.attention = attention
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        button.isBordered = false
        button.font = .menuBarFont(ofSize: 0)
        button.imagePosition = .imageLeading
        button.image = BambooGlyph.menuBarImage

        // The system NSStatusBarButton re-enters layout during scene attachment on macOS 27.
        // A public custom status view avoids that path without changing the SwiftUI popover.
        item.view = button
        observeAnimationEnvironment()
        if #available(macOS 27.0, *) {
            item.target = self
            item.action = #selector(togglePopover)
        } else {
            button.target = self
            button.action = #selector(togglePopover)
        }

        let content = NSHostingController(rootView: MonitorPopover(store: store, preferences: preferences,
            openSession: { [weak self] session in
                self?.closePopover()
                navigation.activate(session, synthetic: store.isSynthetic)
            }, closePopover: { [weak self] in self?.closePopover() }, openSettings: { [weak self] in
                self?.closePopover()
                openSettings()
            }, attention: attention))
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content
        popover.behavior = .transient
        updateLabel()
        updateAppearance()
        Task { @MainActor [weak self] in self?.updateAnimation() }
    }

    private func updateAppearance() {
        guard !stopped else { return }
        withObservationTracking {
            popover.appearance = preferences.appearance.nativeAppearance
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.updateAppearance() }
        }
    }

    private func updateLabel() {
        guard !stopped else { return }
        withObservationTracking {
            let summary = MenuBarSummary(states: store.sessions.map(\.state), health: store.health, isSynthetic: store.isSynthetic)
            guard summary != displayedSummary else { return }
            displayedSummary = summary
            button.attributedTitle = MenuBarTitle.attributedString(for: summary)
            button.toolTip = summary.toolTip
            let width = max(24, ceil(button.fittingSize.width) + 8)
            button.setFrameSize(NSSize(width: width, height: NSStatusBar.system.thickness))
            item.length = width
            updateAnimation()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.updateLabel() }
        }
    }

    private var canAnimate: Bool {
        guard !stopped, let summary = displayedSummary else { return false }
        return MenuBarTitle.motionEnabled(for: summary,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            isVisible: button.window?.isVisible == true
                && button.window?.occlusionState.contains(.visible) == true
                && !button.isHiddenOrHasHiddenAncestor,
            isAwake: systemAwake && screensAwake)
    }

    private func updateAnimation() {
        if canAnimate {
            guard animationTimer == nil else { return }
            let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.advanceAnimation() }
            }
            timer.tolerance = 0.01
            animationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else {
            let wasAnimating = animationTimer != nil
            animationTimer?.invalidate()
            animationTimer = nil
            if wasAnimating, let summary = displayedSummary, !stopped {
                button.attributedTitle = MenuBarTitle.attributedString(for: summary)
            }
        }
    }

    private func advanceAnimation() {
        guard canAnimate, let summary = displayedSummary else {
            updateAnimation()
            return
        }
        // Only replace fixed-size badge frames. Counts, width and accessible text
        // are updated by updateLabel when the underlying summary changes.
        button.attributedTitle = MenuBarTitle.attributedString(for: summary, at: Date())
    }

    private func observeAnimationEnvironment() {
        NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged),
            name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(animationEnvironmentChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(self, selector: #selector(animationEnvironmentChanged), name: name, object: nil)
        }
    }

    @objc private func windowVisibilityChanged(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === button.window else { return }
        updateAnimation()
    }

    @objc private func animationEnvironmentChanged(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.willSleepNotification: systemAwake = false
        case NSWorkspace.didWakeNotification: systemAwake = true
        case NSWorkspace.screensDidSleepNotification: screensAwake = false
        case NSWorkspace.screensDidWakeNotification: screensAwake = true
        default: break
        }
        updateAnimation()
    }

    @objc private func togglePopover() {
        attention.navigationNotice = nil
        if popover.isShown { closePopover() }
        else { showPopover() }
    }

    func presentFromNotification() { showPopover() }

    private func closePopover() {
        popover.performClose(nil)
    }

    private func showPopover() {
        guard !stopped, !popover.isShown else { return }
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func stop() {
        stopped = true
        animationTimer?.invalidate()
        animationTimer = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        closePopover()
        NSStatusBar.system.removeStatusItem(item)
    }
}

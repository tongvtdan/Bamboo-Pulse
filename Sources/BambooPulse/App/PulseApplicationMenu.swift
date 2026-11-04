import AppKit

@MainActor
final class PulseApplicationMenu: NSObject {
    let menu = NSMenu()
    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        super.init()
        let application = NSMenuItem()
        let applicationMenu = NSMenu(title: "Bamboo Pulse")
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        applicationMenu.addItem(settings)
        applicationMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Bamboo Pulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        applicationMenu.addItem(quit)
        application.submenu = applicationMenu
        menu.addItem(application)
        let window = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: ""))
        window.submenu = windowMenu
        menu.addItem(window)
    }

    @objc private func showSettings() { openSettings() }
}

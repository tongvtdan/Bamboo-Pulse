import AppKit
import SwiftUI

// NSPopover retains its hosting controller after dismissal. Observe its actual
// window so a retained SwiftUI view cannot keep an animation clock running.
struct BambooMotionVisibility: NSViewRepresentable {
    let update: (Bool) -> Void

    func makeNSView(context: Context) -> VisibilityView {
        VisibilityView(update: update)
    }

    func updateNSView(_ nsView: VisibilityView, context: Context) {}

    final class VisibilityView: NSView {
        private let update: (Bool) -> Void

        init(update: @escaping (Bool) -> Void) {
            self.update = update
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged),
                    name: NSWindow.didChangeOcclusionStateNotification, object: window)
            }
            visibilityChanged()
        }

        override func viewDidHide() {
            super.viewDidHide()
            visibilityChanged()
        }

        override func viewDidUnhide() {
            super.viewDidUnhide()
            visibilityChanged()
        }

        @objc private func visibilityChanged() {
            // Defer the binding update out of AppKit/SwiftUI layout callbacks.
            Task { @MainActor [weak self] in
                guard let self else { return }
                update(window?.isVisible == true && window?.occlusionState.contains(.visible) == true
                       && !isHiddenOrHasHiddenAncestor)
            }
        }
    }
}

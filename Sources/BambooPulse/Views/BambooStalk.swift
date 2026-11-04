import SwiftUI
import PulseCore

struct BambooStalk: View {
    let state: SessionState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 3) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !motionEnabled)) { context in
                BambooStatusArtwork(state: state,
                    phase: motionEnabled ? BambooMotion.phase(at: context.date, state: state) : nil)
            }
            ZStack(alignment: .leading) {
                Color.clear
                if let activeSection {
                    Capsule().fill(.primary.opacity(0.75))
                        .frame(width: 16, height: 2)
                        .offset(x: CGFloat(activeSection) * 32 + 8)
                }
            }
            .frame(width: 96, height: 2)
        }
        .background(BambooMotionVisibility { isVisible = $0 })
    }

    private var motionEnabled: Bool {
        BambooMotion.isEnabled(state: state, reduceMotion: reduceMotion, isVisible: isVisible)
    }

    private var activeSection: Int? {
        switch state {
        case .needsAttention: 0
        case .turnEnded: 1
        case .working: 2
        case .unknown: nil
        }
    }
}

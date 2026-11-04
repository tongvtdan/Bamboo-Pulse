import SwiftUI
import PulseCore

struct StatusBadge: View {
    let state: SessionState
    var size: CGFloat = 26
    var animates = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    private var color: Color {
        switch state {
        case .needsAttention: Color(red: 1, green: 0.32, blue: 0.22)
        case .turnEnded: Color(red: 0.96, green: 0.67, blue: 0.08)
        case .working: Color(red: 0.31, green: 0.69, blue: 0.25)
        case .unknown: .gray
        }
    }

    var body: some View {
        Group {
            if animates {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !motionEnabled)) { context in
                    artwork(phase: motionEnabled ? BambooMotion.phase(at: context.date, state: state) : nil)
                }
                .background(BambooMotionVisibility { isVisible = $0 })
            } else {
                artwork(phase: nil)
            }
        }
    }

    private var motionEnabled: Bool {
        BambooMotion.isEnabled(state: state, reduceMotion: reduceMotion, isVisible: isVisible)
    }

    func artwork(phase: Double?) -> some View {
        Circle()
            .fill(color.gradient)
            .overlay {
                if let phase {
                    highlight(phase: phase)
                        .clipShape(Circle())
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if state != .working {
                    Image(systemName: state == .needsAttention ? "exclamationmark" : state == .turnEnded ? "minus" : "questionmark")
                        .font(.system(size: size * 0.55, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .overlay { Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5) }
            .frame(width: size, height: size)
    }

    @ViewBuilder private func highlight(phase: Double) -> some View {
        if state == .needsAttention {
            Color.white.opacity(BambooMotion.pulseOpacity(phase: phase))
        } else if state == .working {
            let bandWidth = size * 0.45
            LinearGradient(colors: [.clear, .white.opacity(0.42), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: bandWidth, height: size)
                .offset(x: (size + bandWidth) * phase - bandWidth)
                .frame(width: size, height: size, alignment: .leading)
        }
    }
}

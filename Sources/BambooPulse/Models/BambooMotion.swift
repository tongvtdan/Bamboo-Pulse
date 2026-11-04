import Foundation
import PulseCore

enum BambooMotion {
    static func isEnabled(state: SessionState, reduceMotion: Bool, isVisible: Bool) -> Bool {
        isVisible && !reduceMotion && (state == .working || state == .needsAttention)
    }

    static func phase(at date: Date, state: SessionState) -> Double {
        let period = state == .needsAttention ? 2.4 : 1.8
        let cycles = date.timeIntervalSinceReferenceDate / period
        return cycles - floor(cycles)
    }

    static func pulseOpacity(phase: Double) -> Double {
        0.04 + 0.24 * (1 - cos(phase * 2 * .pi)) / 2
    }
}

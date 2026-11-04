import Foundation
import Testing
import PulseCore

@Suite("Bamboo status motion")
struct BambooMotionTests {
    @Test(arguments: SessionState.allCases)
    func reducedMotionAndHiddenViewsAreAlwaysStill(_ state: SessionState) {
        #expect(!BambooMotion.isEnabled(state: state, reduceMotion: true, isVisible: true))
        #expect(!BambooMotion.isEnabled(state: state, reduceMotion: false, isVisible: false))
    }

    @Test func onlyActiveStatesAnimateAndUnknownStopsImmediately() {
        let sequence: [SessionState] = [.working, .unknown, .needsAttention, .turnEnded, .working]
        #expect(sequence.map { BambooMotion.isEnabled(state: $0, reduceMotion: false, isVisible: true) }
                == [true, false, true, false, true])
    }

    @Test func pulseIsContinuousAndNeverErasesTheBaseColor() {
        #expect(abs(BambooMotion.pulseOpacity(phase: 0) - BambooMotion.pulseOpacity(phase: 1)) < 0.0001)
        #expect(BambooMotion.pulseOpacity(phase: 0.5) > BambooMotion.pulseOpacity(phase: 0))
        for step in 0...100 {
            #expect((0.04...0.28).contains(BambooMotion.pulseOpacity(phase: Double(step) / 100)))
        }
    }

    @Test func phaseWrapsAcrossBothAnimationPeriods() {
        for (state, period) in [(SessionState.working, 1.8), (.needsAttention, 2.4)] {
            let start = Date(timeIntervalSinceReferenceDate: 0)
            #expect(BambooMotion.phase(at: start, state: state) == 0)
            #expect(abs(BambooMotion.phase(at: start.addingTimeInterval(period / 2), state: state) - 0.5) < 0.0001)
            #expect(BambooMotion.phase(at: start.addingTimeInterval(period), state: state) == 0)
        }
    }
}

import AppKit
import PulseCore
import Testing

@Suite("Menu-bar status counts") @MainActor
struct MenuBarSummaryTests {
    @Test func mixedCountsUsePriorityOrderAndExactTooltipTotals() {
        let summary = MenuBarSummary(states: [.working, .needsAttention, .unknown, .working, .turnEnded, .needsAttention],
                                     health: .monitoring, isSynthetic: false)
        #expect(summary.groups.map(\.state) == [.needsAttention, .turnEnded, .working, .unknown])
        #expect(summary.groups.map(\.count) == [2, 1, 2, 1])
        #expect(summary.toolTip == "Bamboo Pulse. Needs you: 2. Turn ended: 1. Working: 2. Unknown: 1.")
    }

    @Test(arguments: SessionState.allCases)
    func singleStateOmitsAllZeroGroups(_ state: SessionState) {
        let summary = MenuBarSummary(states: [state], health: .monitoring, isSynthetic: false)
        #expect(summary.groups == [MenuBarStatusCount(state: state, count: 1)])
    }

    @Test(arguments: [FeedHealth.connecting, .unavailable, .invalid, .stale, .synthetic])
    func unavailableHealthNeverDisplaysRetainedCounts(_ health: FeedHealth) {
        let summary = MenuBarSummary(states: [.needsAttention, .working, .unknown], health: health, isSynthetic: false)
        #expect(summary.isUnavailable)
        #expect(summary.groups.isEmpty)
        #expect(summary.toolTip.contains("Status unknown"))
        #expect(!summary.toolTip.contains("Working:"))
        #expect(!summary.toolTip.contains("No sessions observed"))
        #expect(MenuBarTitle.attributedString(for: summary).string.filter(\.isNumber).isEmpty)
    }

    @Test func availableEmptyFeedMeansZeroRatherThanUnavailable() {
        let summary = MenuBarSummary(states: [], health: .monitoring, isSynthetic: false)
        #expect(!summary.isUnavailable)
        #expect(summary.groups.isEmpty)
        #expect(summary.toolTip.contains("No sessions observed"))
        #expect(MenuBarTitle.attributedString(for: summary).string.contains("0"))
    }

    @Test func largeCountsAreCappedOnlyVisually() {
        let summary = MenuBarSummary(states: Array(repeating: .working, count: 128), health: .monitoring, isSynthetic: false)
        #expect(summary.groups.first?.displayCount == "99+")
        #expect(summary.toolTip.contains("Working: 128"))
        #expect(MenuBarTitle.attributedString(for: summary).string.contains("99+"))
    }

    @Test func previewAlwaysKeepsDemoAndSyntheticMeaning() {
        let summary = MenuBarSummary(states: SessionState.allCases, health: .synthetic, isSynthetic: true)
        #expect(!summary.isUnavailable)
        #expect(summary.groups.count == 4)
        #expect(MenuBarTitle.attributedString(for: summary).string.hasPrefix("Demo"))
        #expect(summary.toolTip.contains("Sample sessions; no live activity"))
    }

    @Test func equalCountsDoNotChangeThePresentation() {
        let first = MenuBarSummary(states: [.working, .needsAttention], health: .monitoring, isSynthetic: false)
        let reordered = MenuBarSummary(states: [.needsAttention, .working], health: .monitoring, isSynthetic: false)
        let changed = MenuBarSummary(states: [.unknown, .needsAttention], health: .monitoring, isSynthetic: false)
        #expect(first == reordered)
        #expect(first != changed)
    }

    @Test func nativeTitleFitsItsMenuBarBudget() {
        let distributions: [[SessionState]] = [[], [.working], Array(repeating: .working, count: 128),
            SessionState.allCases.flatMap { Array(repeating: $0, count: 32) }]
        for states in distributions {
            for preview in [false, true] {
                let summary = MenuBarSummary(states: states, health: preview ? .synthetic : .monitoring, isSynthetic: preview)
                let button = NSButton()
                button.isBordered = false
                button.image = NSImage(size: NSSize(width: 9, height: 18))
                button.imagePosition = .imageLeading
                button.attributedTitle = MenuBarTitle.attributedString(for: summary)
                #expect(button.fittingSize.width + 8 <= 220)
            }
        }
    }

    @Test func motionStopsForReducedMotionHiddenAndSleepingMenuBars() {
        let summary = MenuBarSummary(states: [.working, .needsAttention], health: .monitoring, isSynthetic: false)
        #expect(MenuBarTitle.motionEnabled(for: summary, reduceMotion: false, isVisible: true, isAwake: true))
        #expect(!MenuBarTitle.motionEnabled(for: summary, reduceMotion: true, isVisible: true, isAwake: true))
        #expect(!MenuBarTitle.motionEnabled(for: summary, reduceMotion: false, isVisible: false, isAwake: true))
        #expect(!MenuBarTitle.motionEnabled(for: summary, reduceMotion: false, isVisible: true, isAwake: false))
    }

    @Test func motionStopsImmediatelyWhenActiveEvidenceIsLostOrEnds() {
        for health in [FeedHealth.connecting, .unavailable, .invalid, .stale] {
            let summary = MenuBarSummary(states: [.working, .needsAttention], health: health, isSynthetic: false)
            #expect(!MenuBarTitle.motionEnabled(for: summary, reduceMotion: false, isVisible: true, isAwake: true))
        }
        for states: [SessionState] in [[], [.unknown], [.turnEnded], [.turnEnded, .unknown]] {
            let summary = MenuBarSummary(states: states, health: .monitoring, isSynthetic: false)
            #expect(!MenuBarTitle.motionEnabled(for: summary, reduceMotion: false, isVisible: true, isAwake: true))
        }
    }

    @Test func animatedTitlesPreserveCountsDimensionsAndPreviewMeaning() {
        for synthetic in [false, true] {
            let summary = MenuBarSummary(states: SessionState.allCases.flatMap { Array(repeating: $0, count: 32) },
                health: synthetic ? .synthetic : .monitoring, isSynthetic: synthetic)
            let still = MenuBarTitle.attributedString(for: summary)
            for frame in 0..<144 {
                let animated = MenuBarTitle.attributedString(for: summary, at: Date(timeIntervalSinceReferenceDate: Double(frame) / 20))
                #expect(animated.string == still.string)
                #expect(animated.size() == still.size())
            }
            #expect(still.string.hasPrefix("Demo") == synthetic)
        }
    }

    @Test func animationReusesFramesAndNeverAnimatesUnknownOrEndedBadges() {
        func image(_ state: SessionState, at date: Date?) -> NSImage {
            let summary = MenuBarSummary(states: [state], health: .monitoring, isSynthetic: false)
            return (MenuBarTitle.attributedString(for: summary, at: date)
                .attribute(.attachment, at: 0, effectiveRange: nil) as! NSTextAttachment).image!
        }
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for state in [SessionState.unknown, .turnEnded] {
            #expect(image(state, at: nil) === image(state, at: start.addingTimeInterval(0.9)))
        }
        for state in [SessionState.working, .needsAttention] {
            #expect(image(state, at: start) === image(state, at: start))
            #expect(image(state, at: start) !== image(state, at: start.addingTimeInterval(0.9)))
        }
    }

    @Test func unavailableAndEmptyTitlesStayStaticEvenWithAnAnimationDate() {
        for health in [FeedHealth.unavailable, .monitoring] {
            let summary = MenuBarSummary(states: [], health: health, isSynthetic: false)
            let still = MenuBarTitle.attributedString(for: summary)
            let animated = MenuBarTitle.attributedString(for: summary, at: Date())
            #expect(still.string == animated.string)
            #expect(still.size() == animated.size())
            let stillBadge = still.attribute(.attachment, at: 0, effectiveRange: nil) as! NSTextAttachment
            let animatedBadge = animated.attribute(.attachment, at: 0, effectiveRange: nil) as! NSTextAttachment
            #expect(stillBadge.image === animatedBadge.image)
        }
    }
}

import PulseCore

struct MenuBarSummary: Equatable {
    let groups: [MenuBarStatusCount]
    let health: FeedHealth
    let isSynthetic: Bool

    var isUnavailable: Bool { !isSynthetic && health != .monitoring }

    init(states: [SessionState], health: FeedHealth, isSynthetic: Bool) {
        self.health = health
        self.isSynthetic = isSynthetic
        if !isSynthetic && health != .monitoring {
            groups = []
        } else {
            let order: [SessionState] = [.needsAttention, .turnEnded, .working, .unknown]
            groups = order.compactMap { state in
                let count = states.filter { $0 == state }.count
                return count > 0 ? MenuBarStatusCount(state: state, count: count) : nil
            }
        }
    }

    var toolTip: String {
        let context = isSynthetic
            ? "Bamboo Pulse demo. Sample sessions; no live activity."
            : "Bamboo Pulse."
        if isUnavailable { return "\(context) Status unknown." }
        if groups.isEmpty { return "\(context) No sessions observed." }
        return context + " " + groups.map { "\($0.state.label): \($0.count)" }.joined(separator: ". ") + "."
    }
}

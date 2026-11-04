import PulseCore

struct MenuBarStatusCount: Equatable {
    let state: SessionState
    let count: Int

    var displayCount: String { count > 99 ? "99+" : String(count) }
}

import PulseCore

/// Presentation only: accepted store state remains the sole source of observation health.
struct MonitoringStatus {
    let headline: String
    let detail: String
    let inventory: String
    let recovery: String?
    let showsPopoverGuidance: Bool

    let coverage = "Pulse shows supported Codex sessions on this Mac."

    @MainActor init(store: MonitorStore) {
        showsPopoverGuidance = store.isSynthetic || store.health != .monitoring || store.sessions.isEmpty

        if store.isSynthetic {
            headline = "Demo mode"
            detail = "These are sample sessions, not your live activity."
            inventory = "\(store.sessions.count) sample sessions"
            recovery = nil
            return
        }

        if store.health == .monitoring {
            inventory = "\(store.sessions.count) \(store.sessions.count == 1 ? "session" : "sessions") observed"
            headline = store.sessions.isEmpty ? "No sessions observed" : "Connected"
            detail = store.sessions.isEmpty
                ? "No Codex sessions are being reported to Pulse right now."
                : "Pulse can’t determine the current status of sessions marked Unknown."
            recovery = nil
            return
        }

        inventory = store.sessions.isEmpty
            ? "Current session count unknown"
            : "\(store.sessions.count) previous \(store.sessions.count == 1 ? "session" : "sessions") · status unknown"
        switch store.health {
        case .connecting:
            headline = "Connecting…"
            detail = "Waiting for session updates."
            recovery = nil
        case .invalid:
            headline = "Couldn’t read session updates"
            detail = "The latest update couldn’t be read. Previous statuses are now Unknown."
            recovery = "Pulse will try again automatically."
        case .stale:
            headline = "Updates paused"
            detail = "Session updates are out of date. Previous statuses are now Unknown."
            recovery = "Pulse will try again automatically."
        case .unavailable, .synthetic, .monitoring:
            headline = "Connection unavailable"
            detail = "Pulse can’t get session updates right now."
            recovery = "Pulse will reconnect automatically when updates are available."
        }
    }
}

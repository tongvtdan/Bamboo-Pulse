import AppKit
import SwiftUI
import PulseCore

struct MonitorPopover: View {
    let store: MonitorStore
    let preferences: DisplayPreferences
    let openSession: (Session) -> Void
    let closePopover: () -> Void
    let openSettings: () -> Void
    var attention: NeedsYouNotifications? = nil
    @FocusState private var focusedSessionID: String?

    var body: some View {
        let status = MonitoringStatus(store: store)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Bamboo Pulse").font(.system(size: 22, weight: .bold))
                    HStack(spacing: 8) {
                        Text(status.headline)
                            .font(.system(size: 14)).foregroundStyle(.secondary)
                        if store.isSynthetic {
                            Text("DEMO").font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(.orange.opacity(0.15), in: Capsule())
                        }
                    }
                }
                Spacer(minLength: 12)
                Text(store.summary).font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }
            .padding(.bottom, 16)
            Divider()
            if let notice = attention?.navigationNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
            }
            if status.showsPopoverGuidance {
                VStack(alignment: .leading, spacing: 8) {
                    Text(status.detail)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 16)
            }
            if !store.sessions.isEmpty {
                ScrollViewReader { proxy in
                  ScrollView {
                    VStack(spacing: 0) {
                        ForEach(store.sessions) { session in
                            SessionRow(session: session, showAlias: preferences.showAliases, viewType: preferences.viewType,
                                showStatus: preferences.showSessionStatus,
                                isSynthetic: store.isSynthetic,
                                isFocused: focusedSessionID == session.id,
                                activate: { openSession(session) })
                                .focused($focusedSessionID, equals: session.id)
                            if session.id != store.sessions.last?.id { Divider() }
                        }
                    }
                    .padding(.horizontal, 2)
                  }
                  .frame(height: sessionListHeight)
                  .onChange(of: focusedSessionID) { _, id in
                      if let id { proxy.scrollTo(id) }
                  }
                }
                .defaultFocus($focusedSessionID, store.isSynthetic ? nil : store.sessions.first?.id)
                .onMoveCommand { direction in
                    if direction == .down { moveFocus(by: 1) }
                    else if direction == .up { moveFocus(by: -1) }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Button("Settings…", action: openSettings).keyboardShortcut(",").help("Display preferences and monitoring help.")
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
                }
                .controlSize(.regular)
                Text("Working is activity, not success.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.top, 14)
        }
        .padding(22)
        .frame(width: preferences.viewType.popoverWidth)
        .onExitCommand(perform: closePopover)
        .onAppear { if !store.isSynthetic { focusedSessionID = store.sessions.first?.id } }
        .onChange(of: store.sessions.map(\.id)) { _, ids in
            if let id = focusedSessionID, !ids.contains(id) { focusedSessionID = nil }
        }
    }

    private func moveFocus(by offset: Int) {
        guard !store.isSynthetic, !store.sessions.isEmpty else { return }
        let ids = store.sessions.map(\.id)
        let index = focusedSessionID.flatMap { ids.firstIndex(of: $0) }
        focusedSessionID = ids[index.map { ($0 + offset + ids.count) % ids.count } ?? (offset > 0 ? 0 : ids.count - 1)]
    }

    private var sessionListHeight: CGFloat {
        let rowHeight = preferences.viewType.rowHeight
        return max(0, min(CGFloat(store.sessions.count) * (rowHeight + 1) - 1, rowHeight * 4 + 3))
    }
}

#Preview("Synthetic sessions") {
    MonitorPopover(store: MonitorStore(synthetic: true), preferences: DisplayPreferences(),
                   openSession: { _ in }, closePopover: {}, openSettings: {})
}

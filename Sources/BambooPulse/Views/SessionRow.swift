import SwiftUI
import PulseCore

struct SessionRow: View {
    let session: Session
    let showAlias: Bool
    let viewType: PopoverViewType
    let showStatus: Bool
    let isSynthetic: Bool
    let isFocused: Bool
    let activate: () -> Void
    @State private var isVisible = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isVisible || !showStatus || session.statusTiming == nil)) { _ in
            row(at: .now)
        }
        .background(BambooMotionVisibility { isVisible = $0 })
    }

    private func row(at time: MonitorTime) -> some View {
        Button(action: activate) {
            content(at: time)
                .contentShape(Rectangle())
                .background(isFocused ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(isFocused ? Color.accentColor : .clear, lineWidth: 1.5) }
        }
        .buttonStyle(.plain)
        .disabled(isSynthetic)
        .onKeyPress(.return) {
            guard !isSynthetic else { return .ignored }
            activate()
            return .handled
        }
        .help("\(session.title) · \(session.provider) · \(session.alias) · \(session.state.label). \(timingHint(at: time))\(actionHint)")

    }

    private var actionHint: String {
        if isSynthetic { return "Sample session. Opening a real chat is unavailable." }
        return "Open this chat in Codex"
    }

    func subtitle(at time: MonitorTime) -> String {
        metadata + statusSuffix(at: time)
    }

    private var metadata: String {
        var parts = [session.provider]
        if showAlias { parts.append(session.alias) }
        return parts.joined(separator: " · ")
    }

    private func statusSuffix(at time: MonitorTime) -> String {
        guard showStatus else { return "" }
        var suffix = " · \(session.state.label)"
        if let duration = session.statusTiming?.label(at: time) { suffix += " · \(duration)" }
        return suffix
    }

    private func timingHint(at time: MonitorTime) -> String {
        guard showStatus, let timing = session.statusTiming, let duration = timing.label(at: time) else { return "" }
        return "Continuously observed for \(duration). "
            + (timing.isLowerBound ? "The actual status may have started earlier. " : "Measured from the observed status change. ")
    }

    private func content(at time: MonitorTime) -> some View {
        HStack(spacing: 14) {
            if viewType == .normal {
                BambooStalk(state: session.state)
            } else {
                StatusBadge(state: session.state, size: 22, animates: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(String(session.title.prefix(80)))
                    .font(.system(size: viewType == .normal ? 16 : 14, weight: .semibold)).lineLimit(1)
                HStack(spacing: 0) {
                    Text(metadata).lineLimit(1).truncationMode(.tail)
                    Text(statusSuffix(at: time)).fixedSize(horizontal: true, vertical: false)
                }
                    .font(.system(size: viewType == .normal ? 14 : 12)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: viewType.rowHeight)
    }
}

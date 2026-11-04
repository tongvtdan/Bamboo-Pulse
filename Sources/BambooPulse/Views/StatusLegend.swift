import SwiftUI
import PulseCore

struct StatusLegend: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
            GridRow {
                item(.needsAttention, meaning: "Needs your attention")
                item(.turnEnded, meaning: "Turn finished")
            }
            GridRow {
                item(.working, meaning: "Currently active")
                item(.unknown, meaning: "Status unavailable")
            }
        }
        .font(.callout)
    }

    private func item(_ state: SessionState, meaning: String) -> some View {
        HStack(spacing: 8) {
            StatusBadge(state: state, size: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.label)
                Text(meaning).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

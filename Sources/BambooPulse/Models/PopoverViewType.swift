import Foundation

enum PopoverViewType: String, CaseIterable, Identifiable {
    case normal, compact

    var id: String { rawValue }
    var label: String { self == .normal ? "Normal" : "Compact" }
    var rowHeight: CGFloat { self == .normal ? 52 : 48 }
    var popoverWidth: CGFloat { self == .normal ? 420 : 380 }
}

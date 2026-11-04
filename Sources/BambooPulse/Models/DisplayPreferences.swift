import Foundation
import Observation

@MainActor @Observable
final class DisplayPreferences {
    @ObservationIgnored private let defaults: UserDefaults

    var appearance: DisplayAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "display.appearance") }
    }
    var showAliases: Bool {
        didSet { defaults.set(showAliases, forKey: "display.showAliases") }
    }
    var showSessionStatus: Bool {
        didSet { defaults.set(showSessionStatus, forKey: "display.showSessionStatus") }
    }
    var viewType: PopoverViewType {
        didSet { defaults.set(viewType.rawValue, forKey: "display.viewType") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = DisplayAppearance(rawValue: defaults.string(forKey: "display.appearance") ?? "") ?? .system
        showAliases = defaults.object(forKey: "display.showAliases") as? Bool ?? false
        showSessionStatus = defaults.object(forKey: "display.showSessionStatus") as? Bool ?? false
        viewType = PopoverViewType(rawValue: defaults.string(forKey: "display.viewType") ?? "") ?? .normal
    }
}

enum MonitoringSource: String {
    case standalone, existing

    static func selected(defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: "monitoring.source").flatMap(Self.init(rawValue:)) ?? .standalone
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: "monitoring.source")
    }
}

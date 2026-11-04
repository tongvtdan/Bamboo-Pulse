import Foundation
import PulseCore
import AppKit
import Testing

@Suite("Local display preferences") @MainActor
struct DisplayPreferencesTests {
    private func isolatedDefaults() -> (UserDefaults, String) {
        let suite = "BambooPulseTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test func firstLaunchUsesSystemAppearanceWithoutWritingDefaults() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        #expect(preferences.appearance == .system)
        #expect(!preferences.showAliases)
        #expect(!preferences.showSessionStatus)
        #expect(preferences.viewType == .normal)
        #expect(defaults.persistentDomain(forName: suite)?.isEmpty != false)
    }

    @Test func selectionsSurviveAnotherPreferencesLifetime() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = DisplayPreferences(defaults: defaults)
        preferences.appearance = .dark
        preferences.showAliases = true
        preferences.showSessionStatus = true
        preferences.viewType = .compact
        let restored = DisplayPreferences(defaults: defaults)
        #expect(restored.appearance == .dark)
        #expect(restored.showAliases)
        #expect(restored.showSessionStatus)
        #expect(restored.viewType == .compact)
        #expect(defaults.persistentDomain(forName: suite)?.count == 4)
        restored.showSessionStatus = false
        #expect(!DisplayPreferences(defaults: defaults).showSessionStatus)
        #expect(DisplayPreferences(defaults: defaults).showAliases)
        restored.viewType = .normal
        #expect(DisplayPreferences(defaults: defaults).viewType == .normal)
    }

    @Test func invalidStoredValuesFallBackWithoutOverwritingThem() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("future-appearance", forKey: "display.appearance")
        defaults.set("invalid", forKey: "display.showAliases")
        defaults.set("invalid", forKey: "display.showSessionStatus")
        defaults.set("future-view", forKey: "display.viewType")
        let preferences = DisplayPreferences(defaults: defaults)
        #expect(preferences.appearance == .system)
        #expect(!preferences.showAliases)
        #expect(!preferences.showSessionStatus)
        #expect(preferences.viewType == .normal)
        #expect(defaults.string(forKey: "display.appearance") == "future-appearance")
        #expect(defaults.string(forKey: "display.viewType") == "future-view")
        #expect(defaults.string(forKey: "display.showSessionStatus") == "invalid")
    }

    @Test func retiredLegendPreferenceDoesNotSelectAViewOrGetDeleted() {
        let (defaults, suite) = isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: "display.showLegend")
        let preferences = DisplayPreferences(defaults: defaults)
        #expect(preferences.viewType == .normal)
        preferences.viewType = .compact
        #expect(DisplayPreferences(defaults: defaults).viewType == .compact)
        #expect(defaults.object(forKey: "display.showLegend") as? Bool == false)
    }
}

@Suite("Status duration presentation") @MainActor
struct StatusDurationPresentationTests {
    @Test func statusAndDurationHaveRoomInBothLayouts() throws {
        let store = MonitorStore()
        store.receive(try data(packet(rows: [row("TURN_ENDED", alias: "CX9999", remaining: 120000)])), at: time(), epoch: 0)
        let session = try #require(store.sessions.first)
        for type in PopoverViewType.allCases {
            let view = SessionRow(session: session, showAlias: true, viewType: type, showStatus: true,
                                  isSynthetic: false, isFocused: false, activate: {})
            #expect(view.subtitle(at: time(1000)) == "Codex · CX9999 · Turn ended · ≥1s")
            let font = NSFont.monospacedDigitSystemFont(ofSize: type == .normal ? 14 : 12, weight: .regular)
            let required = ("Codex · Turn ended · ≥100h00m" as NSString).size(withAttributes: [.font: font]).width
            let textBudget = type.popoverWidth - 44 - 14 - (type == .normal ? 96 : 22)
            #expect(required < textBudget)
        }
    }

    @Test func subtitleKeepsDurationAfterStatusAndRespectsDisplayChoices() throws {
        let store = MonitorStore()
        store.receive(try data(packet(rows: [row(remaining: 120000)])), at: time(), epoch: 0)
        let session = try #require(store.sessions.first)
        for viewType in PopoverViewType.allCases {
            func view(alias: Bool, status: Bool) -> SessionRow {
                SessionRow(session: session, showAlias: alias, viewType: viewType, showStatus: status,
                           isSynthetic: false, isFocused: false, activate: {})
            }
            #expect(view(alias: false, status: true).subtitle(at: time(1000)) == "Codex · Working · ≥1s")
            #expect(view(alias: true, status: true).subtitle(at: time(1000)) == "Codex · CX1 · Working · ≥1s")
            #expect(view(alias: true, status: false).subtitle(at: time(1000)) == "Codex · CX1")
            #expect(view(alias: false, status: false).subtitle(at: time(1000)) == "Codex")
            #expect(view(alias: false, status: true).subtitle(at: time(2000)) == "Codex · Working")
        }
    }

    @Test func unknownAndSyntheticRowsDoNotShowLiveDurations() throws {
        let store = MonitorStore()
        store.receive(try data(packet(rows: [row("UNKNOWN")])), at: time(), epoch: 0)
        for session in store.sessions + MonitorStore(synthetic: true).sessions {
            let view = SessionRow(session: session, showAlias: false, viewType: .compact, showStatus: true,
                                  isSynthetic: session.id.hasPrefix("sample"), isFocused: false, activate: {})
            #expect(view.subtitle(at: time()) == "Codex · \(session.state.label)")
        }
    }
}

@Suite("Monitoring source selection") @MainActor
struct MonitoringSourceSelectionTests {
    @Test func standaloneIsDefaultAndSelectionIsPerAccountPreference() {
        let name = "BambooPulseSourceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(MonitoringSource.selected(defaults: defaults) == .standalone)
        MonitoringSource.existing.save(defaults: defaults)
        #expect(MonitoringSource.selected(defaults: defaults) == .existing)
        defaults.set("unknown", forKey: "monitoring.source")
        #expect(MonitoringSource.selected(defaults: defaults) == .standalone)
    }
}

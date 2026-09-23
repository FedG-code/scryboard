import Foundation
import Testing
@testable import ScryboardUI

/// Settings shared through the App Group. Older builds wrote fewer keys, and
/// a newer build must read what they left rather than reset everything.
@Suite("Preferences")
struct PreferencesTests {
    @Test("Preferences round-trip")
    func roundTrip() throws {
        let saved = Preferences(order: .usd, direction: .descending, cardSize: .large, copyFormat: .link)
        let data = try JSONEncoder().encode(saved)
        #expect(try JSONDecoder().decode(Preferences.self, from: data) == saved)
    }

    @Test("Keys an older build never wrote take their defaults")
    func missingKeysDefault() throws {
        let older = Data(#"{"order":"name","direction":"asc","cardSize":"small"}"#.utf8)
        let loaded = try JSONDecoder().decode(Preferences.self, from: older)
        #expect(loaded == Preferences(order: .name, direction: .ascending, cardSize: .small, copyFormat: .image))
    }

    @Test("The store hands back what it was given, defaults when empty")
    func store() {
        let suite = "PreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        #expect(store.load() == Preferences())
        let custom = Preferences(cardSize: .small, copyFormat: .text)
        store.save(custom)
        #expect(store.load() == custom)
    }
}

import Foundation
import LanguifyKit
import Observation

/// Owns user preferences, the learner profile and the local usage ledger,
/// persisted as JSON in UserDefaults. None of this contains conversation data.
@Observable
final class PreferencesStore {
    private let defaults: UserDefaults
    private enum Key {
        static let preferences = "languify.preferences.v1"
        static let profile = "languify.profile.v1"
        static let ledger = "languify.usage.v1"
        static let installID = "languify.install-id"
    }

    var preferences: UserPreferences {
        didSet { save(preferences, Key.preferences) }
    }

    var profile: LearnerProfile {
        didSet { save(profile, Key.profile) }
    }

    var ledger: UsageLedger {
        didSet { save(ledger, Key.ledger) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let prefs = Self.load(UserPreferences.self, Key.preferences, defaults) ?? UserPreferences()
        self.preferences = prefs
        self.profile = Self.load(LearnerProfile.self, Key.profile, defaults) ?? .seeded(from: prefs.selfRating)
        self.ledger = Self.load(UsageLedger.self, Key.ledger, defaults) ?? UsageLedger()
    }

    var language: HeritageLanguage { preferences.language }

    func learnerSnapshot(recentWords: [String]) -> LearnerSnapshot {
        LearnerSnapshot(
            comprehension: preferences.selfRating.comprehension,
            speaking: preferences.selfRating.speaking,
            reading: preferences.selfRating.reading,
            recentWords: recentWords
        )
    }

    func completeOnboarding() {
        profile = .seeded(from: preferences.selfRating)
        preferences.hasCompletedOnboarding = true
    }

    /// Erases preferences, profile and usage. Used by "Delete all data".
    func resetAll() {
        for key in [Key.preferences, Key.profile, Key.ledger] { defaults.removeObject(forKey: key) }
        preferences = UserPreferences()
        profile = .seeded(from: preferences.selfRating)
        ledger = UsageLedger()
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            Log.data.error("Failed to save \(key, privacy: .public)")
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

import Foundation
import TouchCore

enum SettingsStore {
    private static let settingsKey = "touchSettings"
    private static let onboardingKey = "onboardingCompleted"

    static func load() -> TouchSettings {
        TouchSettings.decode(UserDefaults.standard.data(forKey: settingsKey))
    }

    static func save(_ settings: TouchSettings) {
        UserDefaults.standard.set(settings.encoded(), forKey: settingsKey)
    }

    static var onboardingCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: onboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: onboardingKey) }
    }
}

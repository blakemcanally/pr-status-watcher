import Foundation

// MARK: - Settings Store (UserDefaults)

/// Persists app settings to UserDefaults. Accepts a custom UserDefaults
/// instance for test isolation.
final class SettingsStore: SettingsStoreProtocol {
    private let defaults: UserDefaults

    static let pollingKey = "polling_interval"
    static let collapsedReposKey = "collapsed_repos"
    static let filterSettingsKey = "filter_settings"

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func loadRefreshInterval() -> Int {
        let saved = defaults.integer(forKey: Self.pollingKey)
        return saved > 0 ? saved : 60
    }

    func saveRefreshInterval(_ value: Int) {
        defaults.set(value, forKey: Self.pollingKey)
    }

    func loadCollapsedRepos() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.collapsedReposKey) ?? [])
    }

    func saveCollapsedRepos(_ value: Set<String>) {
        defaults.set(Array(value), forKey: Self.collapsedReposKey)
    }

    func loadFilterSettings() -> FilterSettings {
        guard let data = defaults.data(forKey: Self.filterSettingsKey),
              let settings = try? JSONDecoder().decode(FilterSettings.self, from: data) else {
            return FilterSettings()
        }
        return settings
    }

    func saveFilterSettings(_ value: FilterSettings) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: Self.filterSettingsKey)
        }
    }
}

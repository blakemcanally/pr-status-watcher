import Foundation
import os

// MARK: - Settings Store (UserDefaults)

/// Persists app settings to UserDefaults. Accepts a custom UserDefaults
/// instance for test isolation.
final class SettingsStore: SettingsStoreProtocol {
    private let logger = Logger(subsystem: "PRStatusWatcher", category: "SettingsStore")
    private let defaults: UserDefaults

    static let pollingKey = AppConstants.DefaultsKey.pollingInterval
    static let collapsedReposKey = AppConstants.DefaultsKey.collapsedRepos
    static let filterSettingsKey = AppConstants.DefaultsKey.filterSettings
    static let collapsedReadinessSectionsKey = AppConstants.DefaultsKey.collapsedReadinessSections

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func loadRefreshInterval() -> Int {
        let saved = defaults.integer(forKey: Self.pollingKey)
        let result = saved > 0 ? saved : AppConstants.Defaults.refreshInterval
        logger.debug("loadRefreshInterval: \(result)s")
        return result
    }

    func saveRefreshInterval(_ value: Int) {
        defaults.set(value, forKey: Self.pollingKey)
        logger.debug("saveRefreshInterval: \(value)s")
    }

    func loadCollapsedRepos() -> Set<String> {
        let result = Set(defaults.stringArray(forKey: Self.collapsedReposKey) ?? [])
        logger.debug("loadCollapsedRepos: \(result.count) repos")
        return result
    }

    func saveCollapsedRepos(_ value: Set<String>) {
        defaults.set(Array(value), forKey: Self.collapsedReposKey)
        logger.debug("saveCollapsedRepos: \(value.count) repos")
    }

    func loadFilterSettings() -> FilterSettings {
        guard let data = defaults.data(forKey: Self.filterSettingsKey) else {
            logger.info("loadFilterSettings: no saved data, using defaults")
            return FilterSettings()
        }
        do {
            return try JSONDecoder().decode(FilterSettings.self, from: data)
        } catch {
            logger.error("loadFilterSettings: decode failed: \(error.localizedDescription, privacy: .public)")
            return FilterSettings()
        }
    }

    func saveFilterSettings(_ value: FilterSettings) {
        do {
            let data = try JSONEncoder().encode(value)
            defaults.set(data, forKey: Self.filterSettingsKey)
        } catch {
            logger.error("saveFilterSettings: encode failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadCollapsedReadinessSections() -> Set<String> {
        guard let array = defaults.stringArray(forKey: Self.collapsedReadinessSectionsKey) else {
            // First launch: "Not Ready" collapsed by default
            return ["notReady"]
        }
        let result = Set(array)
        logger.debug("loadCollapsedReadinessSections: \(result.count) sections")
        return result
    }

    func saveCollapsedReadinessSections(_ value: Set<String>) {
        defaults.set(Array(value), forKey: Self.collapsedReadinessSectionsKey)
        logger.debug("saveCollapsedReadinessSections: \(value.count) sections")
    }
}

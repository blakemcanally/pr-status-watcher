import Foundation

/// Abstraction over UserDefaults persistence for app settings.
protocol SettingsStoreProtocol {
    func loadRefreshInterval() -> Int
    func saveRefreshInterval(_ value: Int)
    func loadCollapsedRepos() -> Set<String>
    func saveCollapsedRepos(_ value: Set<String>)
    func loadFilterSettings() -> FilterSettings
    func saveFilterSettings(_ value: FilterSettings)
    func loadCollapsedReadinessSections() -> Set<String>
    func saveCollapsedReadinessSections(_ value: Set<String>)
}

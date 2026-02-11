import Foundation
@testable import PRStatusWatcher

final class MockSettingsStore: SettingsStoreProtocol {
    var refreshInterval: Int = 60
    var collapsedRepos: Set<String> = []
    var filterSettings: FilterSettings = FilterSettings()

    var saveRefreshIntervalCallCount = 0
    var saveCollapsedReposCallCount = 0
    var saveFilterSettingsCallCount = 0

    func loadRefreshInterval() -> Int { refreshInterval }
    func saveRefreshInterval(_ value: Int) {
        saveRefreshIntervalCallCount += 1
        refreshInterval = value
    }
    func loadCollapsedRepos() -> Set<String> { collapsedRepos }
    func saveCollapsedRepos(_ value: Set<String>) {
        saveCollapsedReposCallCount += 1
        collapsedRepos = value
    }
    func loadFilterSettings() -> FilterSettings { filterSettings }
    func saveFilterSettings(_ value: FilterSettings) {
        saveFilterSettingsCallCount += 1
        filterSettings = value
    }
}

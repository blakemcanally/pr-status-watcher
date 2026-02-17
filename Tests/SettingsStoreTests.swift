import Testing
import Foundation
@testable import PRStatusWatcher

@Suite final class SettingsStoreTests {
    private let suiteName: String
    private let defaults: UserDefaults
    private let store: SettingsStore

    init() {
        suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SettingsStore(defaults: defaults)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Refresh Interval

    @Test func loadRefreshIntervalDefaultIs60() {
        #expect(store.loadRefreshInterval() == 60)
    }

    @Test func loadRefreshIntervalReturnsSavedValue() {
        defaults.set(120, forKey: SettingsStore.pollingKey)
        #expect(store.loadRefreshInterval() == 120)
    }

    @Test func loadRefreshIntervalIgnoresZero() {
        defaults.set(0, forKey: SettingsStore.pollingKey)
        #expect(store.loadRefreshInterval() == 60)
    }

    @Test func loadRefreshIntervalIgnoresNegative() {
        defaults.set(-10, forKey: SettingsStore.pollingKey)
        #expect(store.loadRefreshInterval() == 60)
    }

    @Test func saveRefreshIntervalPersists() {
        store.saveRefreshInterval(300)
        #expect(defaults.integer(forKey: SettingsStore.pollingKey) == 300)
    }

    // MARK: - Collapsed Repos

    @Test func loadCollapsedReposDefaultIsEmpty() {
        #expect(store.loadCollapsedRepos() == [])
    }

    @Test func loadCollapsedReposReturnsSavedValue() {
        defaults.set(["owner/repo1", "owner/repo2"], forKey: SettingsStore.collapsedReposKey)
        #expect(store.loadCollapsedRepos() == ["owner/repo1", "owner/repo2"])
    }

    @Test func saveCollapsedReposPersists() {
        store.saveCollapsedRepos(["a/b", "c/d"])
        let saved = Set(defaults.stringArray(forKey: SettingsStore.collapsedReposKey) ?? [])
        #expect(saved == ["a/b", "c/d"])
    }

    // MARK: - Filter Settings

    @Test func loadFilterSettingsDefaultIsFilterSettingsInit() {
        #expect(store.loadFilterSettings() == FilterSettings())
    }

    @Test func loadFilterSettingsReturnsSavedValue() throws {
        let custom = FilterSettings(hideDrafts: false, requiredCheckNames: ["build"])
        let data = try JSONEncoder().encode(custom)
        defaults.set(data, forKey: SettingsStore.filterSettingsKey)
        #expect(store.loadFilterSettings() == custom)
    }

    @Test func loadFilterSettingsCorruptedDataReturnsDefault() {
        defaults.set(Data("not json".utf8), forKey: SettingsStore.filterSettingsKey)
        #expect(store.loadFilterSettings() == FilterSettings())
    }

    @Test func saveFilterSettingsPersists() throws {
        let custom = FilterSettings(hideDrafts: false, requiredCheckNames: ["lint"])
        store.saveFilterSettings(custom)
        let data = try #require(defaults.data(forKey: SettingsStore.filterSettingsKey))
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        #expect(decoded == custom)
    }

    @Test func saveAndLoadRoundTrip() {
        let settings = FilterSettings(hideDrafts: false, requiredCheckNames: ["build", "lint"])
        store.saveFilterSettings(settings)
        #expect(store.loadFilterSettings() == settings)
    }

    @Test func loadFilterSettingsWithWrongTypeReturnsDefault() {
        // Store an Int where we expect Data — SettingsStore should handle gracefully
        defaults.set(42, forKey: SettingsStore.filterSettingsKey)
        #expect(store.loadFilterSettings() == FilterSettings())
    }

    // MARK: - Collapsed Readiness Sections

    @Test func loadCollapsedReadinessSectionsDefaultIsNotReadyCollapsed() {
        #expect(store.loadCollapsedReadinessSections() == ["notReady"])
    }

    @Test func loadCollapsedReadinessSectionsReturnsSavedValue() {
        defaults.set(["ready", "notReady"], forKey: SettingsStore.collapsedReadinessSectionsKey)
        #expect(store.loadCollapsedReadinessSections() == ["ready", "notReady"])
    }

    @Test func loadCollapsedReadinessSectionsEmptyArrayReturnsEmpty() {
        defaults.set([String](), forKey: SettingsStore.collapsedReadinessSectionsKey)
        #expect(store.loadCollapsedReadinessSections().isEmpty)
    }

    @Test func saveCollapsedReadinessSectionsPersists() {
        store.saveCollapsedReadinessSections(["ready"])
        let saved = Set(defaults.stringArray(forKey: SettingsStore.collapsedReadinessSectionsKey) ?? [])
        #expect(saved == ["ready"])
    }

    @Test func saveAndLoadCollapsedReadinessSectionsRoundTrip() {
        store.saveCollapsedReadinessSections(["notReady"])
        #expect(store.loadCollapsedReadinessSections() == ["notReady"])
    }
}

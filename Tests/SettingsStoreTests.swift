import XCTest
@testable import PRStatusWatcher

final class SettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: SettingsStore!

    override func setUp() {
        super.setUp()
        suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        store = SettingsStore(defaults: defaults)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Refresh Interval

    func testLoadRefreshIntervalDefaultIs60() {
        XCTAssertEqual(store.loadRefreshInterval(), 60)
    }

    func testLoadRefreshIntervalReturnsSavedValue() {
        defaults.set(120, forKey: SettingsStore.pollingKey)
        XCTAssertEqual(store.loadRefreshInterval(), 120)
    }

    func testLoadRefreshIntervalIgnoresZero() {
        defaults.set(0, forKey: SettingsStore.pollingKey)
        XCTAssertEqual(store.loadRefreshInterval(), 60)
    }

    func testLoadRefreshIntervalIgnoresNegative() {
        defaults.set(-10, forKey: SettingsStore.pollingKey)
        XCTAssertEqual(store.loadRefreshInterval(), 60)
    }

    func testSaveRefreshIntervalPersists() {
        store.saveRefreshInterval(300)
        XCTAssertEqual(defaults.integer(forKey: SettingsStore.pollingKey), 300)
    }

    // MARK: - Collapsed Repos

    func testLoadCollapsedReposDefaultIsEmpty() {
        XCTAssertEqual(store.loadCollapsedRepos(), [])
    }

    func testLoadCollapsedReposReturnsSavedValue() {
        defaults.set(["owner/repo1", "owner/repo2"], forKey: SettingsStore.collapsedReposKey)
        XCTAssertEqual(store.loadCollapsedRepos(), ["owner/repo1", "owner/repo2"])
    }

    func testSaveCollapsedReposPersists() {
        store.saveCollapsedRepos(["a/b", "c/d"])
        let saved = Set(defaults.stringArray(forKey: SettingsStore.collapsedReposKey) ?? [])
        XCTAssertEqual(saved, ["a/b", "c/d"])
    }

    // MARK: - Filter Settings

    func testLoadFilterSettingsDefaultIsFilterSettingsInit() {
        XCTAssertEqual(store.loadFilterSettings(), FilterSettings())
    }

    func testLoadFilterSettingsReturnsSavedValue() throws {
        let custom = FilterSettings(hideDrafts: false, hideCIFailing: true)
        let data = try JSONEncoder().encode(custom)
        defaults.set(data, forKey: SettingsStore.filterSettingsKey)
        XCTAssertEqual(store.loadFilterSettings(), custom)
    }

    func testLoadFilterSettingsCorruptedDataReturnsDefault() {
        defaults.set(Data("not json".utf8), forKey: SettingsStore.filterSettingsKey)
        XCTAssertEqual(store.loadFilterSettings(), FilterSettings())
    }

    func testSaveFilterSettingsPersists() throws {
        let custom = FilterSettings(hideDrafts: false, hideCIPending: true, hideApproved: true)
        store.saveFilterSettings(custom)
        let data = defaults.data(forKey: SettingsStore.filterSettingsKey)!
        let decoded = try JSONDecoder().decode(FilterSettings.self, from: data)
        XCTAssertEqual(decoded, custom)
    }

    func testSaveAndLoadRoundTrip() {
        let settings = FilterSettings(
            hideDrafts: false,
            hideCIFailing: true,
            hideCIPending: true,
            hideConflicting: true,
            hideApproved: true
        )
        store.saveFilterSettings(settings)
        XCTAssertEqual(store.loadFilterSettings(), settings)
    }
}

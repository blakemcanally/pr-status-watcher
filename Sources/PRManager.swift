import SwiftUI
import AppKit
import os
// MARK: - PR Manager (ViewModel)

private let logger = Logger(subsystem: "PRStatusWatcher", category: "PRManager")

@MainActor
final class PRManager: ObservableObject {
    @Published var pullRequests: [PullRequest] = []
    @Published var reviewPRs: [PullRequest] = []
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var ghUser: String?

    private let service: GitHubServiceProtocol
    private let settingsStore: SettingsStoreProtocol
    private let notificationService: NotificationServiceProtocol
    private let scheduler = PollingScheduler()

    @Published var collapsedRepos: Set<String> = [] {
        didSet { settingsStore.saveCollapsedRepos(collapsedRepos) }
    }

    /// Toggle a repo's collapsed state. Call from views instead of mutating
    /// `collapsedRepos` directly, to keep mutation logic in the ViewModel.
    func toggleRepoCollapsed(_ repo: String) {
        if collapsedRepos.contains(repo) {
            collapsedRepos.remove(repo)
        } else {
            collapsedRepos.insert(repo)
        }
    }

    @Published var filterSettings: FilterSettings = FilterSettings() {
        didSet { settingsStore.saveFilterSettings(filterSettings) }
    }

    @Published var refreshInterval: Int {
        didSet { settingsStore.saveRefreshInterval(refreshInterval) }
    }

    var refreshIntervalLabel: String {
        PRStatusSummary.refreshIntervalLabel(for: refreshInterval)
    }

    /// The estimated date of the next scheduled refresh, or nil if not polling.
    var nextRefreshDate: Date? {
        scheduler.nextRefreshDate
    }

    /// True until the first successful fetch completes (distinguishes "loading" from "genuinely empty").
    @Published var hasCompletedInitialLoad = false

    private let changeDetector = StatusChangeDetector()
    private var previousCIStates: [String: PullRequest.CIStatus] = [:]
    private var previousPRIds: Set<String> = []
    private var isFirstLoad = true

    // MARK: - Init

    init(
        service: GitHubServiceProtocol,
        settingsStore: SettingsStoreProtocol,
        notificationService: NotificationServiceProtocol
    ) {
        self.service = service
        self.settingsStore = settingsStore
        self.notificationService = notificationService
        self.refreshInterval = settingsStore.loadRefreshInterval()
        self.collapsedRepos = settingsStore.loadCollapsedRepos()
        self.filterSettings = settingsStore.loadFilterSettings()

        notificationService.requestPermission()

        // Resolve gh user off the main thread so the menu bar is immediately clickable
        logger.info("init: starting user resolution")
        let svc = service
        Task {
            logger.info("init: resolving gh user...")
            ghUser = await Task.detached { svc.currentUser() }.value
            logger.info("init: gh user resolved to \(self.ghUser ?? "nil", privacy: .public)")
            logger.info("init: calling refreshAll...")
            await refreshAll()
            logger.info("init: refreshAll completed, starting polling")
            startPolling()
        }
    }

    // MARK: - Menu Bar Icon

    var overallStatusIcon: String {
        PRStatusSummary.overallStatusIcon(for: pullRequests)
    }

    var hasFailure: Bool {
        PRStatusSummary.hasFailure(in: pullRequests)
    }

    var openCount: Int {
        PRStatusSummary.openCount(in: pullRequests)
    }

    var draftCount: Int {
        PRStatusSummary.draftCount(in: pullRequests)
    }

    var queuedCount: Int {
        PRStatusSummary.queuedCount(in: pullRequests)
    }

    var statusBarSummary: String {
        PRStatusSummary.statusBarSummary(for: pullRequests, reviewPRs: reviewPRs)
    }

    /// Menu bar image with a red badge dot when CI is failing.
    var menuBarImage: NSImage {
        let symbolName = overallStatusIcon
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "PR Status")?
            .withSymbolConfiguration(config) ?? NSImage()

        guard hasFailure else {
            if let img = base.copy() as? NSImage {
                img.isTemplate = true
                return img
            }
            return base
        }

        // Composite the icon with a red badge dot
        let size = NSSize(width: 20, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            // Draw the base icon (left-aligned, vertically centered)
            let iconSize = base.size
            let iconOrigin = NSPoint(
                x: 0,
                y: (rect.height - iconSize.height) / 2
            )
            base.draw(at: iconOrigin, from: .zero, operation: .sourceOver, fraction: 1.0)

            // Red dot badge in the top-right corner
            let dotSize: CGFloat = 5
            let dotRect = NSRect(
                x: iconSize.width - 2,
                y: rect.height - dotSize - 1,
                width: dotSize,
                height: dotSize
            )
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - Refresh (single GraphQL call)

    func refreshAll() async {
        guard let user = ghUser else {
            logger.warning("refreshAll: no gh user, aborting")
            lastError = "gh not authenticated"
            return
        }

        // Skip if a refresh is already in flight (prevents competing updates)
        guard !isRefreshing else {
            logger.info("refreshAll: already in progress, skipping")
            return
        }

        logger.info("refreshAll: starting (user=\(user, privacy: .public))")
        isRefreshing = true
        defer {
            isRefreshing = false
            logger.info("refreshAll: done")
        }

        // Fetch authored PRs and review-requested PRs in parallel
        let svc = service
        async let myResult: Result<[PullRequest], Error> = Task.detached {
            do {
                let prs = try svc.fetchAllMyOpenPRs(username: user)
                return .success(prs)
            } catch {
                return .failure(error)
            }
        }.value

        async let reviewResult: Result<[PullRequest], Error> = Task.detached {
            do {
                let prs = try svc.fetchReviewRequestedPRs(username: user)
                return .success(prs)
            } catch {
                return .failure(error)
            }
        }.value

        let (myPRs, revPRs) = await (myResult, reviewResult)

        // Process authored PRs — keep existing data on failure
        switch myPRs {
        case .success(let prs):
            logger.info("refreshAll: my PRs fetched (\(prs.count) results)")
            // Send notifications for status changes (skip the first load)
            if !isFirstLoad {
                checkForStatusChanges(newPRs: prs)
            }
            isFirstLoad = false

            // Update tracked state for next diff
            previousCIStates = Dictionary(uniqueKeysWithValues: prs.map { ($0.id, $0.ciStatus) })
            previousPRIds = Set(prs.map { $0.id })

            pullRequests = prs
            lastError = nil
        case .failure(let error):
            logger.error("refreshAll: my PRs fetch failed: \(error.localizedDescription, privacy: .public)")
            // Keep existing pullRequests in place — don't blank the UI
            lastError = error.localizedDescription
        }

        // Process review-requested PRs — keep existing data on failure
        switch revPRs {
        case .success(let prs):
            logger.info("refreshAll: review PRs fetched (\(prs.count) results)")
            reviewPRs = prs
        case .failure(let error):
            logger.error("refreshAll: review PRs fetch failed: \(error.localizedDescription, privacy: .public)")
            // Keep existing reviewPRs in place — don't blank the UI
            let reviewError = "Reviews: \(error.localizedDescription)"
            if let existing = lastError {
                lastError = "\(existing) | \(reviewError)"
            } else {
                lastError = reviewError
            }
        }

        hasCompletedInitialLoad = true
    }

    // MARK: - Polling

    private func startPolling() {
        scheduler.start(interval: refreshInterval) { [weak self] in
            await self?.refreshAll()
        }
    }

    // MARK: - Notifications

    var notificationsAvailable: Bool {
        notificationService.isAvailable
    }

    private func checkForStatusChanges(newPRs: [PullRequest]) {
        let notifications = changeDetector.detectChanges(
            previousCIStates: previousCIStates,
            previousPRIds: previousPRIds,
            newPRs: newPRs
        )
        for notification in notifications {
            notificationService.send(
                title: notification.title,
                body: notification.body,
                url: notification.url
            )
        }
    }
}

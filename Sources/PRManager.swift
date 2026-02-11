import SwiftUI
import AppKit
import UserNotifications
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

    let service = GitHubService()
    private static let pollingKey = "polling_interval"
    private static let collapsedReposKey = "collapsed_repos"
    private static let filterSettingsKey = "filter_settings"

    @Published var collapsedRepos: Set<String> = [] {
        didSet { UserDefaults.standard.set(Array(collapsedRepos), forKey: Self.collapsedReposKey) }
    }

    @Published var filterSettings: FilterSettings = FilterSettings() {
        didSet {
            if let data = try? JSONEncoder().encode(filterSettings) {
                UserDefaults.standard.set(data, forKey: Self.filterSettingsKey)
            }
        }
    }

    @Published var refreshInterval: Int {
        didSet { UserDefaults.standard.set(refreshInterval, forKey: Self.pollingKey) }
    }

    /// Human-readable label for the current interval, used in the footer.
    var refreshIntervalLabel: String {
        if refreshInterval < 60 { return "\(refreshInterval)s" }
        if refreshInterval == 60 { return "1 min" }
        if refreshInterval % 60 == 0 { return "\(refreshInterval / 60) min" }
        return "\(refreshInterval)s"
    }

    /// True until the first successful fetch completes (distinguishes "loading" from "genuinely empty").
    @Published var hasCompletedInitialLoad = false

    private var previousCIStates: [String: PullRequest.CIStatus] = [:]
    private var previousPRIds: Set<String> = []
    private var isFirstLoad = true
    private var pollingTask: Task<Void, Never>?

    // MARK: - Init

    init() {
        let saved = UserDefaults.standard.integer(forKey: Self.pollingKey)
        self.refreshInterval = saved > 0 ? saved : 60
        self.collapsedRepos = Set(UserDefaults.standard.stringArray(forKey: Self.collapsedReposKey) ?? [])

        if let data = UserDefaults.standard.data(forKey: Self.filterSettingsKey),
           let saved = try? JSONDecoder().decode(FilterSettings.self, from: data) {
            self.filterSettings = saved
        }

        requestNotificationPermission()

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
        if pullRequests.isEmpty {
            return "arrow.triangle.pull"
        }
        if pullRequests.contains(where: { $0.ciStatus == .failure }) {
            return "xmark.circle.fill"
        }
        if pullRequests.contains(where: { $0.ciStatus == .pending }) {
            return "clock.circle.fill"
        }
        if pullRequests.allSatisfy({ $0.state == .merged || $0.state == .closed }) {
            return "checkmark.circle"
        }
        return "checkmark.circle.fill"
    }

    var hasFailure: Bool {
        pullRequests.contains(where: { $0.ciStatus == .failure })
    }

    var openCount: Int {
        pullRequests.filter { $0.state == .open && !$0.isInMergeQueue }.count
    }

    var draftCount: Int {
        pullRequests.filter { $0.state == .draft }.count
    }

    var queuedCount: Int {
        pullRequests.filter { $0.isInMergeQueue }.count
    }

    /// Compact summary for the menu bar, e.g. "3·10·2"
    /// Order is Draft · Open · Queued (RTL mirrors the PR lifecycle flow).
    var statusBarSummary: String {
        guard !pullRequests.isEmpty else { return "" }
        var parts: [String] = []
        if draftCount > 0 { parts.append("\(draftCount)") }
        if openCount > 0 { parts.append("\(openCount)") }
        if queuedCount > 0 { parts.append("\(queuedCount)") }
        return parts.joined(separator: "·")
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
            break
        }

        hasCompletedInitialLoad = true
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(refreshInterval) * 1_000_000_000)
                await refreshAll()
            }
        }
    }

    deinit {
        pollingTask?.cancel()
    }

    // MARK: - Notifications

    var notificationsAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private func requestNotificationPermission() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkForStatusChanges(newPRs: [PullRequest]) {
        let newIds = Set(newPRs.map { $0.id })

        for pullRequest in newPRs {
            guard let oldStatus = previousCIStates[pullRequest.id] else {
                // New PR appeared — no notification needed
                continue
            }

            // CI went from pending -> failure
            if oldStatus == .pending && pullRequest.ciStatus == .failure {
                sendNotification(
                    title: "CI Failed",
                    body: "\(pullRequest.repoFullName) \(pullRequest.displayNumber): \(pullRequest.title)",
                    url: pullRequest.url
                )
            }

            // CI went from pending -> success
            if oldStatus == .pending && pullRequest.ciStatus == .success {
                sendNotification(
                    title: "All Checks Passed",
                    body: "\(pullRequest.repoFullName) \(pullRequest.displayNumber): \(pullRequest.title)",
                    url: pullRequest.url
                )
            }
        }

        // PRs that disappeared (merged or closed)
        let disappeared = previousPRIds.subtracting(newIds)
        for id in disappeared {
            // We don't have the full PR info anymore, but we can parse the id
            sendNotification(
                title: "PR No Longer Open",
                body: "\(id) was merged or closed",
                url: nil
            )
        }
    }

    private func sendNotification(title: String, body: String, url: URL?) {
        guard notificationsAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let url {
            content.userInfo = ["url": url.absoluteString]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }
}

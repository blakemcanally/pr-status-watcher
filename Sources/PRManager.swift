import SwiftUI
import AppKit
import UserNotifications

// MARK: - PR Manager (ViewModel)

@MainActor
final class PRManager: ObservableObject {
    @Published var pullRequests: [PullRequest] = []
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var ghUser: String?

    let service = GitHubService()
    private static let pollingKey = "polling_interval"

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

    private var previousCIStates: [String: PullRequest.CIStatus] = [:]
    private var previousPRIds: Set<String> = []
    private var isFirstLoad = true

    // MARK: - Init

    init() {
        let saved = UserDefaults.standard.integer(forKey: Self.pollingKey)
        self.refreshInterval = saved > 0 ? saved : 60

        requestNotificationPermission()

        // Resolve gh user off the main thread so the menu bar is immediately clickable
        let svc = service
        Task {
            ghUser = await Task.detached { svc.currentUser() }.value
            await refreshAll()
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
        if draftCount > 0  { parts.append("\(draftCount)") }
        if openCount > 0   { parts.append("\(openCount)") }
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
            let img = base.copy() as! NSImage
            img.isTemplate = true
            return img
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
            lastError = "gh not authenticated"
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        // Single GraphQL call fetches all PRs with CI status — runs off main thread
        let svc = service
        let result: Result<[PullRequest], Error> = await Task.detached {
            do {
                let prs = try svc.fetchAllMyOpenPRs(username: user)
                return .success(prs)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let prs):
            let sorted = prs.sorted {
                if $0.repoFullName != $1.repoFullName {
                    return $0.repoFullName < $1.repoFullName
                }
                return $0.number > $1.number
            }

            // Send notifications for status changes (skip the first load)
            if !isFirstLoad {
                checkForStatusChanges(newPRs: sorted)
            }
            isFirstLoad = false

            // Update tracked state for next diff
            previousCIStates = Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0.ciStatus) })
            previousPRIds = Set(sorted.map { $0.id })

            pullRequests = sorted
            lastError = nil
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    // MARK: - Polling

    private func startPolling() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(refreshInterval) * 1_000_000_000)
                await refreshAll()
            }
        }
    }

    // MARK: - Notifications

    private var notificationsAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private func requestNotificationPermission() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkForStatusChanges(newPRs: [PullRequest]) {
        let newIds = Set(newPRs.map { $0.id })

        for pr in newPRs {
            guard let oldStatus = previousCIStates[pr.id] else {
                // New PR appeared — no notification needed
                continue
            }

            // CI went from pending -> failure
            if oldStatus == .pending && pr.ciStatus == .failure {
                sendNotification(
                    title: "CI Failed",
                    body: "\(pr.repoFullName) \(pr.displayNumber): \(pr.title)",
                    url: pr.url
                )
            }

            // CI went from pending -> success
            if oldStatus == .pending && pr.ciStatus == .success {
                sendNotification(
                    title: "All Checks Passed",
                    body: "\(pr.repoFullName) \(pr.displayNumber): \(pr.title)",
                    url: pr.url
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

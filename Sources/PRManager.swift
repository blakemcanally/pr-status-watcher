import SwiftUI
import AppKit

// MARK: - PR Manager (ViewModel)

@MainActor
final class PRManager: ObservableObject {
    @Published var pullRequests: [PullRequest] = []
    @Published var isRefreshing = false
    @Published var lastError: String?
    @Published var ghUser: String?

    let service = GitHubService()
    private let refreshInterval: UInt64 = 60  // seconds

    // MARK: - Init

    init() {
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
            // Sort by repo then newest PR first
            pullRequests = prs.sorted {
                if $0.repoFullName != $1.repoFullName {
                    return $0.repoFullName < $1.repoFullName
                }
                return $0.number > $1.number
            }
            lastError = nil
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    // MARK: - Polling

    private func startPolling() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: refreshInterval * 1_000_000_000)
                await refreshAll()
            }
        }
    }
}

import Foundation

/// Compares previous and current PR states, returning notifications for
/// meaningful status transitions. Pure logic — no side effects.
struct StatusChangeDetector {

    /// Detect status changes between previous and current PR state.
    ///
    /// Notifications are generated for:
    /// - CI pending → failure ("CI Failed")
    /// - CI pending → success ("All Checks Passed")
    /// - PR disappeared from results ("PR No Longer Open")
    ///
    /// No notification is generated for:
    /// - New PRs that appear for the first time
    /// - Status changes that don't originate from pending
    /// - PRs with unchanged status
    func detectChanges(
        previousCIStates: [String: PullRequest.CIStatus],
        previousPRIds: Set<String>,
        newPRs: [PullRequest]
    ) -> [StatusNotification] {
        var notifications: [StatusNotification] = []
        let newIds = Set(newPRs.map { $0.id })

        for pr in newPRs {
            guard let oldStatus = previousCIStates[pr.id] else {
                continue  // New PR — no notification
            }

            if oldStatus == .pending && pr.ciStatus == .failure {
                notifications.append(StatusNotification(
                    title: "CI Failed",
                    body: "\(pr.repoFullName) \(pr.displayNumber): \(pr.title)",
                    url: pr.url
                ))
            }

            if oldStatus == .pending && pr.ciStatus == .success {
                notifications.append(StatusNotification(
                    title: "All Checks Passed",
                    body: "\(pr.repoFullName) \(pr.displayNumber): \(pr.title)",
                    url: pr.url
                ))
            }
        }

        let disappeared = previousPRIds.subtracting(newIds)
        for id in disappeared {
            notifications.append(StatusNotification(
                title: "PR No Longer Open",
                body: "\(id) was merged or closed",
                url: nil
            ))
        }

        return notifications
    }
}

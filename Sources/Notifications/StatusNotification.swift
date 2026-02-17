import Foundation

/// A notification to send when PR status changes.
struct StatusNotification: Equatable {
    let title: String
    let body: String
    let url: URL?
}

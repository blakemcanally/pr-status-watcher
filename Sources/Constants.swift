import AppKit
import Foundation

// MARK: - App Configuration Constants

/// Centralized configuration constants. Organized by domain so every magic
/// value is discoverable in one place.
enum AppConstants {

    // MARK: GitHub CLI

    enum GitHub {
        /// Known install locations for the `gh` binary, checked in order.
        /// Falls back to PATH-based lookup if none are found.
        static let knownBinaryPaths = [
            "/opt/homebrew/bin/gh",
            "/usr/local/bin/gh",
            "/usr/bin/gh",
        ]

        /// Maximum results per GraphQL search query.
        static let paginationLimit = 100

        /// Seconds before a `gh` process is forcefully terminated.
        static let processTimeoutSeconds: TimeInterval = 30

        /// Seconds to wait after SIGTERM before re-terminating a hung process.
        static let terminationGracePeriod: TimeInterval = 2
    }

    // MARK: UserDefaults Keys

    enum DefaultsKey {
        static let pollingInterval = "polling_interval"
        static let collapsedRepos = "collapsed_repos"
        static let filterSettings = "filter_settings"
        static let collapsedReadinessSections = "collapsedReadinessSections"
    }

    // MARK: Notification

    enum Notification {
        /// Key used to pass the PR URL through notification `userInfo`.
        static let urlInfoKey = "url"
    }

    // MARK: Layout

    enum Layout {
        enum ContentWindow {
            static let minWidth: CGFloat = 400
            static let idealWidth: CGFloat = 460
            static let maxWidth: CGFloat = 560
            static let minHeight: CGFloat = 400
            static let idealHeight: CGFloat = 520
            static let maxHeight: CGFloat = 700
        }

        enum SettingsWindow {
            static let minWidth: CGFloat = 320
            static let idealWidth: CGFloat = 380
            static let maxWidth: CGFloat = 480
            static let minHeight: CGFloat = 520
            static let idealHeight: CGFloat = 620
            static let maxHeight: CGFloat = 800
        }

        enum MenuBar {
            static let imageSize = NSSize(width: 20, height: 16)
            static let badgeDotDiameter: CGFloat = 5
            static let symbolPointSize: CGFloat = 14
            static let statusFontSize: CGFloat = 11
        }

        enum Header {
            static let tabPickerWidth: CGFloat = 180
        }
    }

    // MARK: Defaults

    enum Defaults {
        /// Default polling interval in seconds when no saved preference exists.
        static let refreshInterval = 60
    }
}

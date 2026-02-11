import Foundation

// MARK: - Polling Scheduler

/// Manages a recurring async task on a fixed interval.
/// Properly handles Task cancellation (fixes the try? sleep bug).
@MainActor
final class PollingScheduler {
    private var task: Task<Void, Never>?

    /// Whether a polling task is currently active.
    var isRunning: Bool {
        task != nil && !(task?.isCancelled ?? true)
    }

    /// Start polling at the given interval. Cancels any existing task first.
    func start(interval: Int, action: @escaping @Sendable () async -> Void) {
        stop()
        task = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                } catch {
                    return  // Exit cleanly on cancellation
                }
                await action()
            }
        }
    }

    /// Stop the current polling task.
    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}

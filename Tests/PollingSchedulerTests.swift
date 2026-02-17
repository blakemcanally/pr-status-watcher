import Testing
import Foundation
@testable import PRStatusWatcher

@MainActor
@Suite struct PollingSchedulerTests {

    @Test func isRunningFalseBeforeStart() {
        let scheduler = PollingScheduler()
        #expect(!scheduler.isRunning)
    }

    @Test func isRunningTrueAfterStart() {
        let scheduler = PollingScheduler()
        scheduler.start(interval: 9999) { }
        #expect(scheduler.isRunning)
        scheduler.stop()
    }

    @Test func isRunningFalseAfterStop() {
        let scheduler = PollingScheduler()
        scheduler.start(interval: 9999) { }
        scheduler.stop()
        #expect(!scheduler.isRunning)
    }

    @Test func nextRefreshDateSetAfterStart() async throws {
        let scheduler = PollingScheduler()
        #expect(scheduler.nextRefreshDate == nil)

        scheduler.start(interval: 60) { }
        // Yield to let the spawned Task set nextRefreshDate
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(scheduler.nextRefreshDate != nil)
        scheduler.stop()
    }

    @Test func nextRefreshDateClearedAfterStop() {
        let scheduler = PollingScheduler()
        scheduler.start(interval: 60) { }
        scheduler.stop()
        #expect(scheduler.nextRefreshDate == nil)
    }

    @Test func startCancelsPreviousTask() {
        let scheduler = PollingScheduler()
        scheduler.start(interval: 9999) { }
        let firstRunning = scheduler.isRunning

        // Starting again should cancel the old task and start a new one
        scheduler.start(interval: 9999) { }
        let secondRunning = scheduler.isRunning

        #expect(firstRunning)
        #expect(secondRunning)
        scheduler.stop()
    }

    @Test func actionExecutesAfterInterval() async throws {
        let scheduler = PollingScheduler()
        let flag = FlagBox()

        scheduler.start(interval: 1) { [flag] in
            await flag.set()
        }

        // Wait for the action to fire (interval is 1 second)
        try await Task.sleep(nanoseconds: 1_500_000_000)

        #expect(await flag.value == true)
        scheduler.stop()
    }
}

/// Thread-safe flag for testing async callbacks.
private actor FlagBox {
    var value = false
    func set() { value = true }
}

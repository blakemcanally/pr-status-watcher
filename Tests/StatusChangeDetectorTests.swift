import XCTest
@testable import PRStatusWatcher

final class StatusChangeDetectorTests: XCTestCase {
    let detector = StatusChangeDetector()

    // MARK: - CI Transitions

    func testPendingToFailureSendsCIFailed() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .failure)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "CI Failed")
    }

    func testPendingToSuccessSendsAllChecksPassed() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .success)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "All Checks Passed")
    }

    func testSuccessToFailureDoesNotNotify() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .success]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .failure)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testFailureToSuccessDoesNotNotify() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .failure]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .success)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testNoStatusChangeProducesNoNotification() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .success]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .success)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - New PRs

    func testNewPRDoesNotNotify() {
        let result = detector.detectChanges(
            previousCIStates: [:], previousPRIds: [], newPRs: [
                PullRequest.fixture(number: 1, ciStatus: .pending)
            ]
        )

        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Disappeared PRs

    func testDisappearedPRSendsNotification() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .success]
        let prevIds: Set<String> = ["test/repo#1"]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: []
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.title, "PR No Longer Open")
        XCTAssertTrue(result.first?.body.contains("test/repo#1") ?? false)
        XCTAssertNil(result.first?.url)
    }

    func testMultipleDisappearedPRsSendMultipleNotifications() {
        let prevIds: Set<String> = ["test/repo#1", "test/repo#2", "test/repo#3"]
        let prev: [String: PullRequest.CIStatus] = [
            "test/repo#1": .success,
            "test/repo#2": .pending,
            "test/repo#3": .failure
        ]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: []
        )

        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { $0.title == "PR No Longer Open" })
    }

    // MARK: - Multiple Changes

    func testMultipleTransitionsInSingleRefresh() {
        let prev: [String: PullRequest.CIStatus] = [
            "test/repo#1": .pending,
            "test/repo#2": .pending,
            "test/repo#3": .success
        ]
        let prevIds: Set<String> = ["test/repo#1", "test/repo#2", "test/repo#3"]
        let newPRs = [
            PullRequest.fixture(number: 1, ciStatus: .failure),
            PullRequest.fixture(number: 2, ciStatus: .success),
            // #3 disappeared
        ]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertEqual(result.count, 3)
        let titles = Set(result.map(\.title))
        XCTAssertTrue(titles.contains("CI Failed"))
        XCTAssertTrue(titles.contains("All Checks Passed"))
        XCTAssertTrue(titles.contains("PR No Longer Open"))
    }

    // MARK: - Edge Cases

    func testEmptyPreviousAndNewPRsProducesNoNotifications() {
        let result = detector.detectChanges(
            previousCIStates: [:], previousPRIds: [], newPRs: []
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testNotificationBodyContainsRepoAndNumber() {
        let prev: [String: PullRequest.CIStatus] = ["myorg/myrepo#42": .pending]
        let prevIds: Set<String> = ["myorg/myrepo#42"]
        let pr = PullRequest.fixture(
            owner: "myorg", repo: "myrepo", number: 42,
            title: "Fix the thing", ciStatus: .failure
        )

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: [pr]
        )

        XCTAssertEqual(result.first?.body, "myorg/myrepo #42: Fix the thing")
    }

    func testNotificationURLIsSetFromPR() {
        let expectedURL = URL(string: "https://github.com/test/repo/pull/1")!
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .failure, url: expectedURL)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertEqual(result.first?.url, expectedURL)
    }

    func testPendingToPendingDoesNotNotify() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .pending)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testPendingToUnknownDoesNotNotify() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .unknown)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        XCTAssertTrue(result.isEmpty)
    }
}

import Testing
import Foundation
@testable import PRStatusWatcher

@Suite struct StatusChangeDetectorTests {
    let detector = StatusChangeDetector()

    // MARK: - CI Transitions

    @Test func pendingToFailureSendsCIFailed() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .failure)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        #expect(result.count == 1)
        #expect(result.first?.title == Strings.Notification.ciFailed)
    }

    @Test func pendingToSuccessSendsAllChecksPassed() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .success)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        #expect(result.count == 1)
        #expect(result.first?.title == Strings.Notification.allChecksPassed)
    }

    @Test func successToFailureDoesNotNotify() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .success]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .failure)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        #expect(result.isEmpty)
    }

    @Test func failureToSuccessDoesNotNotify() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .failure]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .success)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        #expect(result.isEmpty)
    }

    @Test func noStatusChangeProducesNoNotification() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .success]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .success)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        #expect(result.isEmpty)
    }

    // MARK: - New PRs

    @Test func newPRDoesNotNotify() {
        let result = detector.detectChanges(
            previousCIStates: [:], previousPRIds: [], newPRs: [
                PullRequest.fixture(number: 1, ciStatus: .pending),
            ]
        )

        #expect(result.isEmpty)
    }

    // MARK: - Disappeared PRs

    @Test func disappearedPRSendsNotification() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .success]
        let prevIds: Set<String> = ["test/repo#1"]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: []
        )

        #expect(result.count == 1)
        #expect(result.first?.title == Strings.Notification.prNoLongerOpen)
        #expect(result.first?.body.contains("test/repo#1") == true)
        #expect(result.first?.url == nil)
    }

    @Test func multipleDisappearedPRsSendMultipleNotifications() {
        let prevIds: Set<String> = ["test/repo#1", "test/repo#2", "test/repo#3"]
        let prev: [String: PullRequest.CIStatus] = [
            "test/repo#1": .success,
            "test/repo#2": .pending,
            "test/repo#3": .failure,
        ]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: []
        )

        #expect(result.count == 3)
        #expect(result.allSatisfy { $0.title == Strings.Notification.prNoLongerOpen })
    }

    // MARK: - Multiple Changes

    @Test func multipleTransitionsInSingleRefresh() {
        let prev: [String: PullRequest.CIStatus] = [
            "test/repo#1": .pending,
            "test/repo#2": .pending,
            "test/repo#3": .success,
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

        #expect(result.count == 3)
        let titles = Set(result.map(\.title))
        #expect(titles.contains(Strings.Notification.ciFailed))
        #expect(titles.contains(Strings.Notification.allChecksPassed))
        #expect(titles.contains(Strings.Notification.prNoLongerOpen))
    }

    // MARK: - Edge Cases

    @Test func emptyPreviousAndNewPRsProducesNoNotifications() {
        let result = detector.detectChanges(
            previousCIStates: [:], previousPRIds: [], newPRs: []
        )

        #expect(result.isEmpty)
    }

    @Test func notificationBodyContainsRepoAndNumber() {
        let prev: [String: PullRequest.CIStatus] = ["myorg/myrepo#42": .pending]
        let prevIds: Set<String> = ["myorg/myrepo#42"]
        let pr = PullRequest.fixture(
            owner: "myorg", repo: "myrepo", number: 42,
            title: "Fix the thing", ciStatus: .failure
        )

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: [pr]
        )

        #expect(result.first?.body == "myorg/myrepo #42: Fix the thing")
    }

    @Test func notificationURLIsSetFromPR() {
        let expectedURL = URL(string: "https://github.com/test/repo/pull/1")!
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .failure, url: expectedURL)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        #expect(result.first?.url == expectedURL)
    }

    @Test func pendingToPendingDoesNotNotify() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .pending)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        #expect(result.isEmpty)
    }

    @Test func pendingToUnknownDoesNotNotify() {
        let prev: [String: PullRequest.CIStatus] = ["test/repo#1": .pending]
        let prevIds: Set<String> = ["test/repo#1"]
        let newPRs = [PullRequest.fixture(number: 1, ciStatus: .unknown)]

        let result = detector.detectChanges(
            previousCIStates: prev, previousPRIds: prevIds, newPRs: newPRs
        )

        #expect(result.isEmpty)
    }
}

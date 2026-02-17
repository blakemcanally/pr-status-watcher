import Testing
import SwiftUI
@testable import PRStatusWatcher

@Suite struct PullRequestSortPriorityTests {
    @Test(arguments: [
        (PullRequest.PRState.open, false, 0),
        (PullRequest.PRState.draft, false, 1),
        (PullRequest.PRState.open, true, 2),    // isInMergeQueue
        (PullRequest.PRState.merged, false, 3),
        (PullRequest.PRState.closed, false, 3),
    ])
    func sortPriority(state: PullRequest.PRState, isInMergeQueue: Bool, expected: Int) {
        #expect(PullRequest.fixture(state: state, isInMergeQueue: isInMergeQueue).sortPriority == expected)
    }
}

@Suite struct PullRequestReviewSortPriorityTests {
    @Test(arguments: [
        (PullRequest.ReviewDecision.reviewRequired, 0),
        (PullRequest.ReviewDecision.none, 0),
        (PullRequest.ReviewDecision.changesRequested, 1),
        (PullRequest.ReviewDecision.approved, 2),
    ])
    func reviewSortPriority(decision: PullRequest.ReviewDecision, expected: Int) {
        #expect(PullRequest.fixture(reviewDecision: decision).reviewSortPriority == expected)
    }
}

@Suite struct PullRequestStatusColorTests {
    @Test(arguments: [
        (PullRequest.PRState.merged, PullRequest.CIStatus.success, false, Color.purple),
        (PullRequest.PRState.closed, PullRequest.CIStatus.success, false, Color.gray),
        (PullRequest.PRState.draft, PullRequest.CIStatus.success, false, Color.gray),
        (PullRequest.PRState.open, PullRequest.CIStatus.success, true, Color.purple),   // queued
        (PullRequest.PRState.open, PullRequest.CIStatus.success, false, Color.green),
        (PullRequest.PRState.open, PullRequest.CIStatus.failure, false, Color.red),
        (PullRequest.PRState.open, PullRequest.CIStatus.pending, false, Color.orange),
        (PullRequest.PRState.open, PullRequest.CIStatus.unknown, false, Color.gray),
    ])
    func statusColor(state: PullRequest.PRState, ciStatus: PullRequest.CIStatus, isInMergeQueue: Bool, expected: Color) {
        #expect(
            PullRequest.fixture(state: state, ciStatus: ciStatus, isInMergeQueue: isInMergeQueue)
                .statusColor == expected
        )
    }
}

@Suite struct PullRequestIdentityTests {
    @Test func idFormat() {
        let pr = PullRequest.fixture(owner: "myorg", repo: "myrepo", number: 42)
        #expect(pr.id == "myorg/myrepo#42")
    }

    @Test func repoFullName() {
        let pr = PullRequest.fixture(owner: "acme", repo: "widget")
        #expect(pr.repoFullName == "acme/widget")
    }

    @Test func displayNumber() {
        let pr = PullRequest.fixture(number: 99)
        #expect(pr.displayNumber == "#99")
    }
}

// MARK: - CIStatus Color Tests

@Suite struct CIStatusColorTests {
    @Test func successColorIsGreen() {
        #expect(PullRequest.CIStatus.success.color == .green)
    }

    @Test func failureColorIsRed() {
        #expect(PullRequest.CIStatus.failure.color == .red)
    }

    @Test func pendingColorIsOrange() {
        #expect(PullRequest.CIStatus.pending.color == .orange)
    }

    @Test func unknownColorIsSecondary() {
        #expect(PullRequest.CIStatus.unknown.color == .secondary)
    }
}

// MARK: - Readiness Tests

@Suite struct ReadinessTests {
    // Default mode (no required checks)

    @Test func openPRWithPassingCIIsReady() {
        let pr = PullRequest.fixture(state: .open, ciStatus: .success, mergeable: .mergeable)
        #expect(pr.isReady(requiredChecks: []))
    }

    @Test func draftPRIsNotReady() {
        let pr = PullRequest.fixture(state: .draft, ciStatus: .success)
        #expect(!pr.isReady(requiredChecks: []))
    }

    @Test func conflictingPRIsNotReady() {
        let pr = PullRequest.fixture(state: .open, ciStatus: .success, mergeable: .conflicting)
        #expect(!pr.isReady(requiredChecks: []))
    }

    @Test func failingCIIsNotReadyInDefaultMode() {
        let pr = PullRequest.fixture(state: .open, ciStatus: .failure)
        #expect(!pr.isReady(requiredChecks: []))
    }

    @Test func pendingCIIsNotReadyInDefaultMode() {
        let pr = PullRequest.fixture(state: .open, ciStatus: .pending)
        #expect(!pr.isReady(requiredChecks: []))
    }

    @Test func unknownCIIsReadyInDefaultMode() {
        let pr = PullRequest.fixture(state: .open, ciStatus: .unknown)
        #expect(pr.isReady(requiredChecks: []))
    }

    // Required checks mode

    @Test func requiredCheckPassingIsReady() {
        let pr = PullRequest.fixture(
            state: .open, ciStatus: .failure,
            checkResults: [
                .init(name: "Bazel-Pipeline-PR", status: .passed, detailsUrl: nil),
                .init(name: "lint", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(pr.isReady(requiredChecks: ["Bazel-Pipeline-PR"]))
    }

    @Test func requiredCheckFailingIsNotReady() {
        let pr = PullRequest.fixture(
            state: .open,
            checkResults: [
                .init(name: "Bazel-Pipeline-PR", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: ["Bazel-Pipeline-PR"]))
    }

    @Test func requiredCheckMissingIsIgnored() {
        let pr = PullRequest.fixture(state: .open, checkResults: [])
        #expect(pr.isReady(requiredChecks: ["Bazel-Pipeline-PR"]))
    }

    @Test func requiredCheckMissingWithOtherCheckPresent() {
        let pr = PullRequest.fixture(
            state: .open,
            checkResults: [
                .init(name: "android-build", status: .passed, detailsUrl: nil),
            ]
        )
        #expect(pr.isReady(requiredChecks: ["Bazel-Pipeline-PR", "android-build"]))
    }

    @Test func requiredCheckPresentButFailingIsNotReady() {
        let pr = PullRequest.fixture(
            state: .open,
            checkResults: [
                .init(name: "Bazel-Pipeline-PR", status: .failed, detailsUrl: nil),
                .init(name: "android-build", status: .passed, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: ["Bazel-Pipeline-PR", "android-build"]))
    }

    @Test func allRequiredChecksMissingIsReady() {
        let pr = PullRequest.fixture(state: .open, checkResults: [
            .init(name: "unrelated-check", status: .passed, detailsUrl: nil),
        ])
        #expect(pr.isReady(requiredChecks: ["Bazel-Pipeline-PR", "ios-lint"]))
    }

    @Test func multipleRequiredChecksAllMustPass() {
        let pr = PullRequest.fixture(
            state: .open,
            checkResults: [
                .init(name: "build", status: .passed, detailsUrl: nil),
                .init(name: "lint", status: .pending, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: ["build", "lint"]))
    }

    @Test func requiredChecksDontOverrideDraftStatus() {
        let pr = PullRequest.fixture(
            state: .draft,
            checkResults: [
                .init(name: "build", status: .passed, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: ["build"]))
    }

    @Test func requiredChecksDontOverrideConflicts() {
        let pr = PullRequest.fixture(
            state: .open, mergeable: .conflicting,
            checkResults: [
                .init(name: "build", status: .passed, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: ["build"]))
    }
}

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

    // Ignored checks mode (default — no required checks)

    @Test func ignoredFailingCheckMakesPRReadyInDefaultMode() {
        let pr = PullRequest.fixture(
            state: .open, ciStatus: .failure,
            checkResults: [
                .init(name: "build", status: .passed, detailsUrl: nil),
                .init(name: "flaky", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: []))
        #expect(pr.isReady(requiredChecks: [], ignoredChecks: ["flaky"]))
    }

    @Test func ignoredPendingCheckMakesPRReadyInDefaultMode() {
        let pr = PullRequest.fixture(
            state: .open, ciStatus: .pending,
            checkResults: [
                .init(name: "build", status: .passed, detailsUrl: nil),
                .init(name: "slow-check", status: .pending, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: []))
        #expect(pr.isReady(requiredChecks: [], ignoredChecks: ["slow-check"]))
    }

    @Test func ignoringAllChecksReturnsReadyInDefaultMode() {
        let pr = PullRequest.fixture(
            state: .open, ciStatus: .failure,
            checkResults: [
                .init(name: "only-check", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(pr.isReady(requiredChecks: [], ignoredChecks: ["only-check"]))
    }

    @Test func ignoredChecksDontOverrideDraftStatus() {
        let pr = PullRequest.fixture(
            state: .draft, ciStatus: .failure,
            checkResults: [
                .init(name: "flaky", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: [], ignoredChecks: ["flaky"]))
    }

    @Test func ignoredChecksDontOverrideConflicts() {
        let pr = PullRequest.fixture(
            state: .open, ciStatus: .failure, mergeable: .conflicting,
            checkResults: [
                .init(name: "flaky", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(!pr.isReady(requiredChecks: [], ignoredChecks: ["flaky"]))
    }

    // Ignored checks + required checks mode

    @Test func ignoredCheckWithRequiredChecksMode() {
        let pr = PullRequest.fixture(
            state: .open, ciStatus: .failure,
            checkResults: [
                .init(name: "build", status: .passed, detailsUrl: nil),
                .init(name: "flaky", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(pr.isReady(requiredChecks: ["build"], ignoredChecks: ["flaky"]))
    }

    @Test func ignoredCheckInBothListsDefensivelyIgnored() {
        let pr = PullRequest.fixture(
            state: .open,
            checkResults: [
                .init(name: "build", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(pr.isReady(requiredChecks: ["build"], ignoredChecks: ["build"]))
    }

    @Test func emptyIgnoredChecksDoesNotAffectReadiness() {
        let pr = PullRequest.fixture(state: .open, ciStatus: .failure)
        #expect(!pr.isReady(requiredChecks: [], ignoredChecks: []))
    }
}

// MARK: - SLA Tests

@Suite struct SLATests {
    private let now = Date()
    private let twoHoursAgo = Date().addingTimeInterval(-2 * 3600)
    private let tenHoursAgo = Date().addingTimeInterval(-10 * 3600)

    @Test func slaNotExceededWhenWithinDeadline() {
        let pullRequest = PullRequest.fixture(publishedAt: twoHoursAgo)
        #expect(!pullRequest.isSLAExceeded(minutes: 480, now: now))
    }

    @Test func slaExceededWhenPastDeadline() {
        let pullRequest = PullRequest.fixture(publishedAt: tenHoursAgo)
        #expect(pullRequest.isSLAExceeded(minutes: 480, now: now))
    }

    @Test func slaNotExceededWhenPublishedAtIsNil() {
        let pullRequest = PullRequest.fixture(publishedAt: nil)
        #expect(!pullRequest.isSLAExceeded(minutes: 480, now: now))
    }

    @Test func slaNotExceededAtExactBoundary() {
        let exactlyAtDeadline = now.addingTimeInterval(-480 * 60)
        let pullRequest = PullRequest.fixture(publishedAt: exactlyAtDeadline)
        #expect(!pullRequest.isSLAExceeded(minutes: 480, now: now))
    }

    @Test func slaExceededJustPastBoundary() {
        let justPast = now.addingTimeInterval(-480 * 60 - 1)
        let pullRequest = PullRequest.fixture(publishedAt: justPast)
        #expect(pullRequest.isSLAExceeded(minutes: 480, now: now))
    }

    @Test func slaWithSmallMinuteThreshold() {
        let fiveMinutesAgo = now.addingTimeInterval(-5 * 60)
        let pullRequest = PullRequest.fixture(publishedAt: fiveMinutesAgo)
        #expect(!pullRequest.isSLAExceeded(minutes: 10, now: now))
        #expect(pullRequest.isSLAExceeded(minutes: 3, now: now))
    }
}

// MARK: - Effective Values Tests (Ignored Checks)

@Suite struct EffectiveValuesTests {
    private let checksFixture: [PullRequest.CheckResult] = [
        .init(name: "build", status: .passed, detailsUrl: nil),
        .init(name: "lint", status: .failed, detailsUrl: nil),
        .init(name: "graphite/stack", status: .failed, detailsUrl: nil),
        .init(name: "test", status: .pending, detailsUrl: nil),
    ]

    private let failedFixture: [PullRequest.CheckInfo] = [
        .init(name: "lint", detailsUrl: nil),
        .init(name: "graphite/stack", detailsUrl: nil),
    ]

    // effectiveCheckResults

    @Test func effectiveCheckResultsWithEmptyIgnoreListReturnsAll() {
        let pr = PullRequest.fixture(checkResults: checksFixture)
        #expect(pr.effectiveCheckResults(ignoredChecks: []).count == 4)
    }

    @Test func effectiveCheckResultsFiltersIgnoredChecks() {
        let pr = PullRequest.fixture(checkResults: checksFixture)
        let effective = pr.effectiveCheckResults(ignoredChecks: ["graphite/stack"])
        #expect(effective.count == 3)
        #expect(!effective.contains(where: { $0.name == "graphite/stack" }))
    }

    @Test func effectiveCheckResultsFiltersMultipleIgnoredChecks() {
        let pr = PullRequest.fixture(checkResults: checksFixture)
        let effective = pr.effectiveCheckResults(ignoredChecks: ["lint", "graphite/stack"])
        #expect(effective.count == 2)
        #expect(effective.map(\.name).sorted() == ["build", "test"])
    }

    // effectiveFailedChecks

    @Test func effectiveFailedChecksFiltersIgnoredChecks() {
        let pr = PullRequest.fixture(failedChecks: failedFixture)
        let effective = pr.effectiveFailedChecks(ignoredChecks: ["graphite/stack"])
        #expect(effective.count == 1)
        #expect(effective.first?.name == "lint")
    }

    @Test func effectiveFailedChecksWithEmptyIgnoreListReturnsAll() {
        let pr = PullRequest.fixture(failedChecks: failedFixture)
        #expect(pr.effectiveFailedChecks(ignoredChecks: []).count == 2)
    }

    // effectiveCIStatus

    @Test func effectiveCIStatusIgnoringFailingCheckBecomesSuccess() {
        let pr = PullRequest.fixture(
            ciStatus: .failure,
            checkResults: [
                .init(name: "build", status: .passed, detailsUrl: nil),
                .init(name: "flaky", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(pr.effectiveCIStatus(ignoredChecks: ["flaky"]) == .success)
    }

    @Test func effectiveCIStatusIgnoringAllChecksReturnsUnknown() {
        let pr = PullRequest.fixture(
            ciStatus: .failure,
            checkResults: [
                .init(name: "only-check", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(pr.effectiveCIStatus(ignoredChecks: ["only-check"]) == .unknown)
    }

    @Test func effectiveCIStatusWithPendingAfterFilteringReturnsPending() {
        let pr = PullRequest.fixture(
            ciStatus: .failure,
            checkResults: [
                .init(name: "build", status: .pending, detailsUrl: nil),
                .init(name: "flaky", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(pr.effectiveCIStatus(ignoredChecks: ["flaky"]) == .pending)
    }

    @Test func effectiveCIStatusWithEmptyIgnoreListReturnsRawStatus() {
        let pr = PullRequest.fixture(ciStatus: .failure)
        #expect(pr.effectiveCIStatus(ignoredChecks: []) == .failure)
    }

    // effectiveCheckCounts

    @Test func effectiveCheckCountsExcludeIgnoredChecks() {
        let pr = PullRequest.fixture(checkResults: checksFixture)
        let counts = pr.effectiveCheckCounts(ignoredChecks: ["graphite/stack"])
        #expect(counts.total == 3)
        #expect(counts.passed == 1)
        #expect(counts.failed == 1)
    }

    // effectiveStatusColor

    @Test func effectiveStatusColorReflectsEffectiveCIStatus() {
        let pr = PullRequest.fixture(
            state: .open, ciStatus: .failure,
            checkResults: [
                .init(name: "build", status: .passed, detailsUrl: nil),
                .init(name: "flaky", status: .failed, detailsUrl: nil),
            ]
        )
        #expect(pr.statusColor == .red)
        #expect(pr.effectiveStatusColor(ignoredChecks: ["flaky"]) == .green)
    }

    @Test func effectiveStatusColorForDraftIsAlwaysGray() {
        let pr = PullRequest.fixture(state: .draft, ciStatus: .failure)
        #expect(pr.effectiveStatusColor(ignoredChecks: ["anything"]) == .gray)
    }
}

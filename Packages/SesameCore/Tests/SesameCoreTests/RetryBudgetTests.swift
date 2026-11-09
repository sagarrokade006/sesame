import Testing
@testable import SesameCore

@Suite struct RetryBudgetTests {
    @Test func oneAutomaticRetryAfterNoFace() {
        var budget = RetryBudget()
        let first = budget.shouldRetryAutomatically(after: .noFace)
        let second = budget.shouldRetryAutomatically(after: .noFace)
        #expect(first)
        #expect(!second)
    }

    @Test func aStrangerGetsTheSameSingleRetry() {
        var budget = RetryBudget()
        let first = budget.shouldRetryAutomatically(after: .stranger)
        let second = budget.shouldRetryAutomatically(after: .stranger)
        #expect(first)
        #expect(!second)
    }

    @Test func aSpoofNeverRetriesAutomatically() {
        var budget = RetryBudget()
        let retry = budget.shouldRetryAutomatically(after: .spoof)
        #expect(!retry)
    }

    @Test func wakingAgainRestoresTheRetry() {
        var budget = RetryBudget()
        _ = budget.shouldRetryAutomatically(after: .noFace)
        budget.reset()
        let retry = budget.shouldRetryAutomatically(after: .noFace)
        #expect(retry)
    }

    @Test func requestsWaitBrieflyAfterAnAttempt() {
        var budget = RetryBudget()
        #expect(budget.allowsRequestedScan(at: 10))
        budget.noteAttemptEnded(at: 10)
        #expect(!budget.allowsRequestedScan(at: 11))
        #expect(budget.allowsRequestedScan(at: 11.5))
    }
}

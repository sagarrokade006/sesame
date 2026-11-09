import Foundation

/// Decides when another scan may start at the same lock screen.
public struct RetryBudget: Sendable, Equatable {
    public enum Miss: Sendable, Equatable {
        case noFace
        case stranger
        case spoof
    }

    private let automaticRetries = 1
    private let minimumGap: TimeInterval = 1.5
    private var automaticRetriesUsed = 0
    private var lastAttemptEndedAt: TimeInterval?

    public init() {}

    /// Call when the Mac wakes or locks again, which starts a fresh set of tries.
    public mutating func reset() {
        automaticRetriesUsed = 0
        lastAttemptEndedAt = nil
    }

    public mutating func noteAttemptEnded(at time: TimeInterval) {
        lastAttemptEndedAt = time
    }

    /// One free try covers looking away as the lid opens. A likely spoof never gets one.
    public mutating func shouldRetryAutomatically(after miss: Miss) -> Bool {
        guard miss != .spoof, automaticRetriesUsed < automaticRetries else { return false }
        automaticRetriesUsed += 1
        return true
    }

    /// Stops a held key or a jittery mouse from restarting the camera over and over.
    public func allowsRequestedScan(at time: TimeInterval) -> Bool {
        guard let lastAttemptEndedAt else { return true }
        return time - lastAttemptEndedAt >= minimumGap
    }
}

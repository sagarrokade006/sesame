import Foundation

/// Decides when another scan may start at the same lock screen.
public struct RetryBudget: Sendable, Equatable {
    public enum Miss: Sendable, Equatable {
        case noFace
        /// The owner was clearly there but never blinked or moved. They're right in front of the camera, so it's
        /// worth trying a few more times on its own.
        case unproven
        case stranger
        case spoof
    }

    /// Keyboard events don't reach apps at the lock screen, so trying again has to happen on its own.
    private static func automaticRetries(after miss: Miss) -> Int {
        switch miss {
        case .unproven: return 3
        case .noFace, .stranger: return 1
        case .spoof: return 0
        }
    }
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

    /// One free try covers looking away as the lid opens; someone recognized but not yet proven gets a few. A likely
    /// spoof never gets one.
    public mutating func shouldRetryAutomatically(after miss: Miss) -> Bool {
        guard automaticRetriesUsed < Self.automaticRetries(after: miss) else { return false }
        automaticRetriesUsed += 1
        return true
    }

    /// Stops a jittery mouse from restarting the camera over and over.
    public func allowsRequestedScan(at time: TimeInterval) -> Bool {
        guard let lastAttemptEndedAt else { return true }
        return time - lastAttemptEndedAt >= minimumGap
    }
}

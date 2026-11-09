import Foundation

/// Decides when a scan has to be ended from outside, because the camera stopped saying anything.
///
/// A scan normally ends itself: every frame is judged, and the frame that passes the time limit ends it. If the
/// camera never delivers a frame, or stops partway, nothing would end the scan, and it would block every later one.
public struct ScanWatchdog: Sendable, Equatable {
    public enum Verdict: Sendable, Equatable {
        case healthy
        /// No frame ever arrived: the camera is busy, unplugged, or not allowed.
        case cameraSilent
        /// Frames were arriving and then stopped.
        case cameraStalled
        /// The scan outlived its time limit without ending itself.
        case overdue
    }

    /// Cameras take a moment to start, more after waking from sleep.
    public var startupPatience: TimeInterval = 3
    public var stallPatience: TimeInterval = 2
    /// How far past its limit a scan may run before it's ended from outside.
    public var overtime: TimeInterval = 1.5

    private let startedAt: TimeInterval
    private let duration: TimeInterval
    private var lastFrameAt: TimeInterval?

    public init(startedAt: TimeInterval, duration: TimeInterval) {
        self.startedAt = startedAt
        self.duration = duration
    }

    public mutating func noteFrame(at time: TimeInterval) {
        lastFrameAt = time
    }

    public func verdict(at now: TimeInterval) -> Verdict {
        if now - startedAt > duration + overtime { return .overdue }
        guard let lastFrameAt else {
            return now - startedAt > startupPatience ? .cameraSilent : .healthy
        }
        return now - lastFrameAt > stallPatience ? .cameraStalled : .healthy
    }
}

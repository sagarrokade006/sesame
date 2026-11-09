import Foundation

/// One scan at the lock screen. Feed it every processed camera frame; it decides when to type the password.
public struct UnlockAttempt: Sendable {
    public struct Rules: Sendable {
        public var matchingFramesRequired = 3
        public var requiresAttention = true
        public var maximumFaceGap: TimeInterval = 0.5
        public var strangerPatience: TimeInterval = 2
        public var duration: TimeInterval = 6
        /// A frame that waited longer than this to be judged says nothing about who is there now.
        public var maximumFrameAge: TimeInterval = 0.5

        public init() {}
    }

    public func isFresh(capturedAt: TimeInterval, now: TimeInterval) -> Bool {
        now - capturedAt <= rules.maximumFrameAge
    }

    public enum Outcome: Sendable, Equatable {
        case keepWatching
        case unlock(name: String)
        case stranger
        case spoof
        case expired
    }

    private let rules: Rules
    private let startedAt: TimeInterval
    private var judge = LivenessJudge()
    public private(set) var challenge: TurnChallenge?
    private var matchStreak = 0
    /// Recognized and attentive, only missing proof of life. Worth telling the person to blink.
    public private(set) var isWaitingForProof = false
    private var doubtStartedAt: TimeInterval?
    private var lastSeenAt: TimeInterval?

    public init(rules: Rules = Rules(), challenge: TurnChallenge? = nil, startedAt: TimeInterval) {
        self.rules = rules
        self.challenge = challenge
        self.startedAt = startedAt
    }

    private mutating func forgetContinuity() {
        matchStreak = 0
        isWaitingForProof = false
        judge.forgetProof()
        challenge?.restart()
    }

    public mutating func observeNoFace(at time: TimeInterval) -> Outcome {
        doubtStartedAt = nil
        if let lastSeenAt, time - lastSeenAt > rules.maximumFaceGap {
            forgetContinuity()
            self.lastSeenAt = nil
        }
        return time - startedAt >= rules.duration ? .expired : .keepWatching
    }

    public mutating func observe(_ reading: FaceReading, verdict: FaceVerdict) -> Outcome {
        if reading.time - startedAt >= rules.duration { return .expired }

        if let lastSeenAt, reading.time - lastSeenAt > rules.maximumFaceGap {
            forgetContinuity()
        }
        lastSeenAt = reading.time

        let finding = judge.observe(reading, countsAsProof: verdict != .stranger)
        if finding == .spoof { return .spoof }
        if verdict == .stranger { forgetContinuity() } else { challenge?.observe(yaw: reading.yaw) }

        guard case .owner(let name) = verdict else {
            matchStreak = 0
            let since = doubtStartedAt ?? reading.time
            doubtStartedAt = since
            return reading.time - since >= rules.strangerPatience ? .stranger : .keepWatching
        }

        doubtStartedAt = nil
        guard !rules.requiresAttention || reading.isAttentive() else {
            matchStreak = 0
            return .keepWatching
        }
        matchStreak += 1

        let provedAlive = finding == .alive
        let passedChallenge = challenge?.isComplete ?? true
        isWaitingForProof = matchStreak >= rules.matchingFramesRequired && passedChallenge && !provedAlive
        return matchStreak >= rules.matchingFramesRequired && provedAlive && passedChallenge
            ? .unlock(name: name)
            : .keepWatching
    }
}

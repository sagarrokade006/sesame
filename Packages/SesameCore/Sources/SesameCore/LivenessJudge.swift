import Foundation

/// What the camera measured about one face in one frame. Angles are radians.
public struct FaceReading: Sendable, Equatable {
    public var time: TimeInterval
    /// Positive means turned toward the left of the screen.
    public var yaw: Double
    /// Positive means looking down.
    public var pitch: Double?
    public var leftEyeOpenness: Double?
    public var rightEyeOpenness: Double?
    /// Sideways distance from between the eyes to the nose, in eye-widths.
    public var noseShift: Double?
    /// Whether a screen- or card-shaped outline surrounds the face.
    public var isFramedByRectangle: Bool

    public init(
        time: TimeInterval,
        yaw: Double,
        pitch: Double? = nil,
        leftEyeOpenness: Double? = nil,
        rightEyeOpenness: Double? = nil,
        noseShift: Double? = nil,
        isFramedByRectangle: Bool = false
    ) {
        self.time = time
        self.yaw = yaw
        self.pitch = pitch
        self.leftEyeOpenness = leftEyeOpenness
        self.rightEyeOpenness = rightEyeOpenness
        self.noseShift = noseShift
        self.isFramedByRectangle = isFramedByRectangle
    }

    var eyeOpenness: Double? {
        guard let leftEyeOpenness, let rightEyeOpenness else { return nil }
        return (leftEyeOpenness + rightEyeOpenness) / 2
    }

    public func isAttentive(maximumTurn: Double = 0.35, minimumEyeOpenness: Double = 0.17) -> Bool {
        guard let leftEyeOpenness, let rightEyeOpenness, abs(yaw) <= maximumTurn,
              leftEyeOpenness >= minimumEyeOpenness, rightEyeOpenness >= minimumEyeOpenness
        else { return false }
        if let pitch, abs(pitch) > maximumTurn { return false }
        return true
    }
}

/// Looks for evidence that a face is a living, three-dimensional person.
public struct LivenessJudge: Sendable {
    public enum Finding: Sendable, Equatable {
        case undecided
        case alive
        case spoof
    }

    /// A phone or printout held up to the camera is outlined in nearly every frame. A doorframe or monitor edge behind
    /// a real person only lines up now and then, so a few scattered hits must not count.
    private let recentFrameCount = 8
    private let framedFramesForSpoof = 6
    private var recentFraming: [Bool] = []

    private var peakOpenness = 0.0
    private var eyesClosedAt: TimeInterval?
    private var sawBlink = false

    private var turnHistory: [(time: TimeInterval, yaw: Double, shift: Double)] = []
    private var sawDepth = false

    public init() {}

    /// Forgets proof of life but not spoof evidence, which must not be escaped by changing faces.
    public mutating func forgetProof() {
        peakOpenness = 0
        eyesClosedAt = nil
        sawBlink = false
        turnHistory = []
        sawDepth = false
    }

    /// `countsAsProof` is false for a face that can't be the owner, so it can only ever add spoof evidence.
    public mutating func observe(_ reading: FaceReading, countsAsProof: Bool) -> Finding {
        recentFraming.append(reading.isFramedByRectangle)
        if recentFraming.count > recentFrameCount { recentFraming.removeFirst() }
        if recentFraming.filter({ $0 }).count >= framedFramesForSpoof {
            return .spoof
        }
        guard countsAsProof else {
            forgetProof()
            return .undecided
        }
        trackBlink(reading)
        trackDepth(reading)
        return sawBlink || sawDepth ? .alive : .undecided
    }

    private mutating func trackBlink(_ reading: FaceReading) {
        guard let openness = reading.eyeOpenness else { return }
        peakOpenness = max(peakOpenness, openness)
        guard peakOpenness > 0 else { return }
        let ratio = openness / peakOpenness

        if let closedAt = eyesClosedAt {
            if ratio >= 0.8 {
                let duration = reading.time - closedAt
                if duration >= 0.03, duration <= 0.6 {
                    sawBlink = true
                }
                eyesClosedAt = nil
            } else if reading.time - closedAt > 0.6 {
                eyesClosedAt = nil
                peakOpenness = openness
            }
        } else if ratio < 0.65 {
            eyesClosedAt = reading.time
        }
    }

    /// On a real head the nose swings against the eyes as the head turns. On a flat picture it barely moves.
    private mutating func trackDepth(_ reading: FaceReading) {
        guard let shift = reading.noseShift else { return }
        turnHistory.append((reading.time, reading.yaw, shift))
        turnHistory.removeAll { reading.time - $0.time > 2.5 }
        guard turnHistory.count >= 6 else { return }

        let yaws = turnHistory.map(\.yaw)
        let shifts = turnHistory.map(\.shift)
        guard let lowYaw = yaws.min(), let highYaw = yaws.max(), highYaw - lowYaw >= 0.2,
              let lowShift = shifts.min(), let highShift = shifts.max(), highShift - lowShift >= 0.04
        else { return }
        if abs(Self.correlation(yaws, shifts)) >= 0.7 {
            sawDepth = true
        }
    }

    private static func correlation(_ first: [Double], _ second: [Double]) -> Double {
        let count = Double(first.count)
        let firstMean = first.reduce(0, +) / count
        let secondMean = second.reduce(0, +) / count
        var product = 0.0
        var firstEnergy = 0.0
        var secondEnergy = 0.0
        for (x, y) in zip(first, second) {
            product += (x - firstMean) * (y - secondMean)
            firstEnergy += (x - firstMean) * (x - firstMean)
            secondEnergy += (y - secondMean) * (y - secondMean)
        }
        let scale = (firstEnergy * secondEnergy).squareRoot()
        return scale > 0 ? product / scale : 0
    }
}

public enum TurnDirection: String, CaseIterable, Sendable {
    case left
    case right

    var yawSign: Double { self == .left ? 1 : -1 }
}

/// A random "turn your head" prompt, which a prerecorded video can't anticipate.
public struct TurnChallenge: Sendable, Equatable {
    public let direction: TurnDirection
    public private(set) var progress = 0.0
    private var startedCentered = false

    private let requiredTurn = 0.26
    private let centeredTurn = 0.12

    public init(direction: TurnDirection) {
        self.direction = direction
    }

    public var isComplete: Bool { progress >= 1 }

    public mutating func observe(yaw: Double) {
        guard !isComplete else { return }
        let turn = yaw * direction.yawSign
        startedCentered = startedCentered || turn <= centeredTurn
        if startedCentered {
            progress = max(progress, min(1, turn / requiredTurn))
        }
    }

    public mutating func restart() {
        progress = 0
        startedCentered = false
    }
}

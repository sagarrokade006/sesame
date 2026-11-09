import Foundation

/// Guides a Face ID–style enrollment: hold still, then roll your head in a circle until the ring around the camera fills.
public struct FaceScan: Sendable {
    public enum Stage: Sendable, Equatable {
        case position
        case holdStill
        case turn
        case complete
    }

    public static let tickCount = 60

    private static let centerSamplesNeeded = 5
    private static let sectorCount = 8
    private static let samplesPerSector = 3
    private static let sampleSpacing: TimeInterval = 0.14
    /// Lighting a few neighbors keeps the ring filling smoothly between camera frames.
    private static let tickSpread = 2
    private static let litShareToFinish = 0.8

    private static let centeredYaw = 0.16
    private static let centeredPitch = 0.18
    private static let yawReach = 0.26
    private static let pitchReach = 0.2
    private static let tooFar = 2.4

    public private(set) var stage = Stage.position
    public private(set) var litTicks = Set<Int>()
    /// The tick the head is pointing at right now, if it's turned far enough.
    public private(set) var activeTick: Int?

    private var centerVectors: [FaceVector] = []
    private var sectorVectors: [Int: [FaceVector]] = [:]
    private var lastSampleAt: TimeInterval = -.infinity

    public init() {}

    public var vectors: [FaceVector] { centerVectors + sectorVectors.keys.sorted().flatMap { sectorVectors[$0] ?? [] } }

    public var progress: Double {
        guard stage != .complete else { return 1 }
        return min(1, Double(litTicks.count) / (Double(Self.tickCount) * Self.litShareToFinish))
    }

    /// The tick a head pose points at: 0 is up, and ticks run clockwise as seen on the mirrored preview.
    public static func tick(yaw: Double, pitch: Double) -> Int? {
        // Positive yaw is toward the left of the screen, and positive pitch is down.
        let x = -yaw / yawReach
        let y = -pitch / pitchReach
        let reach = (x * x + y * y).squareRoot()
        guard reach >= 1, reach <= tooFar else { return nil }
        var angle = atan2(x, y)
        if angle < 0 { angle += 2 * .pi }
        return Int(angle / (2 * .pi) * Double(tickCount)) % tickCount
    }

    public mutating func observe(vector: FaceVector, yaw: Double, pitch: Double, time: TimeInterval, isWellPlaced: Bool) {
        let isCentered = abs(yaw) <= Self.centeredYaw && abs(pitch) <= Self.centeredPitch

        switch stage {
        case .position:
            if isWellPlaced && isCentered { stage = .holdStill }
        case .holdStill:
            guard isWellPlaced, isCentered, takeSampleSlot(at: time) else { return }
            centerVectors.append(vector)
            if centerVectors.count >= Self.centerSamplesNeeded { stage = .turn }
        case .turn:
            activeTick = isWellPlaced ? Self.tick(yaw: yaw, pitch: pitch) : nil
            guard let activeTick else { return }
            for offset in -Self.tickSpread...Self.tickSpread {
                litTicks.insert((activeTick + offset + Self.tickCount) % Self.tickCount)
            }
            let sector = activeTick * Self.sectorCount / Self.tickCount
            if sectorVectors[sector, default: []].count < Self.samplesPerSector, takeSampleSlot(at: time) {
                sectorVectors[sector, default: []].append(vector)
            }
            if Double(litTicks.count) >= Double(Self.tickCount) * Self.litShareToFinish {
                stage = .complete
                self.activeTick = nil
            }
        case .complete:
            break
        }
    }

    private mutating func takeSampleSlot(at time: TimeInterval) -> Bool {
        guard time - lastSampleAt >= Self.sampleSpacing else { return false }
        lastSampleAt = time
        return true
    }
}

import Foundation

/// A unit-length face description produced by the recognition model.
public struct FaceVector: Codable, Sendable, Equatable {
    public let values: [Float]

    public init(_ raw: [Float]) {
        let length = raw.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        values = length > 0 ? raw.map { $0 / length } : raw
    }

    public func similarity(to other: FaceVector) -> Float {
        guard values.count == other.values.count else { return 0 }
        return zip(values, other.values).reduce(Float(0)) { $0 + $1.0 * $1.1 }
    }
}

public struct FaceProfile: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var vectors: [FaceVector]
    public var isActive: Bool
    public var modelVersion: String
    public var createdAt: Date
    /// Optional so profiles saved before these existed still load.
    public var lastUsedAt: Date?
    public var unlockCount: Int?

    public init(id: UUID = UUID(), name: String, vectors: [FaceVector], modelVersion: String, createdAt: Date, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.vectors = vectors
        self.modelVersion = modelVersion
        self.createdAt = createdAt
        self.isActive = isActive
    }

    public mutating func noteUnlock(at date: Date) {
        lastUsedAt = date
        unlockCount = (unlockCount ?? 0) + 1
    }

    /// Averages the closest few samples, so one lucky sample can't carry a match on its own.
    public func score(for vector: FaceVector) -> Float {
        let closest = vectors.map { $0.similarity(to: vector) }.sorted(by: >).prefix(3)
        guard !closest.isEmpty else { return 0 }
        return closest.reduce(0, +) / Float(closest.count)
    }
}

public enum FaceVerdict: Sendable, Equatable {
    /// Clearly the owner.
    case owner(name: String)
    /// Close to the owner but not clear enough to unlock, such as mid-blink, turned away, or partly covered.
    case doubtful
    case stranger
}

public struct MatchRule: Codable, Sendable, Equatable {
    /// SFace's published same-person cosine threshold is 0.363; unlocking a Mac warrants a higher bar.
    public var acceptScore: Float = 0.48
    /// At or above this a face may still be the owner, mid-blink or turned away.
    public var doubtfulScore: Float = 0.28

    /// How far above `acceptScore` a face must score before it can unlock or vouch for a blink. A clear view of the
    /// owner scores around 0.85. A face that's half covered, or a photo held over someone else's face, hovers right at
    /// the threshold, and a frame that only just clears it must not count. A constant rather than a stored setting, so
    /// saved settings keep loading.
    public static let confidenceMargin: Float = 0.10

    public init() {}

    /// The score that counts as the owner.
    public var unlockScore: Float { acceptScore + Self.confidenceMargin }

    public func bestScore(for vector: FaceVector, among profiles: [FaceProfile], modelVersion: String) -> (name: String, score: Float)? {
        profiles
            .filter { $0.isActive && $0.modelVersion == modelVersion }
            .map { (name: $0.name, score: $0.score(for: vector)) }
            .max { $0.score < $1.score }
    }

    public func verdict(for vector: FaceVector, among profiles: [FaceProfile], modelVersion: String) -> FaceVerdict {
        guard let best = bestScore(for: vector, among: profiles, modelVersion: modelVersion) else { return .stranger }
        if best.score >= unlockScore { return .owner(name: best.name) }
        return best.score >= doubtfulScore ? .doubtful : .stranger
    }
}

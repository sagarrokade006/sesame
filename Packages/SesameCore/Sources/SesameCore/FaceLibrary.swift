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

    public init(id: UUID = UUID(), name: String, vectors: [FaceVector], modelVersion: String, createdAt: Date, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.vectors = vectors
        self.modelVersion = modelVersion
        self.createdAt = createdAt
        self.isActive = isActive
    }

    /// Averages the closest few samples, so one lucky sample can't carry a match on its own.
    public func score(for vector: FaceVector) -> Float {
        let closest = vectors.map { $0.similarity(to: vector) }.sorted(by: >).prefix(3)
        guard !closest.isEmpty else { return 0 }
        return closest.reduce(0, +) / Float(closest.count)
    }
}

public enum FaceVerdict: Sendable, Equatable {
    case owner(name: String)
    case doubtful
    case stranger
}

public struct MatchRule: Codable, Sendable, Equatable {
    /// SFace's published same-person cosine threshold is 0.363; unlocking a Mac warrants a higher bar.
    public var acceptScore: Float = 0.48
    /// At or above this a face may still be the owner, mid-blink or turned away.
    public var doubtfulScore: Float = 0.28

    public init() {}

    public func verdict(for vector: FaceVector, among profiles: [FaceProfile], modelVersion: String) -> FaceVerdict {
        let scored = profiles
            .filter { $0.isActive && $0.modelVersion == modelVersion }
            .map { (name: $0.name, score: $0.score(for: vector)) }
        guard let best = scored.max(by: { $0.score < $1.score }) else { return .stranger }
        if best.score >= acceptScore { return .owner(name: best.name) }
        return best.score >= doubtfulScore ? .doubtful : .stranger
    }
}

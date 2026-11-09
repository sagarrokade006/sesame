import Foundation

public struct PlanePoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Rotation, uniform scale, and translation: x' = a·x − b·y + tx, y' = b·x + a·y + ty.
public struct SimilarityTransform: Sendable, Equatable {
    public var a: Double
    public var b: Double
    public var tx: Double
    public var ty: Double

    public func apply(_ point: PlanePoint) -> PlanePoint {
        PlanePoint(x: a * point.x - b * point.y + tx, y: b * point.x + a * point.y + ty)
    }

    /// Least-squares fit mapping `source` onto `target`. Returns nil if the source points all coincide.
    public static func fit(from source: [PlanePoint], to target: [PlanePoint]) -> SimilarityTransform? {
        guard source.count == target.count, !source.isEmpty else { return nil }
        let count = Double(source.count)
        let sourceX = source.map(\.x).reduce(0, +) / count
        let sourceY = source.map(\.y).reduce(0, +) / count
        let targetX = target.map(\.x).reduce(0, +) / count
        let targetY = target.map(\.y).reduce(0, +) / count

        var dot = 0.0
        var cross = 0.0
        var energy = 0.0
        for (from, to) in zip(source, target) {
            let fx = from.x - sourceX, fy = from.y - sourceY
            let gx = to.x - targetX, gy = to.y - targetY
            dot += fx * gx + fy * gy
            cross += fx * gy - fy * gx
            energy += fx * fx + fy * fy
        }
        guard energy > 0 else { return nil }
        let a = dot / energy
        let b = cross / energy
        return SimilarityTransform(
            a: a,
            b: b,
            tx: targetX - (a * sourceX - b * sourceY),
            ty: targetY - (b * sourceX + a * sourceY)
        )
    }
}

public enum FaceTemplate {
    public static let side = 112.0

    /// Where the left eye, right eye, nose, left mouth corner, and right mouth corner belong, as seen in the image.
    /// Origin at the bottom left, matching Core Image and Vision.
    public static let landmarks = [
        PlanePoint(x: 38.2946, y: side - 51.6963),
        PlanePoint(x: 73.5318, y: side - 51.5014),
        PlanePoint(x: 56.0252, y: side - 71.7366),
        PlanePoint(x: 41.5493, y: side - 92.3655),
        PlanePoint(x: 70.7299, y: side - 92.2041),
    ]
}

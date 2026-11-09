import Foundation
import Testing
@testable import SesameCore

/// Replays a real scan from 2026-11-10: the owner covered half their face and blinked. Every frame matched only
/// borderline (0.43 to 0.55, where a clear view scores about 0.85), and the blink came from those frames. It unlocked
/// before the confidence margin and must not now.
@Suite struct HalfCoveredFaceTests {
    /// (score, yaw, pitch, left eye, right eye), in order, about 30 frames a second.
    private static let halfCovered: [(Float, Double, Double, Double, Double)] = [
        (0.470, 0.18, -0.19, 0.47, 0.46), (0.441, 0.19, -0.20, 0.51, 0.49), (0.476, 0.22, -0.21, 0.45, 0.47),
        (0.458, 0.22, -0.21, 0.49, 0.54), (0.449, 0.15, -0.19, 0.52, 0.54), (0.482, 0.15, -0.19, 0.49, 0.50),
        (0.441, 0.18, -0.17, 0.51, 0.55), (0.485, 0.10, -0.15, 0.51, 0.50), (0.456, 0.09, -0.16, 0.50, 0.51),
        (0.467, 0.06, -0.17, 0.51, 0.53), (0.443, 0.04, -0.15, 0.53, 0.59), (0.509, 0.09, -0.17, 0.49, 0.50),
        (0.461, 0.08, -0.16, 0.49, 0.53), (0.458, 0.08, -0.17, 0.50, 0.54), (0.479, 0.12, -0.19, 0.49, 0.53),
        (0.493, 0.16, -0.17, 0.52, 0.55), (0.494, 0.18, -0.16, 0.45, 0.48), (0.482, 0.20, -0.17, 0.46, 0.48),
        (0.472, 0.20, -0.17, 0.50, 0.52), (0.479, 0.21, -0.17, 0.47, 0.51), (0.444, 0.18, -0.17, 0.48, 0.51),
        (0.530, 0.17, -0.17, 0.45, 0.47), (0.532, 0.15, -0.17, 0.47, 0.50), (0.442, 0.17, -0.15, 0.50, 0.56),
        (0.550, 0.16, -0.13, 0.46, 0.48), (0.518, 0.16, -0.14, 0.47, 0.49), (0.518, 0.13, -0.14, 0.47, 0.48),
        (0.478, 0.16, -0.14, 0.46, 0.51), (0.520, 0.15, -0.13, 0.45, 0.49), (0.527, 0.18, -0.14, 0.48, 0.50),
        (0.493, 0.21, -0.14, 0.45, 0.50), (0.496, 0.21, -0.13, 0.48, 0.53), (0.505, 0.19, -0.12, 0.47, 0.50),
        (0.517, 0.18, -0.11, 0.45, 0.48), (0.527, 0.17, -0.11, 0.47, 0.49), (0.527, 0.20, -0.12, 0.50, 0.51),
        (0.494, 0.23, -0.14, 0.47, 0.51), (0.432, 0.21, -0.14, 0.50, 0.56), (0.537, 0.22, -0.16, 0.46, 0.48),
        (0.489, 0.21, -0.16, 0.48, 0.52), (0.525, 0.20, -0.17, 0.46, 0.49), (0.506, 0.19, -0.16, 0.47, 0.50),
        (0.493, 0.18, -0.16, 0.46, 0.51), (0.430, 0.16, -0.17, 0.43, 0.40), (0.474, 0.12, -0.17, 0.38, 0.29),
        (0.495, 0.13, -0.17, 0.37, 0.27), (0.468, 0.13, -0.15, 0.39, 0.30), (0.453, 0.16, -0.14, 0.45, 0.43),
        (0.472, 0.15, -0.15, 0.45, 0.46), (0.482, 0.15, -0.16, 0.49, 0.51), (0.464, 0.16, -0.16, 0.50, 0.53),
        (0.502, 0.18, -0.16, 0.47, 0.50), (0.510, 0.21, -0.17, 0.48, 0.49), (0.489, 0.20, -0.17, 0.47, 0.50),
    ]

    private let library = [FaceProfile(name: "Owner", vectors: Array(repeating: FaceVector([1, 0]), count: 3), modelVersion: "v1", createdAt: Date())]

    /// A probe vector that scores exactly `score` against the library.
    private func probe(_ score: Float) -> FaceVector {
        FaceVector([score, (1 - score * score).squareRoot()])
    }

    private func replay(scoreBoost: Float) -> [UnlockAttempt.Outcome] {
        var attempt = UnlockAttempt(startedAt: 0)
        let rule = MatchRule()
        var outcomes: [UnlockAttempt.Outcome] = []
        for (index, frame) in Self.halfCovered.enumerated() {
            let score = min(1, frame.0 + scoreBoost)
            let verdict = rule.verdict(for: probe(score), among: library, modelVersion: "v1")
            let reading = FaceReading(
                time: Double(index) * 0.033, yaw: frame.1, pitch: frame.2,
                leftEyeOpenness: frame.3, rightEyeOpenness: frame.4
            )
            outcomes.append(attempt.observe(reading, verdict: verdict))
        }
        return outcomes
    }

    @Test func theRealHalfCoveredScanDoesNotUnlock() {
        #expect(!replay(scoreBoost: 0).contains(.unlock(name: "Owner")))
    }

    /// The same movements with the face clearly visible still unlock, so the margin doesn't lock the owner out.
    @Test func theSameScanWithAClearFaceUnlocks() {
        #expect(replay(scoreBoost: 0.35).contains(.unlock(name: "Owner")))
    }

    @Test func clearMatchesNeedTheMargin() {
        let rule = MatchRule()
        #expect(rule.verdict(for: probe(0.55), among: library, modelVersion: "v1") == .doubtful)
        #expect(rule.verdict(for: probe(0.59), among: library, modelVersion: "v1") == .owner(name: "Owner"))
        var strict = MatchRule()
        strict.acceptScore = 0.55
        #expect(strict.verdict(for: probe(0.62), among: library, modelVersion: "v1") == .doubtful)
        #expect(strict.verdict(for: probe(0.66), among: library, modelVersion: "v1") == .owner(name: "Owner"))
    }
}

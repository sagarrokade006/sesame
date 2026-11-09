import Foundation
import Testing
@testable import SesameCore

private let owner = FaceVerdict.owner(name: "Alex")

private func reading(
    _ time: TimeInterval,
    yaw: Double = 0,
    eyes: Double = 0.3,
    shift: Double? = nil,
    framed: Bool = false
) -> FaceReading {
    FaceReading(time: time, yaw: yaw, pitch: 0, leftEyeOpenness: eyes, rightEyeOpenness: eyes, noseShift: shift, isFramedByRectangle: framed)
}

private struct Run {
    var attempt: UnlockAttempt
    var time = 0.0
    var outcomes: [UnlockAttempt.Outcome] = []

    init(rules: UnlockAttempt.Rules = .init(), challenge: TurnChallenge? = nil) {
        attempt = UnlockAttempt(rules: rules, challenge: challenge, startedAt: 0)
    }

    mutating func frame(_ verdict: FaceVerdict, yaw: Double = 0, eyes: Double = 0.3, shift: Double? = nil, framed: Bool = false) {
        time += 0.05
        outcomes.append(attempt.observe(reading(time, yaw: yaw, eyes: eyes, shift: shift, framed: framed), verdict: verdict))
    }

    mutating func frames(_ verdict: FaceVerdict, count: Int) {
        for _ in 0..<count { frame(verdict) }
    }

    mutating func blink(_ verdict: FaceVerdict) {
        for eyes in [0.3, 0.3, 0.1, 0.1, 0.3, 0.3] { frame(verdict, eyes: eyes) }
    }

    mutating func noFace(for duration: TimeInterval) {
        let end = time + duration
        while time < end {
            time += 0.05
            outcomes.append(attempt.observeNoFace(at: time))
        }
    }

    var unlocked: Bool { outcomes.contains(.unlock(name: "Alex")) }
}

@Suite struct AttemptTests {
    @Test func blinkAndMatchesUnlock() {
        var run = Run()
        run.blink(owner)
        run.frames(owner, count: 3)
        #expect(run.unlocked)
    }

    @Test func matchWithoutProofOfLifeNeverUnlocks() {
        var run = Run()
        run.frames(owner, count: 60)
        #expect(!run.unlocked)
    }

    @Test func strangersBlinkCanNotVouchForTheOwner() {
        var run = Run()
        run.blink(.stranger)
        run.frames(owner, count: 20)
        #expect(!run.unlocked)
    }

    @Test func aStrangerFrameErasesProof() {
        var run = Run()
        run.blink(owner)
        run.frame(.stranger)
        run.frames(owner, count: 20)
        #expect(!run.unlocked)
    }

    /// A half-covered face, or a photo held over someone else's face, only scores borderline. A blink seen there
    /// must never vouch for a later clear match.
    @Test func aBlinkDuringDoubtDoesNotCount() {
        var run = Run()
        run.blink(.doubtful)
        run.frames(owner, count: 20)
        #expect(!run.unlocked)
    }

    @Test func doubtfulFramesNeitherProveNorErase() {
        var run = Run()
        run.blink(owner)
        run.frames(.doubtful, count: 5)
        run.frames(owner, count: 3)
        #expect(run.unlocked)
    }

    @Test func oneOrTwoMatchingFramesAreNotEnough() {
        var run = Run()
        run.blink(owner)
        // A borderline frame keeps the proof but restarts the streak of clear matches.
        run.frame(.doubtful)
        run.frames(owner, count: 2)
        #expect(!run.unlocked)
    }

    @Test func aLongAbsenceErasesProof() {
        var run = Run()
        run.blink(owner)
        run.noFace(for: 1)
        run.frames(owner, count: 20)
        #expect(!run.unlocked)
    }

    @Test func aBriefDropoutKeepsProof() {
        var run = Run()
        run.blink(owner)
        run.noFace(for: 0.1)
        run.frames(owner, count: 3)
        #expect(run.unlocked)
    }

    @Test func closedEyesDoNotCountTowardTheStreak() {
        var run = Run()
        run.blink(owner)
        for _ in 0..<20 { run.frame(owner, eyes: 0.05) }
        #expect(!run.unlocked)
    }

    @Test func lookingAwayDoesNotCountTowardTheStreak() {
        var run = Run()
        run.blink(owner)
        for _ in 0..<20 { run.frame(owner, yaw: 0.7) }
        #expect(!run.unlocked)
    }

    @Test func aRecognizedStillFaceAsksForABlink() {
        var run = Run()
        run.frames(owner, count: 10)
        #expect(run.attempt.isWaitingForProof)
        #expect(!run.outcomes.contains(.unlock(name: "Alex")))
        run.blink(owner)
        run.frames(owner, count: 3)
        #expect(run.outcomes.contains(.unlock(name: "Alex")))
    }

    @Test func aStrangerIsNeverAskedToBlink() {
        var run = Run()
        run.frames(.stranger, count: 10)
        #expect(!run.attempt.isWaitingForProof)
    }

    @Test func rectangleAroundTheFaceIsASpoof() {
        var run = Run()
        for _ in 0..<6 { run.frame(owner, framed: true) }
        #expect(run.outcomes.contains(.spoof))
    }

    @Test func aFewFramedFramesAreNotASpoof() {
        var run = Run()
        for _ in 0..<3 { run.frame(owner, framed: true) }
        #expect(!run.outcomes.contains(.spoof))
    }

    @Test func scatteredFramingFromTheBackgroundIsNotASpoof() {
        var run = Run()
        for index in 0..<60 { run.frame(owner, framed: index % 3 == 0) }
        #expect(!run.outcomes.contains(.spoof))
    }

    @Test func spoofEvidenceSurvivesChangingFaces() {
        var run = Run()
        for verdict in [FaceVerdict.stranger, owner, .doubtful, .stranger, owner, .doubtful] {
            run.frame(verdict, framed: true)
        }
        #expect(run.outcomes.contains(.spoof))
    }

    @Test func aSustainedStrangerEndsTheAttempt() {
        var run = Run()
        run.frames(.stranger, count: 45)
        #expect(run.outcomes.contains(.stranger))
    }

    @Test func attemptsExpire() {
        var run = Run()
        run.frames(owner, count: 125)
        #expect(run.outcomes.last == .expired)
    }

    @Test func challengeMustBeFinished() {
        var run = Run(challenge: TurnChallenge(direction: .left))
        run.blink(owner)
        run.frames(owner, count: 20)
        #expect(!run.unlocked)
    }

    @Test func challengePlusProofUnlocks() {
        var run = Run(challenge: TurnChallenge(direction: .left))
        run.blink(owner)
        run.frame(.doubtful, yaw: 0.3)
        run.frames(owner, count: 3)
        #expect(run.unlocked)
    }

    @Test func aStrangerRestartsTheChallenge() {
        var run = Run(challenge: TurnChallenge(direction: .left))
        run.blink(owner)
        run.frame(.doubtful, yaw: 0.3)
        run.frame(.stranger)
        run.frames(owner, count: 20)
        #expect(!run.unlocked)
        #expect(run.attempt.challenge?.progress == 0)
    }
}

@Suite struct LivenessTests {
    @Test func headTurnWithNoseMovementProvesDepth() {
        var judge = LivenessJudge()
        var finding = LivenessJudge.Finding.undecided
        for step in 0..<10 {
            let yaw = Double(step) * 0.04
            finding = judge.observe(reading(Double(step) * 0.05, yaw: yaw, shift: yaw * 0.6), as: .proof)
        }
        #expect(finding == .alive)
    }

    @Test func flatPictureTurningShowsNoDepth() {
        var judge = LivenessJudge()
        var finding = LivenessJudge.Finding.undecided
        for step in 0..<20 {
            finding = judge.observe(reading(Double(step) * 0.05, yaw: Double(step) * 0.04, shift: 0.01), as: .proof)
        }
        #expect(finding == .undecided)
    }

    @Test func aLongEyeClosureIsNotABlink() {
        var judge = LivenessJudge()
        var finding = LivenessJudge.Finding.undecided
        let eyes = [0.3, 0.3] + [Double](repeating: 0.1, count: 20) + [0.3, 0.3]
        for (index, value) in eyes.enumerated() {
            finding = judge.observe(reading(Double(index) * 0.05, eyes: value), as: .proof)
        }
        #expect(finding == .undecided)
    }
}

@Suite struct ChallengeTests {
    @Test func wrongDirectionDoesNotCount() {
        var challenge = TurnChallenge(direction: .right)
        challenge.observe(yaw: 0)
        challenge.observe(yaw: 0.4)
        #expect(!challenge.isComplete)
    }

    @Test func alreadyTurnedProvesNothing() {
        var challenge = TurnChallenge(direction: .left)
        challenge.observe(yaw: 0.5)
        challenge.observe(yaw: 0.6)
        #expect(!challenge.isComplete)
    }

    @Test func aFullTurnCompletes() {
        var challenge = TurnChallenge(direction: .right)
        challenge.observe(yaw: 0)
        challenge.observe(yaw: -0.3)
        #expect(challenge.isComplete)
    }
}

@Suite struct LibraryTests {
    private func profile(_ vectors: [[Float]], version: String = "v1", active: Bool = true) -> FaceProfile {
        FaceProfile(name: "Alex", vectors: vectors.map(FaceVector.init), modelVersion: version, createdAt: Date(timeIntervalSince1970: 0), isActive: active)
    }

    @Test func vectorsAreUnitLength() {
        #expect(abs(FaceVector([3, 4]).similarity(to: FaceVector([3, 4])) - 1) < 0.0001)
    }

    @Test func mismatchedVectorsScoreZero() {
        #expect(FaceVector([1, 0]).similarity(to: FaceVector([1, 0, 0])) == 0)
    }

    @Test func verdictTiers() {
        let rule = MatchRule()
        let library = [profile([[1, 0], [1, 0], [1, 0]])]
        #expect(rule.verdict(for: FaceVector([1, 0]), among: library, modelVersion: "v1") == owner)
        #expect(rule.verdict(for: FaceVector([0.35, 0.94]), among: library, modelVersion: "v1") == .doubtful)
        #expect(rule.verdict(for: FaceVector([0, 1]), among: library, modelVersion: "v1") == .stranger)
    }

    @Test func oneLuckySampleCanNotCarryAMatch() {
        let rule = MatchRule()
        let library = [profile([[1, 0], [0, 1], [0, 1]])]
        #expect(rule.verdict(for: FaceVector([1, 0]), among: library, modelVersion: "v1") != owner)
    }

    @Test func inactiveAndOutdatedProfilesAreIgnored() {
        let rule = MatchRule()
        let vector = FaceVector([1, 0])
        #expect(rule.verdict(for: vector, among: [profile([[1, 0]], active: false)], modelVersion: "v1") == .stranger)
        #expect(rule.verdict(for: vector, among: [profile([[1, 0]], version: "old")], modelVersion: "v1") == .stranger)
    }
}

@Suite struct AlignmentTests {
    @Test func recoversAKnownTransform() throws {
        let known = SimilarityTransform(a: 0.8, b: 0.3, tx: 12, ty: -5)
        let fit = try #require(SimilarityTransform.fit(from: FaceTemplate.landmarks, to: FaceTemplate.landmarks.map(known.apply)))
        #expect(abs(fit.a - known.a) < 1e-9)
        #expect(abs(fit.b - known.b) < 1e-9)
        #expect(abs(fit.tx - known.tx) < 1e-9)
        #expect(abs(fit.ty - known.ty) < 1e-9)
    }

    @Test func coincidentPointsHaveNoFit() {
        let point = PlanePoint(x: 1, y: 1)
        #expect(SimilarityTransform.fit(from: [point, point], to: [point, point]) == nil)
    }
}

@Suite struct SafeguardTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func trustExpires() {
        let trust = TrustWindow(grantedAt: start)
        #expect(trust.isValid(at: start.addingTimeInterval(47 * 3600)))
        #expect(!trust.isValid(at: start.addingTimeInterval(48 * 3600)))
        #expect(!trust.isValid(at: start.addingTimeInterval(-1)))
    }

    @Test func attemptsRunOut() {
        var counter = AttemptCounter()
        for _ in 0..<4 { counter.recordFailure() }
        #expect(!counter.isExhausted)
        counter.recordFailure()
        #expect(counter.isExhausted)
        counter.reset()
        #expect(!counter.isExhausted)
    }

    @Test func passwordCheckCodes() {
        #expect(PasswordCheck.from(openDirectoryCode: 5000) == .rejected)
        #expect(PasswordCheck.from(openDirectoryCode: 5304) == .unavailable)
    }

    @Test func passwordGoesStaleAfterTwoMisses() {
        var health = PasswordHealth()
        health.recordMissedEntry()
        #expect(!health.isOutdated)
        health.recordMissedEntry()
        #expect(health.isOutdated)
        health.record(.unavailable, at: start)
        #expect(health.isOutdated)
        health.record(.accepted, at: start)
        #expect(!health.isOutdated)
    }

    @Test func historyIsCappedNewestFirst() {
        var history = ActivityHistory()
        for index in 0..<(ActivityHistory.capacity + 5) {
            history.add(ActivityEntry(date: start.addingTimeInterval(Double(index)), kind: .stranger))
        }
        #expect(history.entries.count == ActivityHistory.capacity)
        #expect(history.entries.first?.date == start.addingTimeInterval(Double(ActivityHistory.capacity + 4)))
    }

    @Test func failuresWhileAwayStopAtThePreviousUnlock() {
        var history = ActivityHistory()
        history.add(ActivityEntry(date: start, kind: .stranger))
        history.add(ActivityEntry(date: start, kind: .unlocked))
        history.add(ActivityEntry(date: start, kind: .stranger))
        history.add(ActivityEntry(date: start, kind: .spoof))
        history.add(ActivityEntry(date: start, kind: .paused))
        history.add(ActivityEntry(date: start, kind: .unlocked))
        #expect(history.failuresWhileAway == 2)
    }

    @Test func batchesNeverSplitASurrogatePair() {
        let text = Array(String(repeating: "a", count: 15).utf16) + Array("😀".utf16) + [97]
        let ranges = KeystrokeBatches.ranges(for: text, limit: 16)
        #expect(ranges == [0..<15, 15..<18])
    }
}

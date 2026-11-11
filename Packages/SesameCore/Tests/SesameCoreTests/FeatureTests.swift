import Foundation
import Testing
@testable import SesameCore

@Suite struct PauseTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 15))! }

    @Test func anOpenEndedPauseStaysOn() {
        #expect(Pause().isActive(at: now))
        #expect(Pause().isActive(at: now.addingTimeInterval(365 * 24 * 3600)))
    }

    @Test func aTimedPauseEnds() {
        let pause = Pause.forHours(1, from: now)
        #expect(pause.isActive(at: now.addingTimeInterval(3599)))
        #expect(!pause.isActive(at: now.addingTimeInterval(3600)))
    }

    @Test func untilTomorrowEndsAtMidnight() {
        let pause = Pause.untilTomorrow(from: now, calendar: calendar)
        #expect(pause.until == calendar.date(from: DateComponents(year: 2026, month: 11, day: 11)))
    }

    @Test func survivesSaving() throws {
        let pause = Pause.forHours(2, from: now)
        let decoded = try JSONDecoder().decode(Pause.self, from: JSONEncoder().encode(pause))
        #expect(decoded == pause)
    }
}

@Suite struct DarknessTests {
    @Test func mostlyDarkFramesAreTooDark() {
        var judge = DarknessJudge()
        for _ in 0..<20 { judge.observe(brightness: 0.04) }
        #expect(judge.isTooDark)
    }

    @Test func aLitEmptyRoomIsNotTooDark() {
        var judge = DarknessJudge()
        for _ in 0..<40 { judge.observe(brightness: 0.4) }
        #expect(!judge.isTooDark)
    }

    @Test func aFewDarkFramesAreNotEnough() {
        var judge = DarknessJudge()
        for _ in 0..<10 { judge.observe(brightness: 0.02) }
        #expect(!judge.isTooDark)
    }

    @Test func aBriefDarkSpellInALitRoomDoesNotCount() {
        var judge = DarknessJudge()
        for _ in 0..<10 { judge.observe(brightness: 0.02) }
        for _ in 0..<30 { judge.observe(brightness: 0.5) }
        #expect(!judge.isTooDark)
    }
}

@Suite struct EyeAttentionTests {
    private func reading(left: Double, right: Double, yaw: Double = 0) -> FaceReading {
        FaceReading(time: 0, yaw: yaw, pitch: 0, leftEyeOpenness: left, rightEyeOpenness: right)
    }

    @Test func bothEyesOpenIsAttentive() {
        #expect(reading(left: 0.35, right: 0.37).isAttentive())
    }

    /// A closed eye measured 0.19 in real scans, above the fixed minimum, while the open one read 0.36.
    @Test func oneClosedEyeIsNotAttentive() {
        #expect(!reading(left: 0.19, right: 0.36).isAttentive())
        #expect(!reading(left: 0.36, right: 0.19).isAttentive())
    }

    @Test func bothClosedIsNotAttentive() {
        #expect(!reading(left: 0.12, right: 0.13).isAttentive())
    }

    /// Turning the head makes one eye look a little smaller; that still counts.
    @Test func aSlightTurnKeepsBothEyesCounted() {
        #expect(reading(left: 0.35, right: 0.45, yaw: 0.3).isAttentive())
    }

    @Test func aWinkCanNotUnlock() {
        var attempt = UnlockAttempt(startedAt: 0)
        var outcomes: [UnlockAttempt.Outcome] = []
        // A real blink first, as proof of life, then holding one eye shut.
        for (index, eyes) in [0.35, 0.35, 0.1, 0.1, 0.35, 0.35].enumerated() {
            let frame = FaceReading(time: Double(index) * 0.05, yaw: 0, pitch: 0, leftEyeOpenness: 0.19, rightEyeOpenness: eyes)
            outcomes.append(attempt.observe(frame, verdict: .owner(name: "Alex")))
        }
        for index in 6..<40 {
            let frame = FaceReading(time: Double(index) * 0.05, yaw: 0, pitch: 0, leftEyeOpenness: 0.19, rightEyeOpenness: 0.36)
            outcomes.append(attempt.observe(frame, verdict: .owner(name: "Alex")))
        }
        #expect(!outcomes.contains(.unlock(name: "Alex")))
    }
}

@Suite struct FaceStatsTests {
    @Test func countsUnlocks() {
        var profile = FaceProfile(name: "Alex", vectors: [], modelVersion: "v1", createdAt: Date())
        #expect(profile.unlockCount == nil)
        let when = Date()
        profile.noteUnlock(at: when)
        profile.noteUnlock(at: when)
        #expect(profile.unlockCount == 2)
        #expect(profile.lastUsedAt == when)
    }

    /// A profile saved by 1.0.2 has neither field.
    @Test func olderProfilesStillLoad() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Alex","vectors":[],"isActive":true,"modelVersion":"v1","createdAt":0}"#
        let profile = try JSONDecoder().decode(FaceProfile.self, from: Data(old.utf8))
        #expect(profile.name == "Alex")
        #expect(profile.lastUsedAt == nil)
    }
}

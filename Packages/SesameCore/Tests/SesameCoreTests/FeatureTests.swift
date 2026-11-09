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

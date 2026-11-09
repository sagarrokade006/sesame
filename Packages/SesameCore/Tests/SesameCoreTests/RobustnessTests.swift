import Foundation
import Testing
@testable import SesameCore

@Suite struct ScanWatchdogTests {
    @Test func aCameraGetsTimeToStart() {
        let dog = ScanWatchdog(startedAt: 100, duration: 6)
        #expect(dog.verdict(at: 102.9) == .healthy)
        #expect(dog.verdict(at: 103.1) == .cameraSilent)
    }

    @Test func framesKeepItHealthy() {
        var dog = ScanWatchdog(startedAt: 100, duration: 6)
        dog.noteFrame(at: 101)
        #expect(dog.verdict(at: 102.9) == .healthy)
        dog.noteFrame(at: 104)
        #expect(dog.verdict(at: 105.5) == .healthy)
    }

    @Test func framesThatStopAreAStall() {
        var dog = ScanWatchdog(startedAt: 100, duration: 6)
        dog.noteFrame(at: 101)
        #expect(dog.verdict(at: 103.1) == .cameraStalled)
    }

    @Test func aScanThatOutlivesItsLimitIsOverdue() {
        var dog = ScanWatchdog(startedAt: 100, duration: 6)
        dog.noteFrame(at: 107.4)
        #expect(dog.verdict(at: 107.4) == .healthy)
        #expect(dog.verdict(at: 107.6) == .overdue)
    }
}

@Suite struct DailyActivityTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    @Test func coversEveryDayOldestFirst() {
        let days = ActivityHistory().daily(days: 7, endingAt: date(10), calendar: calendar)
        #expect(days.count == 7)
        #expect(days.first?.date == calendar.startOfDay(for: date(4)))
        #expect(days.last?.date == calendar.startOfDay(for: date(10)))
        #expect(days.allSatisfy { $0.unlocks == 0 && $0.failures == 0 })
    }

    @Test func countsUnlocksAndFailuresOnTheirDay() {
        var history = ActivityHistory()
        history.add(ActivityEntry(date: date(8), kind: .unlocked))
        history.add(ActivityEntry(date: date(10, 9), kind: .unlocked))
        history.add(ActivityEntry(date: date(10, 10), kind: .stranger))
        history.add(ActivityEntry(date: date(10, 11), kind: .spoof))
        history.add(ActivityEntry(date: date(10, 12), kind: .passwordProblem))
        let days = history.daily(days: 7, endingAt: date(10, 23), calendar: calendar)
        #expect(days[4].unlocks == 1)
        #expect(days[6].unlocks == 1)
        #expect(days[6].failures == 2)
    }

    @Test func ignoresEntriesOutsideTheWindow() {
        var history = ActivityHistory()
        history.add(ActivityEntry(date: date(1), kind: .unlocked))
        let days = history.daily(days: 7, endingAt: date(10), calendar: calendar)
        #expect(days.map(\.unlocks).reduce(0, +) == 0)
    }
}

@Suite struct TrustClockTests {
    @Test func elapsedTimeBoundsTheWindowToo() {
        let window = TrustWindow(grantedAt: Date(), hours: 48)
        #expect(window.isValid(elapsed: 0))
        #expect(window.isValid(elapsed: 47 * 3600))
        #expect(!window.isValid(elapsed: 48 * 3600))
        #expect(!window.isValid(elapsed: -1))
    }
}

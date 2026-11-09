import Foundation
import Testing
@testable import SesameCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// 2026-11-09 is a Monday.
private func date(day: Int = 9, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

private func unmet(_ rules: UnlockRules, at when: Date = date(12), network: String? = "Home", connected: Bool = true) -> UnlockRules.Unmet? {
    rules.firstUnmet(at: when, calendar: calendar, network: network, deviceConnected: connected)
}

@Suite struct UnlockRulesTests {
    @Test func noRulesAllowsEverything() {
        let rules = UnlockRules()
        #expect(rules.isEmpty)
        #expect(unmet(rules, network: nil, connected: false) == nil)
    }

    @Test func networkMustBeTrusted() {
        var rules = UnlockRules()
        rules.trustedNetworks = ["Home"]
        #expect(unmet(rules, network: "Home") == nil)
        #expect(unmet(rules, network: "Cafe") == .network)
    }

    @Test func anUnreadableNetworkFailsClosed() {
        var rules = UnlockRules()
        rules.trustedNetworks = ["Home"]
        #expect(unmet(rules, network: nil) == .network)
    }

    @Test func deviceMustBeConnected() {
        var rules = UnlockRules()
        rules.device = .init(name: "Watch", address: "aa-bb")
        #expect(unmet(rules, connected: true) == nil)
        #expect(unmet(rules, connected: false) == .device)
    }

    @Test func daytimeHours() {
        var rules = UnlockRules()
        rules.hours = .init(start: 9 * 60, end: 17 * 60)
        #expect(unmet(rules, at: date(9)) == nil)
        #expect(unmet(rules, at: date(16, 59)) == nil)
        #expect(unmet(rules, at: date(17)) == .hours)
        #expect(unmet(rules, at: date(8, 59)) == .hours)
    }

    @Test func overnightHours() {
        var rules = UnlockRules()
        rules.hours = .init(start: 22 * 60, end: 6 * 60)
        #expect(unmet(rules, at: date(23)) == nil)
        #expect(unmet(rules, at: date(3)) == nil)
        #expect(unmet(rules, at: date(12)) == .hours)
    }

    @Test func weekdaysOnlySkipsTheWeekend() {
        var rules = UnlockRules()
        rules.hours = .init(start: 0, end: 23 * 60 + 59, weekdaysOnly: true)
        #expect(unmet(rules, at: date(day: 9, 12)) == nil)
        #expect(unmet(rules, at: date(day: 8, 12)) == .hours)
    }

    @Test func anOvernightWindowBelongsToTheDayItStarted() {
        var rules = UnlockRules()
        rules.hours = .init(start: 22 * 60, end: 6 * 60, weekdaysOnly: true)
        // Saturday 2am began on Friday night, Monday 2am began on Sunday night.
        #expect(unmet(rules, at: date(day: 14, 2)) == nil)
        #expect(unmet(rules, at: date(day: 9, 2)) == .hours)
    }

    @Test func networkIsReportedFirst() {
        var rules = UnlockRules()
        rules.trustedNetworks = ["Home"]
        rules.device = .init(name: "Watch", address: "aa-bb")
        #expect(unmet(rules, network: "Cafe", connected: false) == .network)
    }

    @Test func staleFramesAreRejected() {
        let attempt = UnlockAttempt(startedAt: 0)
        #expect(attempt.isFresh(capturedAt: 10, now: 10.4))
        #expect(!attempt.isFresh(capturedAt: 10, now: 10.6))
    }
}

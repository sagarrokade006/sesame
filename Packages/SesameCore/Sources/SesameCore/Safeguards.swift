import Foundation

/// How long a Touch ID approval stays good. Using the Mac never extends it.
public struct TrustWindow: Codable, Sendable, Equatable {
    public var grantedAt: Date
    public var hours: Int

    public static let defaultHours = 48

    public init(grantedAt: Date, hours: Int = TrustWindow.defaultHours) {
        self.grantedAt = grantedAt
        self.hours = hours
    }

    public func isValid(at now: Date) -> Bool {
        now >= grantedAt && now.timeIntervalSince(grantedAt) < TimeInterval(hours) * 3600
    }

    /// The same window measured on a clock that can't be set, such as time since boot including sleep. Both have to
    /// agree, so turning the Mac's clock back doesn't stretch an approval.
    public func isValid(elapsed: TimeInterval) -> Bool {
        elapsed >= 0 && elapsed < TimeInterval(hours) * 3600
    }
}

/// Stops an endless stream of attempts at one lock screen.
public struct AttemptCounter: Sendable, Equatable {
    public let limit: Int
    public private(set) var failures = 0

    public init(limit: Int = 5) {
        self.limit = limit
    }

    public var isExhausted: Bool { failures >= limit }

    public mutating func recordFailure() { failures += 1 }

    /// Only for after the Mac was genuinely unlocked.
    public mutating func reset() { failures = 0 }
}

public enum PasswordCheck: Sendable, Equatable {
    case accepted
    case rejected
    /// macOS couldn't answer, which says nothing about the password.
    case unavailable

    public static func from(openDirectoryCode code: Int) -> PasswordCheck {
        code == 5000 ? .rejected : .unavailable
    }
}

/// Whether the stored Mac password still works. Typing a stale one would rack up failed logins.
public struct PasswordHealth: Codable, Sendable, Equatable {
    public private(set) var lastVerified: Date?
    public private(set) var lastUnlock: Date?
    public private(set) var missedEntries = 0
    public private(set) var isOutdated = false

    public init() {}

    public mutating func record(_ check: PasswordCheck, at date: Date) {
        switch check {
        case .accepted:
            lastVerified = date
            missedEntries = 0
            isOutdated = false
        case .rejected:
            isOutdated = true
        case .unavailable:
            break
        }
    }

    public mutating func recordUnlock(at date: Date) {
        lastUnlock = date
        missedEntries = 0
        isOutdated = false
    }

    /// One miss can be a focus problem, so it takes two in a row.
    public mutating func recordMissedEntry() {
        missedEntries += 1
        if missedEntries >= 2 { isOutdated = true }
    }
}

public struct ActivityEntry: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case unlocked
        case stranger
        case spoof
        case paused
        case passwordProblem
    }

    public var id: UUID
    public var date: Date
    public var kind: Kind
    public var note: String?

    public init(id: UUID = UUID(), date: Date, kind: Kind, note: String? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.note = note
    }
}

public struct ActivityHistory: Codable, Sendable, Equatable {
    public static let capacity = 150

    /// Newest first.
    public private(set) var entries: [ActivityEntry] = []

    public init() {}

    public mutating func add(_ entry: ActivityEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity { entries.removeLast() }
    }

    public mutating func clear() { entries = [] }

    /// One day's totals, for the week chart.
    public struct Day: Sendable, Equatable, Identifiable {
        public let date: Date
        public var unlocks = 0
        public var failures = 0

        public var id: Date { date }
    }

    /// The last `days` days, oldest first, ending today. Days with nothing still appear, with zeros.
    public func daily(days: Int, endingAt now: Date, calendar: Calendar) -> [Day] {
        let today = calendar.startOfDay(for: now)
        var result = (0..<max(days, 0)).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { Day(date: $0) }
        }
        for entry in entries {
            let day = calendar.startOfDay(for: entry.date)
            guard let index = result.firstIndex(where: { $0.date == day }) else { continue }
            switch entry.kind {
            case .unlocked: result[index].unlocks += 1
            case .stranger, .spoof: result[index].failures += 1
            case .paused, .passwordProblem: break
            }
        }
        return result
    }

    /// Failed attempts since the most recent unlock before now.
    public var failuresWhileAway: Int {
        let afterNewest = entries.first?.kind == .unlocked ? Array(entries.dropFirst()) : entries
        return afterNewest.prefix { $0.kind != .unlocked }.filter { $0.kind == .stranger || $0.kind == .spoof }.count
    }
}

/// Splits a password into small keystroke batches without breaking a surrogate pair.
public enum KeystrokeBatches {
    public static func ranges(for utf16: [UInt16], limit: Int = 16) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        while start < utf16.count {
            var end = min(start + limit, utf16.count)
            if end < utf16.count, end - start > 1, UTF16.isLeadSurrogate(utf16[end - 1]) {
                end -= 1
            }
            result.append(start..<end)
            start = end
        }
        return result
    }
}

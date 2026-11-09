import Foundation

/// Face unlock switched off by its owner, either until a set time or until they turn it back on.
public struct Pause: Codable, Sendable, Equatable {
    /// nil means until it's turned back on.
    public var until: Date?

    public init(until: Date? = nil) {
        self.until = until
    }

    public func isActive(at now: Date) -> Bool {
        until.map { now < $0 } ?? true
    }

    public static func forHours(_ hours: Int, from now: Date) -> Pause {
        Pause(until: now.addingTimeInterval(TimeInterval(hours) * 3600))
    }

    /// Until the start of the next day.
    public static func untilTomorrow(from now: Date, calendar: Calendar) -> Pause {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        return Pause(until: tomorrow ?? now.addingTimeInterval(24 * 3600))
    }
}

/// Works out whether a scan that found nobody was simply too dark to see anyone.
public struct DarknessJudge: Sendable, Equatable {
    /// Average brightness, 0 to 1, below which a webcam frame is too dark for face detection.
    public static let darkLevel = 0.12
    private static let minimumFrames = 15
    private static let darkShare = 0.7

    private var frames = 0
    private var darkFrames = 0

    public init() {}

    /// Call with the brightness of each frame that had no face in it.
    public mutating func observe(brightness: Double) {
        frames += 1
        if brightness < Self.darkLevel { darkFrames += 1 }
    }

    /// True once most of a meaningful number of faceless frames were dark.
    public var isTooDark: Bool {
        frames >= Self.minimumFrames && Double(darkFrames) / Double(frames) >= Self.darkShare
    }
}

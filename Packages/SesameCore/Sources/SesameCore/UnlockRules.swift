import Foundation

/// Where and when face unlock may run. Each rule is off until it's set, and a rule that can't be checked counts as unmet.
public struct UnlockRules: Codable, Sendable, Equatable {
    public struct Device: Codable, Sendable, Equatable, Identifiable {
        public var name: String
        public var address: String

        public var id: String { address }

        public init(name: String, address: String) {
            self.name = name
            self.address = address
        }
    }

    /// Minutes after midnight. A start later than the end runs overnight.
    public struct Hours: Codable, Sendable, Equatable {
        public var start: Int
        public var end: Int
        public var weekdaysOnly: Bool

        public init(start: Int = 8 * 60, end: Int = 20 * 60, weekdaysOnly: Bool = false) {
            self.start = start
            self.end = end
            self.weekdaysOnly = weekdaysOnly
        }

        public func contains(_ date: Date, calendar: Calendar) -> Bool {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            let overnight = start > end
            let inside = overnight ? minute >= start || minute < end : minute >= start && minute < end
            guard inside, weekdaysOnly else { return inside }
            // Past midnight, an overnight window still belongs to the day it began.
            let day = overnight && minute < end ? calendar.date(byAdding: .day, value: -1, to: date) ?? date : date
            return !calendar.isDateInWeekend(day)
        }
    }

    public enum Unmet: Sendable, Equatable {
        case network
        case device
        case hours

        public var explanation: String {
            switch self {
            case .network: return "You're not on a trusted Wi-Fi network."
            case .device: return "Your trusted Bluetooth device isn't connected."
            case .hours: return "It's outside your unlock hours."
            }
        }
    }

    /// Empty means any network.
    public var trustedNetworks: [String] = []
    public var device: Device?
    public var hours: Hours?

    public init() {}

    public var isEmpty: Bool { trustedNetworks.isEmpty && device == nil && hours == nil }

    /// `network` is nil when macOS won't say, which fails the network rule rather than skipping it.
    public func firstUnmet(at date: Date, calendar: Calendar, network: String?, deviceConnected: Bool) -> Unmet? {
        if !trustedNetworks.isEmpty, !(network.map(trustedNetworks.contains) ?? false) { return .network }
        if device != nil, !deviceConnected { return .device }
        if let hours, !hours.contains(date, calendar: calendar) { return .hours }
        return nil
    }
}

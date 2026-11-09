import Foundation

/// Tracks one macOS privacy permission from inside the running app.
///
/// macOS answers these checks once per process: a permission granted while Sesame runs often still reads as denied,
/// and keystrokes stay blocked until Sesame restarts. So once someone has been sent to grant it, or it changed while
/// running, the honest next step is a restart, not waiting for a change that never shows up.
public struct PermissionGate: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        /// Works now.
        case ready
        /// Never asked in this run.
        case needsPermission
        /// Asked, or changed while running. Only a fresh copy of Sesame can tell, and use it.
        case needsRestart
    }

    private var sawDenied: Bool
    private var hasAsked = false
    private var wasBlocked = false
    public private(set) var state: State

    public init(grantedAtLaunch: Bool) {
        sawDenied = !grantedAtLaunch
        state = grantedAtLaunch ? .ready : .needsPermission
    }

    /// Call with what macOS reports now.
    @discardableResult
    public mutating func observe(granted: Bool) -> State {
        if !granted { sawDenied = true }
        state = Self.state(granted: granted, sawDenied: sawDenied, hasAsked: hasAsked, wasBlocked: wasBlocked)
        return state
    }

    /// Call after showing the system prompt or System Settings.
    public mutating func noteAsked(grantedNow: Bool) {
        hasAsked = true
        observe(granted: grantedNow)
    }

    /// Call when the permission reads as granted but didn't work, such as keystrokes that never arrived.
    public mutating func noteBlocked() {
        wasBlocked = true
        state = .needsRestart
    }

    private static func state(granted: Bool, sawDenied: Bool, hasAsked: Bool, wasBlocked: Bool) -> State {
        if wasBlocked { return .needsRestart }
        if granted { return sawDenied ? .needsRestart : .ready }
        return hasAsked ? .needsRestart : .needsPermission
    }
}

/// What to make of the Mac staying locked after Sesame typed the password.
public enum EntryMiss: Sendable, Equatable {
    /// macOS accepts the saved password, so the keystrokes never reached the lock screen.
    case keystrokesBlocked
    /// macOS rejected the saved password.
    case wrongPassword
    /// macOS couldn't say. Count it as a miss and let two in a row mark the password out of date.
    case unknown

    public init(recheck: PasswordCheck) {
        switch recheck {
        case .accepted: self = .keystrokesBlocked
        case .rejected: self = .wrongPassword
        case .unavailable: self = .unknown
        }
    }
}

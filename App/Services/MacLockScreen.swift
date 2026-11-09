import AppKit
import ApplicationServices
import CoreGraphics
import SesameCore

enum MacLockScreen {
    /// The session's own answer. Lock notifications can be posted by any process, so they only ever prompt a check.
    nonisolated static var isLocked: Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool ?? false
    }

    nonisolated static var canType: Bool { AXIsProcessTrusted() }

    static func requestTypingPermission() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

/// Types the password at the login window.
enum PasswordTyper {
    private static let batchPause: TimeInterval = 0.012
    /// The login window keeps its password field hidden until a key is pressed, and swallows typing until it appears.
    private static let fieldRevealPause: TimeInterval = 0.6
    private static let beforeReturnPause: TimeInterval = 0.12

    enum Failure: Error {
        case noLongerLocked
        case eventFailed
    }

    /// Re-checks the lock before every keystroke batch, so nothing lands in an app that took focus after an unlock.
    nonisolated static func type(_ password: Data, isStillLocked: () -> Bool) throws {
        guard var units = String(data: password, encoding: .utf8).map({ Array($0.utf16) }) else { throw Failure.eventFailed }
        defer { units.indices.forEach { units[$0] = 0 } }

        let source = CGEventSource(stateID: .hidSystemState)
        guard isStillLocked() else { throw Failure.noLongerLocked }
        // Left Arrow reveals the hidden field without typing anything into it.
        try tap(keyCode: 0x7B, command: false, source: source)
        Thread.sleep(forTimeInterval: fieldRevealPause)

        guard isStillLocked() else { throw Failure.noLongerLocked }
        try tap(keyCode: 0x7C, command: true, source: source)
        try tap(keyCode: 0x33, command: true, source: source)
        Thread.sleep(forTimeInterval: 0.05)

        for range in KeystrokeBatches.ranges(for: units) {
            guard isStillLocked() else { throw Failure.noLongerLocked }
            try send(Array(units[range]), source: source)
        }
        Thread.sleep(forTimeInterval: beforeReturnPause)
        guard isStillLocked() else { throw Failure.noLongerLocked }
        try tap(keyCode: 0x24, command: false, source: source)
    }

    private nonisolated static func send(_ text: [UInt16], source: CGEventSource?) throws {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
        else { throw Failure.eventFailed }
        down.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text)
        up.keyboardSetUnicodeString(stringLength: text.count, unicodeString: text)
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: batchPause)
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: batchPause)
    }

    private nonisolated static func tap(keyCode: CGKeyCode, command: Bool, source: CGEventSource?) throws {
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false),
              let commandDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let commandUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
        else { throw Failure.eventFailed }
        if command {
            commandDown.flags = .maskCommand
            down.flags = .maskCommand
            up.flags = .maskCommand
            commandUp.flags = []
            commandDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.015)
        }
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.015)
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.015)
        if command {
            commandUp.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.015)
        }
    }
}

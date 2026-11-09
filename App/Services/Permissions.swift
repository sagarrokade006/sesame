import AppKit
import ApplicationServices
import AVFoundation
import Observation
import OSLog
import SesameCore

/// The three macOS permissions Sesame depends on, watched for the whole life of the app.
@MainActor
@Observable
final class Permissions {
    static let shared = Permissions()

    private(set) var camera = AVCaptureDevice.authorizationStatus(for: .video)
    /// Accessibility plus permission to post keyboard events, so the password reaches the lock screen.
    private(set) var typing: PermissionGate
    /// Input Monitoring, so Space can start a scan at the lock screen.
    private(set) var space: PermissionGate

    /// Set while the person is off approving something, so Sesame only comes forward when they expect it.
    @ObservationIgnored private var isWaiting = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastSummary = ""
    @ObservationIgnored private let log = Logger(subsystem: "com.sagarrokade.sesame", category: "permissions")

    private init() {
        typing = PermissionGate(grantedAtLaunch: Self.canType)
        space = PermissionGate(grantedAtLaunch: Self.canHearSpace)
    }

    nonisolated static var canType: Bool { AXIsProcessTrusted() && CGPreflightPostEventAccess() }
    nonisolated static var canHearSpace: Bool { RetryTriggers.canHearSpace }

    /// Whether a typed password will actually reach the lock screen.
    var isTypingReady: Bool { typing.state == .ready }

    /// macOS doesn't announce permission changes, so this polls while Sesame runs.
    func startWatching() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { Permissions.shared.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func refresh() {
        #if DEBUG
        if Snapshot.folder != nil { return }
        #endif
        let cameraNow = AVCaptureDevice.authorizationStatus(for: .video)
        let accessibility = AXIsProcessTrusted()
        let postEvents = CGPreflightPostEventAccess()
        let listen = Self.canHearSpace

        let gained = (cameraNow == .authorized && camera != .authorized)
            || (accessibility && postEvents && typing.state != .ready)
            || (listen && space.state != .ready)
        if cameraNow != camera { camera = cameraNow }
        var nextTyping = typing
        nextTyping.observe(granted: accessibility && postEvents)
        if nextTyping != typing { typing = nextTyping }
        var nextSpace = space
        nextSpace.observe(granted: listen)
        if nextSpace != space { space = nextSpace }

        let summary = "camera=\(cameraNow.rawValue) accessibility=\(accessibility) postEvents=\(postEvents) inputMonitoring=\(listen) typing=\(typing.state) space=\(space.state)"
        if summary != lastSummary {
            lastSummary = summary
            log.notice("\(summary, privacy: .public)")
        }
        if gained, isWaiting {
            isWaiting = false
            AppModel.bringToFront()
        }
    }

    func askForCamera() async {
        isWaiting = true
        if camera == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            AppModel.bringToFront()
        } else {
            // macOS only asks once, so after that the switch has to be flipped in System Settings.
            Self.openSettings("Privacy_Camera")
        }
        refresh()
    }

    func askForTyping() {
        isWaiting = true
        // Adds Sesame to the Accessibility list and shows the system prompt, whose button opens System Settings.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        CGRequestPostEventAccess()
        typing.noteAsked(grantedNow: Self.canType)
    }

    func askForSpace() {
        isWaiting = true
        if !RetryTriggers.requestSpaceAccess() {
            Self.openSettings("Privacy_ListenEvent")
        }
        space.noteAsked(grantedNow: Self.canHearSpace)
    }

    func openTypingSettings() { Self.openSettings("Privacy_Accessibility") }
    func openSpaceSettings() { Self.openSettings("Privacy_ListenEvent") }

    /// Keystrokes went nowhere although macOS says they're allowed.
    func noteTypingBlocked() {
        typing.noteBlocked()
    }

    /// Quits and opens a fresh copy, which is the only way to pick up permissions changed while running.
    /// The new copy opens its window and asks for Touch ID right away.
    static func restartSesame() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\" --args --resume",
            Bundle.main.bundlePath, String(ProcessInfo.processInfo.processIdentifier),
        ]
        do {
            try task.run()
            NSApp.terminate(nil)
        } catch {
            Logger(subsystem: "com.sagarrokade.sesame", category: "permissions")
                .error("restart failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static var wasRestarted: Bool { CommandLine.arguments.contains("--resume") }

    private static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    #if DEBUG
    /// Snapshot runs don't have the app's permissions, so they say what the picture should show.
    func pretend(granted: Bool) {
        camera = granted ? .authorized : .notDetermined
        typing = PermissionGate(grantedAtLaunch: granted)
        space = PermissionGate(grantedAtLaunch: granted)
    }

    /// Shows the "Open Settings / Restart" state for both permissions.
    func pretendAskedButNotApplied() {
        camera = .authorized
        typing = PermissionGate(grantedAtLaunch: false)
        typing.noteAsked(grantedNow: false)
        space = PermissionGate(grantedAtLaunch: false)
        space.noteAsked(grantedNow: false)
    }
    #endif
}

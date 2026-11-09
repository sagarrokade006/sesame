import AppKit
import Observation
import OSLog
import SesameCore

/// Numbers and yes/no states only, never names, faces, or passwords. Read with:
/// log show --last 30m --predicate 'subsystem == "com.sagarrokade.sesame"'
private let scanLog = Logger(subsystem: "com.sagarrokade.sesame", category: "unlock")

/// Watches for the Mac locking and waking, and runs one scan at a time.
@MainActor
@Observable
final class UnlockController {
    private(set) var statusLine = "Waiting"

    @ObservationIgnored private let vault: Vault
    @ObservationIgnored private let camera = CameraFeed()
    @ObservationIgnored private let reader = FaceReader()
    @ObservationIgnored private let badge = LockBadge()
    @ObservationIgnored private var attempt: UnlockAttempt?
    @ObservationIgnored private var scanID = UUID()
    @ObservationIgnored private var counter = AttemptCounter()
    @ObservationIgnored private var lastTriggerAt: Date?
    @ObservationIgnored private var isConfirmingEntry = false
    @ObservationIgnored private var unlockNotificationPending = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let triggers = RetryTriggers()
    @ObservationIgnored private var retry = RetryBudget()
    @ObservationIgnored private var followUp: Task<Void, Never>?
    @ObservationIgnored private var isSleeping = false
    @ObservationIgnored private var watchdog: ScanWatchdog?
    @ObservationIgnored private var watchdogTimer: Timer?
    @ObservationIgnored private var pendingScan: Task<Void, Never>?
    @ObservationIgnored private var darkness = DarknessJudge()
    /// How many failed attempts the last alert covered, so one batch is only announced once.
    @ObservationIgnored private var alertedFailures = 0

    init(vault: Vault) {
        self.vault = vault
        triggers.onRequest = { [weak self] in self?.requestScan() }
        listen()
    }

    var isModelAvailable: Bool { reader.isReady }

    private func listen() {
        let distributed = DistributedNotificationCenter.default()
        let workspace = NSWorkspace.shared.notificationCenter

        func watch(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping @MainActor (UnlockController) -> Void) {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let self { action(self) }
                }
            })
        }

        watch(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.didLock() }
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.didUnlock() }
        watch(distributed, Notification.Name("com.apple.screensaver.didstop")) { $0.scheduleScan() }
        watch(workspace, NSWorkspace.screensDidWakeNotification) { $0.scheduleScan() }
        watch(workspace, NSWorkspace.didWakeNotification) { controller in
            controller.isSleeping = false
            controller.scheduleScan()
        }
        watch(workspace, NSWorkspace.willSleepNotification) { controller in
            controller.isSleeping = true
            controller.standDown()
        }
        // Nobody is looking at a dark display, and the camera light shouldn't stay on behind a closed lid.
        watch(workspace, NSWorkspace.screensDidSleepNotification) { $0.standDown() }
    }

    private var canScan: Bool {
        MacLockScreen.isLocked && attempt == nil && !isConfirmingEntry && vault.isTrusted && vault.hasPassword
            && vault.contents.profiles.contains(where: \.isActive)
    }

    /// Stops everything in flight without counting it as a failed attempt.
    private func standDown() {
        pendingScan?.cancel()
        followUp?.cancel()
        if attempt != nil { scanLog.notice("scan stood down") }
        endScan()
        badge.hide()
    }

    private func didLock() {
        retry.reset()
        triggers.start(ignoringFor: 3)
        if vault.contents.settings.scansWhenLocking {
            scheduleScan()
            return
        }
        // Never scans here by default, or locking and walking away could unlock it again.
        followUp?.cancel()
        followUp = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, !isSleeping, canScan else { return }
            badge.show(blocker ?? .message("Face unlock is ready", LockBadge.retryHint))
        }
    }

    /// The pointer or trackpad moving at the lock screen.
    private func requestScan() {
        guard canScan, retry.allowsRequestedScan(at: ProcessInfo.processInfo.systemUptime) else { return }
        followUp?.cancel()
        beginScan()
    }

    /// Tries again by itself, a few times when it clearly saw you, then explains how to ask for another scan.
    private func afterMiss(_ miss: RetryBudget.Miss) {
        let tryAgain = retry.shouldRetryAutomatically(after: miss)
        scanLog.notice("miss \(String(describing: miss), privacy: .public) retrying=\(tryAgain, privacy: .public)")
        followUp?.cancel()
        followUp = Task {
            let pause: Duration = switch miss {
            case .noFace: .milliseconds(400)
            case .unproven: .milliseconds(500)
            case .stranger, .spoof: .milliseconds(1700)
            }
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled, canScan else { return }
            if tryAgain {
                beginScan()
            } else {
                badge.show(.message("Try again", LockBadge.retryHint))
            }
        }
    }

    private func didUnlock() {
        // The notification alone can be forged, so the real session state has to agree.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !MacLockScreen.isLocked else { return }
            counter.reset()
            retry.reset()
            followUp?.cancel()
            pendingScan?.cancel()
            triggers.stop()
            endScan()
            // After a face unlock, `confirmEntry` keeps the checkmark up briefly instead, and alerts itself.
            if !isConfirmingEntry {
                badge.hide()
                alertAboutFailedAttempts()
            }
        }
    }

    /// One lid-open fires several wake signals, so those within two seconds count once.
    private func scheduleScan() {
        let now = Date()
        if let lastTriggerAt, now.timeIntervalSince(lastTriggerAt) < 2 { return }
        lastTriggerAt = now
        retry.reset()
        followUp?.cancel()
        pendingScan?.cancel()
        pendingScan = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            beginScan()
        }
    }

    private var blocker: LockBadge.Content? {
        if !reader.isReady { return .message("Face unlock unavailable", "The recognition model is missing.") }
        if vault.contents.settings.isPaused() { return .message("Face unlock is paused", "Turn it back on from Sesame in the menu bar.") }
        if Permissions.shared.camera != .authorized { return .message("Sesame can't use the camera", "Open Sesame and allow Camera.") }
        if CameraFeed.trustedDevice() == nil { return .message("No camera found", "Connect a camera, or enter your password.") }
        if vault.contents.passwordHealth.isOutdated { return .message("Sesame paused", "Your saved password looks out of date.") }
        if counter.isExhausted { return .message("Sesame paused", "Too many attempts. Enter your password.") }
        if Permissions.shared.typing.state == .needsPermission {
            return .message("Sesame can't type yet", "Open Sesame and allow Accessibility.")
        }
        if Permissions.shared.typing.state == .needsRestart {
            return .message("Restart Sesame", "macOS won't let this copy type your password until it restarts.")
        }
        if let unmet = Surroundings.shared.firstUnmet(vault.contents.settings.unlockRules) {
            return .message("Face unlock is off", unmet.explanation)
        }
        return nil
    }

    private func beginScan() {
        vault.closeIfExpired()
        Permissions.shared.refresh()
        scanLog.notice("scan requested locked=\(MacLockScreen.isLocked, privacy: .public) idle=\(self.attempt == nil, privacy: .public) confirming=\(self.isConfirmingEntry, privacy: .public) vaultTrusted=\(self.vault.isTrusted, privacy: .public) hasPassword=\(self.vault.hasPassword, privacy: .public) activeFaces=\(self.vault.contents.profiles.filter(\.isActive).count, privacy: .public) typing=\(String(describing: Permissions.shared.typing.state), privacy: .public) model=\(self.reader.isReady, privacy: .public)")
        guard canScan else { return }
        triggers.start()
        if let blocker {
            badge.show(blocker)
            return
        }

        let settings = vault.contents.settings
        var rules = UnlockAttempt.Rules()
        rules.requiresAttention = settings.requiresAttention
        rules.requiresBlink = settings.requiresBlink
        let challenge = settings.usesTurnChallenge ? TurnChallenge(direction: TurnDirection.allCases.randomElement() ?? .left) : nil
        if challenge != nil { rules.duration = 9 }

        let id = UUID()
        scanID = id
        let startedAt = ProcessInfo.processInfo.systemUptime
        attempt = UnlockAttempt(rules: rules, challenge: challenge, startedAt: startedAt)
        watchdog = ScanWatchdog(startedAt: startedAt, duration: rules.duration)
        startWatchdog()
        showProgress()

        let reader = self.reader
        darkness = DarknessJudge()
        camera.start { [weak self] pixels, time in
            let capture = reader.read(pixels, at: time)
            let brightness = capture == nil ? FaceReader.brightness(of: pixels) : nil
            Task { @MainActor in self?.receive(capture, brightness: brightness, at: time, scan: id) }
        }
    }

    /// Ends a scan the camera has gone quiet on, which nothing else would end.
    private func startWatchdog() {
        watchdogTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkWatchdog() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    private func checkWatchdog() {
        guard let attempt, let verdict = watchdog?.verdict(at: ProcessInfo.processInfo.systemUptime), verdict != .healthy else { return }
        scanLog.error("scan ended by watchdog: \(String(describing: verdict), privacy: .public)")
        let sawOwner = attempt.sawOwner
        endScan()
        switch verdict {
        case .healthy:
            break
        case .cameraSilent, .cameraStalled:
            // Another app may be holding the camera, or it was unplugged. One more try, then say so.
            if retry.shouldRetryAutomatically(after: .noFace) {
                badge.hide()
                followUp?.cancel()
                followUp = Task {
                    try? await Task.sleep(for: .milliseconds(600))
                    guard !Task.isCancelled, canScan else { return }
                    beginScan()
                }
            } else {
                badge.show(.message("Camera isn't responding", "Another app may be using it. Enter your password."))
            }
        case .overdue:
            badge.hide()
            afterMiss(sawOwner ? .unproven : .noFace)
        }
    }

    private func showProgress() {
        if let challenge = attempt?.challenge, !challenge.isComplete {
            badge.show(.turn(challenge.direction, progress: challenge.progress))
        } else if attempt?.isWaitingForProof == true {
            badge.show(.blink(headMovementCounts: !vault.contents.settings.requiresBlink))
        } else {
            badge.show(.scanning)
        }
    }

    private func receive(_ capture: FaceCapture?, brightness: Double?, at time: TimeInterval, scan: UUID) {
        guard scan == scanID, var current = attempt else { return }
        watchdog?.noteFrame(at: ProcessInfo.processInfo.systemUptime)
        // A frame that queued behind a slow one may show a moment that has passed.
        guard current.isFresh(capturedAt: time, now: ProcessInfo.processInfo.systemUptime) else {
            scanLog.notice("frame stale")
            return
        }
        guard MacLockScreen.isLocked else {
            endScan()
            badge.hide()
            return
        }

        let outcome: UnlockAttempt.Outcome
        if let capture {
            let contents = vault.contents
            let verdict = contents.settings.matchRule.verdict(
                for: capture.vector, among: contents.profiles, modelVersion: FaceReader.modelVersion
            )
            outcome = current.observe(capture.reading, verdict: verdict)
            let best = contents.profiles.filter(\.isActive).map { $0.score(for: capture.vector) }.max() ?? -1
            let reading = capture.reading
            scanLog.notice("frame score=\(best, format: .fixed(precision: 3), privacy: .public) yaw=\(reading.yaw, format: .fixed(precision: 2), privacy: .public) pitch=\(reading.pitch ?? 0, format: .fixed(precision: 2), privacy: .public) eyes=\(reading.leftEyeOpenness ?? -1, format: .fixed(precision: 2), privacy: .public)/\(reading.rightEyeOpenness ?? -1, format: .fixed(precision: 2), privacy: .public) framed=\(reading.isFramedByRectangle, privacy: .public) width=\(capture.widthFraction, format: .fixed(precision: 2), privacy: .public)")
        } else {
            outcome = current.observeNoFace(at: time)
            if let brightness { darkness.observe(brightness: brightness) }
            scanLog.notice("frame no face brightness=\(brightness ?? -1, format: .fixed(precision: 2), privacy: .public)")
        }
        if outcome != .keepWatching { scanLog.notice("scan outcome \(String(describing: outcome).prefix(8), privacy: .public)") }
        attempt = current

        switch outcome {
        case .keepWatching:
            showProgress()
        case .unlock(let name):
            endScan()
            badge.show(.success)
            enterPassword(for: name)
        case .stranger:
            fail(.stranger, note: nil)
        case .spoof:
            fail(.spoof, note: "A screen or card shape surrounded the face.")
        case .expired:
            endScan()
            if current.sawOwner {
                // Recognized but never blinked: keep the prompt up and look again.
                badge.show(.blink(headMovementCounts: !vault.contents.settings.requiresBlink))
                afterMiss(.unproven)
            } else if darkness.isTooDark {
                // Trying again in the dark would only fail the same way, so say why instead.
                scanLog.notice("too dark to see a face")
                badge.show(.message("It's too dark to see you", "Turn on a light, or enter your password."))
            } else {
                badge.hide()
                afterMiss(.noFace)
            }
        }
    }

    private func endScan() {
        if attempt != nil { retry.noteAttemptEnded(at: ProcessInfo.processInfo.systemUptime) }
        scanID = UUID()
        attempt = nil
        watchdog = nil
        watchdogTimer?.invalidate()
        watchdogTimer = nil
        camera.stop()
    }

    private func fail(_ kind: ActivityEntry.Kind, note: String?) {
        endScan()
        counter.recordFailure()
        log(kind, note: note)
        if counter.isExhausted {
            log(.paused, note: "\(counter.limit) failed attempts.")
            badge.show(.message("Sesame paused", "Too many attempts. Enter your password."))
        } else {
            badge.show(.failure)
            afterMiss(kind == .spoof ? .spoof : .stranger)
        }
    }

    /// After any unlock, says so once if someone else tried while the owner was away.
    private func alertAboutFailedAttempts() {
        let failures = vault.contents.activity.failuresWhileAway
        guard vault.contents.settings.alertsOnFailedAttempts, failures > 0, failures != alertedFailures else { return }
        alertedFailures = failures
        Alerts.failedAttempts(failures)
    }

    private func log(_ kind: ActivityEntry.Kind, note: String?) {
        vault.update { $0.activity.add(ActivityEntry(date: Date(), kind: kind, note: note)) }
    }

    private func enterPassword(for name: String) {
        scanLog.notice("entering password typing=\(String(describing: Permissions.shared.typing.state), privacy: .public)")
        guard Permissions.shared.isTypingReady, var password = try? vault.openPassword() else {
            log(.passwordProblem, note: "Sesame couldn't type the password.")
            badge.show(.failure)
            return
        }
        isConfirmingEntry = true
        Task {
            let secret = password
            password.resetBytes(in: 0..<password.count)
            let typed = await Task.detached(priority: .userInitiated) { () -> Bool in
                var copy = secret
                defer { copy.resetBytes(in: 0..<copy.count) }
                return (try? PasswordTyper.type(copy, isStillLocked: { MacLockScreen.isLocked })) != nil
            }.value
            await confirmEntry(typed: typed, name: name)
        }
    }

    private func confirmEntry(typed: Bool, name: String) async {
        defer { isConfirmingEntry = false }
        scanLog.notice("password typed=\(typed, privacy: .public)")
        guard typed else {
            badge.hide()
            return
        }
        for _ in 0..<50 where MacLockScreen.isLocked {
            try? await Task.sleep(for: .milliseconds(100))
        }
        scanLog.notice("after typing stillLocked=\(MacLockScreen.isLocked, privacy: .public)")
        if MacLockScreen.isLocked {
            // A correct password doesn't count as a failed login, so asking macOS is safe and tells the two failures apart.
            let miss = EntryMiss(recheck: await vault.recheckPassword())
            scanLog.notice("entry miss \(String(describing: miss), privacy: .public)")
            switch miss {
            case .keystrokesBlocked:
                // Scanning again would only repeat the miss, so stop until Sesame restarts.
                Permissions.shared.noteTypingBlocked()
                log(.passwordProblem, note: "macOS blocked Sesame's keystrokes. Restart Sesame.")
            case .wrongPassword:
                log(.passwordProblem, note: "Your saved password no longer works. Save the new one.")
            case .unknown:
                vault.update { $0.passwordHealth.recordMissedEntry() }
                log(.passwordProblem, note: "The Mac stayed locked after typing the password.")
            }
            if let blocker { badge.show(blocker) } else { badge.show(.failure) }
        } else {
            vault.update { contents in
                contents.passwordHealth.recordUnlock(at: Date())
                if let index = contents.profiles.firstIndex(where: { $0.isActive && $0.name == name }) {
                    contents.profiles[index].noteUnlock(at: Date())
                }
            }
            if vault.contents.settings.playsUnlockSound { NSSound(named: "Glass")?.play() }
            alertAboutFailedAttempts()
            log(.unlocked, note: name)
            badge.hide(after: .seconds(1.2))
        }
    }
}

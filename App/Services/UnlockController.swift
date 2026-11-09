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

    init(vault: Vault) {
        self.vault = vault
        triggers.hotZone = { LockBadge.hotZone }
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
        watch(workspace, NSWorkspace.willSleepNotification) { $0.isSleeping = true }
    }

    private var canScan: Bool {
        MacLockScreen.isLocked && attempt == nil && !isConfirmingEntry && vault.isTrusted && vault.hasPassword
            && vault.contents.profiles.contains(where: \.isActive)
    }

    private func didLock() {
        retry.reset()
        triggers.start()
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

    /// Space or the pointer reaching the notch.
    private func requestScan() {
        guard canScan, retry.allowsRequestedScan(at: ProcessInfo.processInfo.systemUptime) else { return }
        followUp?.cancel()
        beginScan()
    }

    /// Tries once more by itself, then explains how to ask for another scan.
    private func afterMiss(_ miss: RetryBudget.Miss) {
        let tryAgain = retry.shouldRetryAutomatically(after: miss)
        followUp?.cancel()
        followUp = Task {
            try? await Task.sleep(for: miss == .noFace ? .milliseconds(400) : .milliseconds(1700))
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
            triggers.stop()
            endScan()
            // After a face unlock, `confirmEntry` keeps the checkmark up briefly instead.
            if !isConfirmingEntry { badge.hide() }
        }
    }

    /// One lid-open fires several wake signals, so those within two seconds count once.
    private func scheduleScan() {
        let now = Date()
        if let lastTriggerAt, now.timeIntervalSince(lastTriggerAt) < 2 { return }
        lastTriggerAt = now
        retry.reset()
        followUp?.cancel()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            beginScan()
        }
    }

    private var blocker: LockBadge.Content? {
        if !reader.isReady { return .message("Face unlock unavailable", "The recognition model is missing.") }
        if vault.contents.passwordHealth.isOutdated { return .message("Sesame paused", "Your saved password looks out of date.") }
        if counter.isExhausted { return .message("Sesame paused", "Too many attempts. Enter your password.") }
        if let unmet = Surroundings.shared.firstUnmet(vault.contents.settings.unlockRules) {
            return .message("Face unlock is off", unmet.explanation)
        }
        return nil
    }

    private func beginScan() {
        vault.closeIfExpired()
        scanLog.notice("scan requested locked=\(MacLockScreen.isLocked, privacy: .public) idle=\(self.attempt == nil, privacy: .public) confirming=\(self.isConfirmingEntry, privacy: .public) vaultTrusted=\(self.vault.isTrusted, privacy: .public) hasPassword=\(self.vault.hasPassword, privacy: .public) activeFaces=\(self.vault.contents.profiles.filter(\.isActive).count, privacy: .public) canType=\(MacLockScreen.canType, privacy: .public) model=\(self.reader.isReady, privacy: .public)")
        guard canScan else { return }
        triggers.start()
        if let blocker {
            badge.show(blocker)
            return
        }

        let settings = vault.contents.settings
        var rules = UnlockAttempt.Rules()
        rules.requiresAttention = settings.requiresAttention
        let challenge = settings.usesTurnChallenge ? TurnChallenge(direction: TurnDirection.allCases.randomElement() ?? .left) : nil
        if challenge != nil { rules.duration = 9 }

        let id = UUID()
        scanID = id
        attempt = UnlockAttempt(rules: rules, challenge: challenge, startedAt: ProcessInfo.processInfo.systemUptime)
        showProgress()

        let reader = self.reader
        camera.start { [weak self] pixels, time in
            let capture = reader.read(pixels, at: time)
            Task { @MainActor in self?.receive(capture, at: time, scan: id) }
        }
    }

    private func showProgress() {
        if let challenge = attempt?.challenge, !challenge.isComplete {
            badge.show(.turn(challenge.direction, progress: challenge.progress))
        } else {
            badge.show(.scanning)
        }
    }

    private func receive(_ capture: FaceCapture?, at time: TimeInterval, scan: UUID) {
        guard scan == scanID, var current = attempt else { return }
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
            scanLog.notice("frame no face")
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
            badge.hide()
            afterMiss(.noFace)
        }
    }

    private func endScan() {
        if attempt != nil { retry.noteAttemptEnded(at: ProcessInfo.processInfo.systemUptime) }
        scanID = UUID()
        attempt = nil
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

    private func log(_ kind: ActivityEntry.Kind, note: String?) {
        vault.update { $0.activity.add(ActivityEntry(date: Date(), kind: kind, note: note)) }
    }

    private func enterPassword(for name: String) {
        scanLog.notice("entering password canType=\(MacLockScreen.canType, privacy: .public)")
        guard MacLockScreen.canType, var password = try? vault.openPassword() else {
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
            vault.update { $0.passwordHealth.recordMissedEntry() }
            log(.passwordProblem, note: "The Mac stayed locked after typing the password.")
            if let blocker { badge.show(blocker) } else { badge.show(.failure) }
        } else {
            vault.update { $0.passwordHealth.recordUnlock(at: Date()) }
            log(.unlocked, note: name)
            badge.hide(after: .seconds(1.2))
        }
    }
}

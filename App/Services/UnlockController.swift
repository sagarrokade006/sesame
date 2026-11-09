import AppKit
import Observation
import SesameCore

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

    init(vault: Vault) {
        self.vault = vault
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

        watch(distributed, Notification.Name("com.apple.screenIsLocked")) { controller in
            if controller.vault.contents.settings.scansWhenLocking { controller.scheduleScan() }
        }
        watch(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.didUnlock() }
        watch(distributed, Notification.Name("com.apple.screensaver.didstop")) { $0.scheduleScan() }
        watch(workspace, NSWorkspace.screensDidWakeNotification) { $0.scheduleScan() }
        watch(workspace, NSWorkspace.didWakeNotification) { $0.scheduleScan() }
    }

    private func didUnlock() {
        // The notification alone can be forged, so the real session state has to agree.
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !MacLockScreen.isLocked else { return }
            counter.reset()
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
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            beginScan()
        }
    }

    private var blocker: LockBadge.Content? {
        if !reader.isReady { return .message("Face unlock unavailable", "The recognition model is missing.") }
        if vault.contents.passwordHealth.isOutdated { return .message("Sesame paused", "Your saved password looks out of date.") }
        if counter.isExhausted { return .message("Sesame paused", "Too many attempts. Enter your password.") }
        return nil
    }

    private func beginScan() {
        vault.closeIfExpired()
        guard MacLockScreen.isLocked, attempt == nil, !isConfirmingEntry, vault.isTrusted, vault.hasPassword,
              vault.contents.profiles.contains(where: \.isActive)
        else { return }
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
        } else {
            outcome = current.observeNoFace(at: time)
        }
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
        }
    }

    private func endScan() {
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
        }
    }

    private func log(_ kind: ActivityEntry.Kind, note: String?) {
        vault.update { $0.activity.add(ActivityEntry(date: Date(), kind: kind, note: note)) }
    }

    private func enterPassword(for name: String) {
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
        guard typed else {
            badge.hide()
            return
        }
        for _ in 0..<50 where MacLockScreen.isLocked {
            try? await Task.sleep(for: .milliseconds(100))
        }
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

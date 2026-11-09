import AppKit

/// Asks for another scan when someone moves the pointer or trackpad at the lock screen, anywhere on screen. Runs only
/// while the Mac is locked.
///
/// The keyboard can't be used: the lock screen turns on Secure Event Input, which stops every app, Sesame included,
/// from seeing key presses. The pointer's position is still readable, and moving it is a natural "I'm here".
@MainActor
final class RetryTriggers {
    var onRequest: (() -> Void)?

    /// How far the pointer must move between checks to count, so a still hand or a jittery trackpad doesn't.
    private static let movementThreshold: CGFloat = 8
    private var timer: Timer?
    private var lastLocation: NSPoint?
    private var ignoreUntil: Date = .distantPast

    /// `ignoringFor` covers the moments right after locking, so locking with the mouse and walking off doesn't scan.
    func start(ignoringFor delay: TimeInterval = 0) {
        ignoreUntil = max(ignoreUntil, Date().addingTimeInterval(delay))
        guard timer == nil else { return }
        lastLocation = NSEvent.mouseLocation
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastLocation = nil
        ignoreUntil = .distantPast
    }

    private func checkPointer() {
        let location = NSEvent.mouseLocation
        defer { lastLocation = location }
        guard let lastLocation, Date() >= ignoreUntil else { return }
        if hypot(location.x - lastLocation.x, location.y - lastLocation.y) >= Self.movementThreshold {
            onRequest?()
        }
    }
}

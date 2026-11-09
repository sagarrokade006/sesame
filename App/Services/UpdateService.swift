import AppKit
import Observation
import Sparkle
import UserNotifications

/// Checks GitHub Releases for new versions, tells the user, and installs them in the app.
@MainActor
@Observable
final class UpdateService {
    /// Set when a newer version was found and hasn't been dealt with yet.
    private(set) var availableVersion: String?

    @ObservationIgnored private let bridge = UpdateBridge()
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    init() {
        // A build without a public key can't verify updates, so it never looks for them.
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: bridge)
        bridge.onFound = { [weak self] version in self?.availableVersion = version }
        bridge.onCleared = { [weak self] in self?.availableVersion = nil }
        bridge.onOpen = { [weak self] in self?.checkNow() }
    }

    var isEnabled: Bool { controller != nil }

    var checksAutomatically: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkNow() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }
}

/// Sesame mostly lives in the menu bar, so an update window could appear behind other apps. This shows a notification
/// and a menu bar prompt instead of interrupting.
private final class UpdateBridge: NSObject, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate, @unchecked Sendable {
    var onFound: ((String) -> Void)?
    var onCleared: (() -> Void)?
    var onOpen: (() -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        onFound?(update.displayVersionString)
        if !handleShowingUpdate, !state.userInitiated {
            notify(version: update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func standardUserDriverWillFinishUpdateSession() {
        onCleared?()
    }

    private func notify(version: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Sesame \(version) is available"
            content.body = "Click to update."
            center.add(UNNotificationRequest(identifier: "sesame.update", content: content, trigger: nil))
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        DispatchQueue.main.async { [weak self] in self?.onOpen?() }
        completionHandler()
    }
}

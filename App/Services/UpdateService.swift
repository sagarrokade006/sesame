import AppKit
import Observation
import OSLog
import Sparkle
@preconcurrency import UserNotifications

/// Read with: log show --last 1h --predicate 'subsystem == "com.sagarrokade.sesame" AND category == "updates"'
private let updateLog = Logger(subsystem: "com.sagarrokade.sesame", category: "updates")

/// Checks GitHub Releases for new versions once a day, tells the person, and installs them from inside the app.
/// Every update is checked against the public key in Info.plist before it's installed.
@MainActor
@Observable
final class UpdateService {
    /// Set when a newer version was found and hasn't been installed yet.
    private(set) var availableVersion: String?
    private(set) var lastChecked: Date?
    /// The last check failed, such as no internet. Cleared by the next successful check.
    private(set) var lastError: String?

    @ObservationIgnored private let bridge = UpdateBridge()
    @ObservationIgnored private let watcher = UpdateWatcher()
    @ObservationIgnored private var controller: SPUStandardUpdaterController?

    init() {
        #if DEBUG
        // A development build would replace itself with the released version.
        updateLog.notice("updates are off in debug builds")
        return
        #else
        // A build without a public key can't verify updates, so it never looks for them.
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: watcher, userDriverDelegate: bridge)
        self.controller = controller
        let found: (String) -> Void = { [weak self] version in
            self?.availableVersion = version
            self?.lastError = nil
        }
        bridge.onFound = found
        bridge.onOpen = { [weak self] in self?.checkNow() }
        watcher.onFound = found
        watcher.onNotFound = { [weak self] in
            self?.availableVersion = nil
            self?.lastError = nil
        }
        watcher.onFailed = { [weak self] message in self?.lastError = message }
        watcher.onFinishedCheck = { [weak self] in self?.lastChecked = controller.updater.lastUpdateCheckDate }
        do {
            try controller.updater.start()
            lastChecked = controller.updater.lastUpdateCheckDate
            UpdateNotification.askPermissionIfNeeded()
            updateLog.notice("updater started, version \(Self.currentVersion, privacy: .public), automatic=\(controller.updater.automaticallyChecksForUpdates, privacy: .public)")
        } catch {
            self.controller = nil
            updateLog.error("updater couldn't start: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }

    var isEnabled: Bool {
        #if DEBUG
        if isPretending { return true }
        #endif
        return controller != nil
    }

    #if DEBUG
    @ObservationIgnored private var isPretending = false

    /// For snapshots: shows the update controls as if a real check had happened.
    func pretend(available: String?, lastChecked: Date) {
        isPretending = true
        availableVersion = available
        self.lastChecked = lastChecked
    }
    #endif

    static var currentVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }

    var checksAutomatically: Bool {
        get {
            #if DEBUG
            if isPretending { return true }
            #endif
            return controller?.updater.automaticallyChecksForUpdates ?? false
        }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Shows Sparkle's window, which either offers the update or says Sesame is up to date.
    func checkNow() {
        watcher.isUserInitiated = true
        AppModel.bringToFront()
        controller?.checkForUpdates(nil)
    }
}

/// Hears how each check went. Sparkle may call this off the main thread, so results hop back to it.
private nonisolated final class UpdateWatcher: NSObject, SPUUpdaterDelegate, @unchecked Sendable {
    @MainActor var onFound: ((String) -> Void)?
    @MainActor var onNotFound: (() -> Void)?
    @MainActor var onFailed: ((String) -> Void)?
    @MainActor var onFinishedCheck: (() -> Void)?
    /// Set while a check the person started with Check now is running.
    @MainActor var isUserInitiated = false

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        updateLog.notice("found \(item.displayVersionString, privacy: .public) (\(item.versionString, privacy: .public))")
        let version = item.displayVersionString
        Task { @MainActor in
            self.onFound?(version)
            // A check someone started with Check now shows Sparkle's window. A daily check in the background would
            // otherwise go unnoticed, so it posts a notification.
            if !self.isUserInitiated { UpdateNotification.post(version: version) }
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        updateLog.notice("up to date")
        Task { @MainActor in self.onNotFound?() }
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let nsError = error as NSError
        // "No update" also arrives here; it isn't a failure.
        guard !(nsError.domain == SUSparkleErrorDomain && nsError.code == Int(SUError.noUpdateError.rawValue)) else { return }
        updateLog.error("update failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public) \(nsError.localizedDescription, privacy: .public)")
        let message = nsError.localizedDescription
        Task { @MainActor in self.onFailed?(message) }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        Task { @MainActor in
            self.isUserInitiated = false
            self.onFinishedCheck?()
        }
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        updateLog.notice("installing and relaunching")
    }
}

/// Sesame mostly lives in the menu bar, so an update window could appear behind other apps. Scheduled checks show a
/// notification and an in-app prompt instead of interrupting.
private final class UpdateBridge: NSObject, SPUStandardUserDriverDelegate, UNUserNotificationCenterDelegate, @unchecked Sendable {
    var onFound: ((String) -> Void)?
    var onOpen: (() -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: User driver

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Lets Sparkle show its window only when Sesame is already in front; otherwise this notifies instead.
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        onFound?(update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        UpdateNotification.clear()
    }

    func standardUserDriverWillFinishUpdateSession() {}

    // MARK: Notifications

    /// Shows the banner even while Sesame is the active app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isUpdate = response.notification.request.identifier == UpdateNotification.id
        DispatchQueue.main.async { [weak self] in
            if isUpdate {
                self?.onOpen?()
            } else {
                NotificationCenter.default.post(name: Alerts.opened, object: nil)
            }
        }
        completionHandler()
    }
}

/// The "new version" notification. Posting again replaces the previous one instead of stacking up.
private enum UpdateNotification {
    static let id = "sesame.update"

    /// Asks once, at launch, while the person is likely looking, so a later update notice isn't stuck behind a prompt.
    static func askPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            updateLog.notice("asking for notification permission")
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                updateLog.notice("notification permission \(granted ? "granted" : "declined", privacy: .public)")
            }
        }
    }

    static func post(version: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional:
                let content = UNMutableNotificationContent()
                content.title = "Sesame \(version) is available"
                content.body = "Click to see what's new and install it."
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
                    if let error {
                        updateLog.error("notification failed: \(error.localizedDescription, privacy: .public)")
                    } else {
                        updateLog.notice("notified about \(version, privacy: .public)")
                    }
                }
            case .notDetermined:
                updateLog.notice("asking for notification permission")
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted { post(version: version) }
                }
            default:
                // The in-app banner and About page still show the update.
                updateLog.notice("notifications not allowed")
            }
        }
    }

    static func clear() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }
}

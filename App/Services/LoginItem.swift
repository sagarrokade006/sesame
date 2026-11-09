import Foundation
import Observation
import OSLog
import ServiceManagement

/// Opens Sesame when you log in. Face unlock only works while Sesame is running, so without this a restart quietly
/// turns it off until Sesame is opened by hand.
@MainActor
@Observable
final class LoginItem {
    private(set) var isOn = SMAppService.mainApp.status == .enabled
    /// macOS wants the person to approve it in System Settings › General › Login Items.
    private(set) var needsApproval = SMAppService.mainApp.status == .requiresApproval
    private(set) var error: String?

    @ObservationIgnored private let log = Logger(subsystem: "com.sagarrokade.sesame", category: "login")

    func refresh() {
        #if DEBUG
        if Snapshot.folder != nil { return }
        #endif
        let status = SMAppService.mainApp.status
        if isOn != (status == .enabled) { isOn = status == .enabled }
        if needsApproval != (status == .requiresApproval) { needsApproval = status == .requiresApproval }
    }

    func set(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            log.error("login item change failed: \(error.localizedDescription, privacy: .public)")
            self.error = error.localizedDescription
        }
        refresh()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    #if DEBUG
    func pretend(on: Bool) { isOn = on }
    #endif
}

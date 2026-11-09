import AppKit
import AVFoundation
import Observation
import OSLog
import SwiftUI

@main
struct SesameApp: App {
    @State private var model = AppModel()

    init() {
        #if DEBUG
        if let folder = Snapshot.folder {
            DispatchQueue.main.async { Snapshot.run(in: folder) }
            return
        }
        #endif
        // Two copies would both watch the camera, type the password, and overwrite each other's saved data.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "com.sagarrokade.sesame")
            .filter { $0 != .current }
        if let other = others.first {
            other.activate()
            exit(0)
        }
    }

    var body: some Scene {
        Window("Sesame", id: "main") {
            MainView(model: model)
                .frame(width: MainView.size.width, height: MainView.size.height)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        MenuBarExtra("Sesame", image: "MenuBarIcon") {
            MenuPanel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
@Observable
final class AppModel {
    let vault = Vault()
    let controller: UnlockController
    let updates = UpdateService()
    private(set) var errorMessage: String?
    /// Mirrors of system permissions, which SwiftUI can't observe directly. See `refreshPermissions()`.
    private(set) var cameraAccess = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var canType = MacLockScreen.canType
    @ObservationIgnored private var hasAskedToType = false
    @ObservationIgnored private var hasLoggedPermissions = false
    /// Set while the user is off approving something, so Sesame only comes forward when they were expecting it.
    @ObservationIgnored private var isWaitingForPermission = false
    @ObservationIgnored private let permissionLog = Logger(subsystem: "com.sagarrokade.sesame", category: "permissions")

    init() {
        controller = UnlockController(vault: vault)
    }

    /// macOS doesn't announce permission changes, so the open window calls this regularly.
    #if DEBUG
    /// Snapshot runs don't have the app's permissions, so they say what the picture should show.
    func pretendPermissions(granted: Bool) {
        cameraAccess = granted ? .authorized : .notDetermined
        canType = granted
    }
    #endif

    func refreshPermissions() {
        #if DEBUG
        if Snapshot.folder != nil { return }
        #endif
        let camera = AVCaptureDevice.authorizationStatus(for: .video)
        let typing = MacLockScreen.canType
        let gainedPermission = (camera == .authorized && cameraAccess != .authorized) || (typing && !canType)
        if camera != cameraAccess || typing != canType || !hasLoggedPermissions {
            hasLoggedPermissions = true
            permissionLog.notice("camera=\(camera.rawValue, privacy: .public) accessibility=\(typing, privacy: .public)")
        }
        if camera != cameraAccess { cameraAccess = camera }
        if typing != canType { canType = typing }
        if gainedPermission, isWaitingForPermission {
            isWaitingForPermission = false
            Self.bringToFront()
        }
    }

    /// System prompts and System Settings take focus, and a menu bar app isn't brought back automatically.
    static func bringToFront() {
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
    }

    func requestCamera() async {
        isWaitingForPermission = true
        if cameraAccess == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            Self.bringToFront()
        } else {
            // macOS only asks once, so after that the switch has to be flipped in System Settings.
            openPrivacySettings("Privacy_Camera")
        }
        refreshPermissions()
    }

    func requestTyping() {
        isWaitingForPermission = true
        if hasAskedToType {
            openPrivacySettings("Privacy_Accessibility")
        } else {
            hasAskedToType = true
            MacLockScreen.requestTypingPermission()
        }
    }

    private func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func openVault() async {
        do {
            try await vault.open()
            Self.bringToFront()
            errorMessage = nil
            if vault.hasPassword, !vault.contents.passwordHealth.isOutdated {
                await vault.recheckPassword()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func eraseAll() async {
        guard await vault.requireApproval("erase everything Sesame stores") else { return }
        vault.eraseEverything()
    }
}

private struct MenuPanel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Hexagon()
                    .stroke(Theme.mint, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    .frame(width: 16, height: 16)
                Text("Sesame").font(.system(size: 15, weight: .bold, design: .rounded))
                Spacer()
                Text(model.vault.isTrusted ? "On" : "Locked")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            if let version = model.updates.availableVersion {
                Button("Update to \(version)") { model.updates.checkNow() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.mint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Open Sesame") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                if model.vault.isOpen {
                    Button("Lock") { model.vault.close() }
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
    }
}

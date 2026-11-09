import AppKit
import AVFoundation
import Observation
import OSLog
import SesameCore
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
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.sagarrokade.sesame")
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
    let whatsNew = WhatsNew()
    private(set) var errorMessage: String?
    @ObservationIgnored private var isOpeningVault = false
    let permissions = Permissions.shared
    let loginItem = LoginItem()

    init() {
        controller = UnlockController(vault: vault)
        permissions.startWatching()
        #if DEBUG
        if Snapshot.folder != nil { return }
        #endif
        if !Permissions.wasRestarted, Vault.hasSavedData {
            // Touch ID is needed after every restart, so ask as soon as Sesame starts, such as at login, instead of
            // leaving face unlock off until someone remembers to open the window.
            Task { @MainActor in await self.openVault(showWindow: false) }
        }
        if Permissions.wasRestarted {
            // Came back from "Restart Sesame": pick up where the person left off.
            Task { @MainActor in
                Self.bringToFront()
                await self.openVault()
            }
        }
    }

    var cameraAccess: AVAuthorizationStatus { permissions.camera }

    /// System prompts and System Settings take focus, and a menu bar app isn't brought back automatically.
    static func bringToFront() {
        raiseMainWindow()
        // Touch ID, camera, and Accessibility prompts close a moment after they report back, and take focus with them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { raiseMainWindow() }
    }

    /// macOS no longer lets an app simply take focus back, so this asks whichever app is in front to hand it over.
    private static func raiseMainWindow() {
        let window = NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
            ?? NSApp.windows.first { $0.canBecomeMain }
        if let front = NSWorkspace.shared.frontmostApplication, front != NSRunningApplication.current {
            NSRunningApplication.current.activate(from: front, options: [])
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    /// The saved data exists but this copy of Sesame can't decrypt it, such as after switching between a build from
    /// Xcode and a release, which keep their keys in different places. Only starting over gets past this.
    private(set) var canStartOver = false

    func pause(_ pause: Pause?) {
        vault.update { $0.settings.pause = pause }
    }

    func openVault(showWindow: Bool = true) async {
        guard !vault.isOpen, !isOpeningVault else { return }
        isOpeningVault = true
        defer { isOpeningVault = false }
        do {
            try await vault.open()
            if showWindow { Self.bringToFront() }
            errorMessage = nil
            canStartOver = false
            if vault.hasPassword, !vault.contents.passwordHealth.isOutdated {
                await vault.recheckPassword()
            }
        } catch let error as VaultError {
            errorMessage = error.localizedDescription
            switch error {
            case .keyMissing, .unreadable: canStartOver = true
            default: break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    func pretendKeyMissing() {
        canStartOver = true
        errorMessage = VaultError.keyMissing.localizedDescription
    }
    #endif

    /// Deletes data this copy can't read, then sets up a fresh, empty vault. Opening it asks for Touch ID.
    func startOver() async {
        guard canStartOver else { return }
        vault.eraseEverything()
        canStartOver = false
        errorMessage = nil
        await openVault()
    }

    func eraseAll() async {
        guard await vault.requireApproval("erase everything Sesame stores") else { return }
        vault.eraseEverything()
    }
}

private struct MenuPanel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var status: UnlockStatus { model.unlockStatus }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Hexagon().fill(status.color.opacity(0.18))
                    Hexagon().stroke(status.color, style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                    Image(systemName: symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(status.color)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.primary)
                    Text(status.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)

            if model.vault.isOpen {
                divider
                row(symbol: "pause.fill", title: model.vault.contents.settings.isPaused() ? "Face unlock is paused" : "Pause face unlock") {
                    if model.vault.contents.settings.isPaused() {
                        Button("Turn back on") { model.pause(nil) }
                    } else {
                        PauseMenu(model: model)
                    }
                }
                if let last = model.vault.contents.passwordHealth.lastUnlock {
                    divider
                    row(symbol: "lock.open.fill", title: "Last face unlock") {
                        Text(last.formatted(.relative(presentation: .named)))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondary)
                    }
                }
            }

            if let version = model.updates.availableVersion {
                divider
                row(symbol: "arrow.down.circle.fill", title: "Sesame \(version) is available") {
                    Button("Update") { model.updates.checkNow() }
                        .buttonStyle(FilledButtonStyle(color: Theme.sky))
                }
            }

            divider
            HStack(spacing: 8) {
                if model.vault.isOpen {
                    Button("Open Sesame", action: showWindow).buttonStyle(FilledButtonStyle(color: Theme.mint))
                    Button("Lock") { model.vault.close() }
                } else {
                    Button("Unlock") {
                        showWindow()
                        Task { await model.openVault() }
                    }
                    .buttonStyle(FilledButtonStyle(color: Theme.mint))
                    Button("Open Sesame", action: showWindow)
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .padding(14)
        }
        .frame(width: 310)
        .background(Theme.page)
        .preferredColorScheme(.dark)
    }

    private var symbol: String {
        switch status {
        case .ready: return "checkmark"
        case .locked: return "lock.fill"
        case .setupNeeded: return "list.bullet"
        case .pausedByUser: return "pause.fill"
        case .paused, .off: return "exclamationmark"
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }

    private func row(symbol: String, title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondary)
                .frame(width: 18)
            Text(title).font(.system(size: 12.5)).foregroundStyle(Theme.primary)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private func showWindow() {
        openWindow(id: "main")
        AppModel.bringToFront()
    }
}

/// The three ways to pause: for an hour, until tomorrow, or until it's turned back on.
struct PauseMenu: View {
    let model: AppModel

    var body: some View {
        Menu("Pause") {
            Button("For 1 hour") { model.pause(.forHours(1, from: Date())) }
            Button("Until tomorrow") { model.pause(.untilTomorrow(from: Date(), calendar: .current)) }
            Button("Until I turn it back on") { model.pause(Pause()) }
        }
        .menuStyle(.borderedButton)
        .fixedSize()
    }
}

#if DEBUG
extension AppModel {
    /// For snapshots: the menu bar panel as it looks when opened.
    func menuPanelSnapshot() -> some View { MenuPanel(model: self) }
}
#endif

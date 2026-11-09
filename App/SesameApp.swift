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
    private(set) var errorMessage: String?
    let permissions = Permissions.shared

    init() {
        controller = UnlockController(vault: vault)
        permissions.startWatching()
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
        NSApp.activate()
        NSApp.windows.first { $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
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
                    .buttonStyle(FilledButtonStyle(color: Theme.mint))
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

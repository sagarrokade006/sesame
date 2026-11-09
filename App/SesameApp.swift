import AppKit
import Observation
import SwiftUI

@main
struct SesameApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Sesame", id: "main") {
            MainView(model: model)
                .frame(width: 760, height: 600)
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
    /// Bumped to make views re-read system permission state, which SwiftUI can't observe.
    private(set) var refreshCount = 0

    init() {
        controller = UnlockController(vault: vault)
    }

    func refresh() {
        refreshCount += 1
    }

    func openVault() async {
        do {
            try await vault.open()
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

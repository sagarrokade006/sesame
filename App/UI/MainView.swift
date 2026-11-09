import AVFoundation
import SesameCore
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case faces = "Faces"
    case password = "Password"
    case security = "Security"
    case activity = "Activity"
    case help = "Help"
    case about = "About"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .overview: return "hexagon.fill"
        case .faces: return "person.crop.square.fill"
        case .password: return "key.fill"
        case .security: return "lock.shield.fill"
        case .activity: return "clock.fill"
        case .help: return "questionmark.circle.fill"
        case .about: return "info.circle.fill"
        }
    }
}

struct MainView: View {
    let model: AppModel
    @State private var page = Page.overview

    var body: some View {
        HStack(spacing: 0) {
            rail
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(page.rawValue)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.primary)
                    content
                }
                .padding(.horizontal, 24)
                .padding(.top, 44)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Theme.page)
        .ignoresSafeArea()
        .task {
            // Ends on its own when the window closes.
            while !Task.isCancelled {
                model.refreshPermissions()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var rail: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 9) {
                Hexagon()
                    .stroke(Theme.mint, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                    .frame(width: 20, height: 20)
                Text("Sesame")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primary)
            }
            .padding(.leading, 10)
            .padding(.top, 44)
            .padding(.bottom, 16)

            ForEach(Page.allCases) { item in
                Button { page = item } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(page == item ? Theme.mint : Theme.secondary)
                            .frame(width: 20)
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: page == item ? .semibold : .regular))
                            .foregroundStyle(Theme.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.mint.opacity(page == item ? 0.16 : 0))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: 196)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.rail)
    }

    @ViewBuilder
    private var content: some View {
        if page == .help {
            HelpPage()
        } else if page == .about {
            AboutPage(updates: model.updates)
        } else if !model.vault.isOpen {
            LockedPage(model: model)
        } else {
            switch page {
            case .overview: OverviewPage(model: model, open: { page = $0 })
            case .faces: FacesPage(model: model)
            case .password: PasswordPage(model: model)
            case .security: SecurityPage(model: model)
            case .activity: ActivityPage(model: model)
            case .help: HelpPage()
            case .about: AboutPage(updates: model.updates)
            }
        }
    }
}

struct LockedPage: View {
    let model: AppModel

    var body: some View {
        Panel {
            PanelRow(title: "Sesame is locked", detail: model.errorMessage ?? "Use Touch ID or your Mac password to open it.") {
                Button("Unlock") { Task { await model.openVault() } }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.mint)
            }
        }
    }
}

struct OverviewPage: View {
    let model: AppModel
    let open: (Page) -> Void

    private var vault: Vault { model.vault }

    private var isReady: Bool {
        vault.hasPassword && vault.contents.profiles.contains(where: \.isActive) && model.canType
            && model.controller.isModelAvailable && !vault.contents.passwordHealth.isOutdated
    }

    var body: some View {
        HStack(spacing: 16) {
            ScanMark(state: isReady ? .success : .scanning).frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(isReady ? "Ready to unlock your Mac" : "Finish setting up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                Text(isReady ? "Sesame scans when your Mac wakes." : "Complete the steps below.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

        Panel {
            step("Camera", done: model.cameraAccess == .authorized, action: "Allow") {
                Task { await model.requestCamera() }
            }
            PanelDivider()
            step("Accessibility", detail: model.canType ? "Lets Sesame type your password at the lock screen." : "If it's already on in System Settings, remove Sesame with the minus button, then allow it again.", done: model.canType, action: "Allow") {
                model.requestTyping()
            }
            PanelDivider()
            step("Your face", done: !vault.contents.profiles.isEmpty, action: "Add") { open(.faces) }
            PanelDivider()
            step("Mac password", done: vault.hasPassword && !vault.contents.passwordHealth.isOutdated, action: "Add") { open(.password) }
        }

        if !model.controller.isModelAvailable {
            Text("The face recognition model is missing from this build.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.coral)
        }
    }

    private func step(_ title: String, detail: String? = nil, done: Bool, action: String, perform: @escaping () -> Void) -> some View {
        PanelRow(title: title, detail: detail) {
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.mint)
            } else {
                Button(action, action: perform).tint(Theme.mint)
            }
        }
    }
}

struct PasswordPage: View {
    let model: AppModel
    @State private var entry = ""
    @State private var message: String?
    @State private var isSaving = false

    private var vault: Vault { model.vault }
    private var health: PasswordHealth { vault.contents.passwordHealth }

    var body: some View {
        if health.isOutdated {
            Panel {
                PanelRow(title: "Saved password looks out of date", detail: "Face unlock is paused to avoid failed logins.") {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.amber)
                }
            }
        }

        Panel {
            HStack(spacing: 10) {
                SecureField(vault.hasPassword ? "New Mac password" : "Mac password", text: $entry)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button(isSaving ? "Checking…" : "Save", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.mint)
                    .disabled(entry.isEmpty || isSaving)
            }
            .padding(12)
        }

        if let message {
            Text(message).font(.system(size: 12)).foregroundStyle(Theme.secondary)
        }

        if vault.hasPassword {
            SectionLabel(text: "Health")
            Panel {
                PanelRow(title: "Last verified with macOS") { value(health.lastVerified, fallback: "Not verified") }
                PanelDivider()
                PanelRow(title: "Last face unlock") { value(health.lastUnlock, fallback: "Not yet") }
                PanelDivider()
                PanelRow(title: "Check saved password") {
                    Button("Check") { Task { await vault.recheckPassword() } }
                }
            }
        }

        SectionLabel(text: "Remove")
        Panel {
            PanelRow(title: "Erase everything", detail: "Deletes your faces, password, history, and settings.") {
                Button("Erase", role: .destructive) { Task { await model.eraseAll() } }
            }
        }
    }

    private func value(_ date: Date?, fallback: String) -> some View {
        Text(date?.formatted(date: .abbreviated, time: .shortened) ?? fallback)
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondary)
    }

    private func save() {
        guard !entry.isEmpty, !isSaving else { return }
        isSaving = true
        message = nil
        Task {
            defer { isSaving = false }
            if vault.hasPassword, !(await vault.requireApproval("change the password Sesame stores")) { return }
            do {
                try await vault.savePassword(entry)
                entry = ""
                message = "Saved."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}

struct SecurityPage: View {
    let model: AppModel

    private var vault: Vault { model.vault }
    private var settings: SecuritySettings { vault.contents.settings }

    private func binding<Value>(_ path: WritableKeyPath<SecuritySettings, Value>) -> Binding<Value> {
        Binding(
            get: { vault.contents.settings[keyPath: path] },
            set: { newValue in vault.update { $0.settings[keyPath: path] = newValue } }
        )
    }

    var body: some View {
        if !vault.hasRecentApproval {
            Panel {
                PanelRow(title: "These settings are locked", detail: "Authenticate to change how face unlock works.") {
                    Button("Unlock") { Task { _ = await vault.requireApproval("change Sesame's security settings") } }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.mint)
                }
            }
        }

        Group {
            Panel {
                PanelRow(title: "Turn challenge", detail: "Asks you to turn your head to a random side.") {
                    Toggle("", isOn: binding(\.usesTurnChallenge)).labelsHidden().toggleStyle(.switch).tint(Theme.mint)
                }
                PanelDivider()
                PanelRow(title: "Require attention", detail: "Only unlocks with eyes open, facing the screen.") {
                    Toggle("", isOn: binding(\.requiresAttention)).labelsHidden().toggleStyle(.switch).tint(Theme.mint)
                }
                PanelDivider()
                PanelRow(title: "Scan as soon as the Mac locks", detail: "May unlock again if you're still in view.") {
                    Toggle("", isOn: binding(\.scansWhenLocking)).labelsHidden().toggleStyle(.switch).tint(Theme.mint)
                }
            }

            SectionLabel(text: "Trust")
            Panel {
                PanelRow(title: "Ask for Touch ID every") {
                    Picker("", selection: binding(\.trustHours)) {
                        Text("24 hours").tag(24)
                        Text("48 hours").tag(48)
                        Text("7 days").tag(168)
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
                PanelDivider()
                PanelRow(title: "Match strictness") {
                    Picker("", selection: binding(\.matchRule.acceptScore)) {
                        Text("Standard").tag(Float(0.48))
                        Text("Strict").tag(Float(0.55))
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }
            }

            UnlockRulesSection(vault: vault)
        }
        .disabled(!vault.hasRecentApproval)
        .opacity(vault.hasRecentApproval ? 1 : 0.55)
    }
}

struct ActivityPage: View {
    let model: AppModel

    private var history: ActivityHistory { model.vault.contents.activity }

    var body: some View {
        if history.failuresWhileAway > 0 {
            Panel {
                PanelRow(title: "\(history.failuresWhileAway) failed attempts while you were away", detail: "No images are stored.") {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(Theme.amber)
                }
            }
        }

        Panel {
            if history.entries.isEmpty {
                PanelRow(title: "No activity yet") { EmptyView() }
            }
            ForEach(Array(history.entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { PanelDivider() }
                PanelRow(title: title(entry.kind), detail: entry.note) {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondary)
                }
            }
        }

        if !history.entries.isEmpty {
            Button("Clear history") { model.vault.update { $0.activity.clear() } }
        }
    }

    private func title(_ kind: ActivityEntry.Kind) -> String {
        switch kind {
        case .unlocked: return "Unlocked"
        case .stranger: return "Face not recognized"
        case .spoof: return "Possible spoof"
        case .paused: return "Face unlock paused"
        case .passwordProblem: return "Password problem"
        }
    }
}

struct AboutPage: View {
    let updates: UpdateService

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        Panel {
            PanelRow(title: "Version") {
                Text(version).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            PanelDivider()
            PanelRow(title: "Face recognition", detail: "SFace by OpenCV, Apache License 2.0") { EmptyView() }
            if updates.isEnabled {
                PanelDivider()
                PanelRow(title: "Updates", detail: updates.availableVersion.map { "Version \($0) is available" }) {
                    Button(updates.availableVersion == nil ? "Check now" : "Update") { updates.checkNow() }
                }
                PanelDivider()
                PanelRow(title: "Check automatically") {
                    Toggle("", isOn: Binding(
                        get: { updates.checksAutomatically },
                        set: { updates.checksAutomatically = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(Theme.mint)
                }
            }
        }
        Text("Sesame is a convenience tool and isn't as secure as Face ID or Touch ID. A webcam sees a flat image, and Sesame signs in by typing your saved password.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondary)
    }
}

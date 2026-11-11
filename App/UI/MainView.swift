import AVFoundation
import SesameCore
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case faces = "Faces"
    case password = "Password"
    case security = "Security"
    case conditions = "Conditions"
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
        case .conditions: return "location.fill"
        case .activity: return "clock.fill"
        case .help: return "questionmark.circle.fill"
        case .about: return "info.circle.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .overview: return "How face unlock is doing on this Mac."
        case .faces: return "The people Sesame recognizes."
        case .password: return "Sesame types this at the lock screen once it knows it's you."
        case .security: return "How strict a scan has to be before Sesame unlocks."
        case .conditions: return "Only unlock in places and at times you trust."
        case .activity: return "Every unlock and failed attempt. No images are kept."
        case .help: return "Answers to common questions."
        case .about: return ""
        }
    }

    static let groups: [(String?, [Page])] = [
        (nil, [.overview]),
        ("Unlock", [.faces, .password]),
        ("Protection", [.security, .conditions, .activity]),
    ]
}

struct MainView: View {
    static let size = CGSize(width: 820, height: 700)

    let model: AppModel
    @State private var page: Page

    init(model: AppModel, page: Page = .overview) {
        self.model = model
        _page = State(initialValue: page)
    }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, page: $page)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if page != .about {
                        PageHeader(title: page.rawValue, subtitle: page.subtitle)
                    }
                    content
                }
                .id(page)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .padding(.horizontal, 28)
                .padding(.top, 46)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            .animation(.easeOut(duration: 0.18), value: page)
        }
        .onReceive(NotificationCenter.default.publisher(for: Alerts.opened)) { _ in
            page = .activity
            AppModel.bringToFront()
        }
        .background(Theme.page)
        .ignoresSafeArea()
        .task {
            // Ends on its own when the window closes.
            while !Task.isCancelled {
                model.permissions.refresh()
                model.loginItem.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if page == .help {
            HelpPage()
        } else if page == .about {
            AboutPage(updates: model.updates, whatsNew: model.whatsNew, loginItem: model.loginItem)
        } else if !model.vault.isOpen {
            LockedPage(model: model)
        } else {
            switch page {
            case .overview: OverviewPage(model: model, open: { page = $0 })
            case .faces: FacesPage(model: model)
            case .password: PasswordPage(model: model)
            case .security: SecurityPage(model: model)
            case .conditions: ConditionsPage(model: model)
            case .activity: ActivityPage(model: model)
            case .help: HelpPage()
            case .about: AboutPage(updates: model.updates, whatsNew: model.whatsNew, loginItem: model.loginItem)
            }
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    let model: AppModel
    @Binding var page: Page

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                ZStack {
                    Hexagon().fill(Theme.mint.opacity(0.16))
                    Hexagon().stroke(Theme.mint, style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
                }
                .frame(width: 24, height: 24)
                Text("Sesame")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.primary)
            }
            .padding(.leading, 10)
            .padding(.top, 46)
            .padding(.bottom, 18)

            ForEach(Array(Page.groups.enumerated()), id: \.offset) { _, group in
                if let title = group.0 {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(Theme.tertiary)
                        .padding(.leading, 12)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                }
                ForEach(group.1) { item(for: $0) }
            }

            Spacer(minLength: 0)
            item(for: .help)
            item(for: .about)
            statusFooter.padding(.top, 10)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(width: 212)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.rail)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    private func item(for item: Page) -> some View {
        SidebarItem(page: item, isSelected: page == item, badge: badge(for: item)) { page = item }
    }

    private func badge(for item: Page) -> SidebarItem.Badge? {
        if item == .about, model.updates.availableVersion != nil || model.whatsNew.isUnseen { return .dot }
        if item == .activity, model.vault.isOpen, model.vault.contents.activity.failuresWhileAway > 0 {
            return .count(model.vault.contents.activity.failuresWhileAway)
        }
        return nil
    }

    private var statusFooter: some View {
        let status = model.unlockStatus
        return Button { page = .overview } label: {
            HStack(spacing: 10) {
                StatusDot(color: status.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Face unlock").font(.system(size: 10.5)).foregroundStyle(Theme.tertiary)
                    Text(status.short).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.primary)
                }
                Spacer(minLength: 0)
                if model.vault.isOpen {
                    Button { model.vault.close() } label: {
                        Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondary)
                    .help("Lock Sesame")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarItem: View {
    enum Badge: Equatable {
        case dot
        case count(Int)
    }

    let page: Page
    let isSelected: Bool
    let badge: Badge?
    let select: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: page.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.mint : Theme.secondary)
                    .frame(width: 20)
                Text(page.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected || isHovered ? Theme.primary : Theme.primary.opacity(0.8))
                Spacer(minLength: 0)
                switch badge {
                case .dot:
                    Circle().fill(Theme.sky).frame(width: 7, height: 7)
                case .count(let count):
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black.opacity(0.75))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.amber, in: Capsule())
                case nil:
                    EmptyView()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Theme.mint.opacity(0.14) : (isHovered ? Color.white.opacity(0.05) : .clear))
            )
            .overlay(alignment: .leading) {
                Capsule().fill(Theme.mint).frame(width: 3, height: isSelected ? 16 : 0).offset(x: -6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }
}

// MARK: - Locked

struct LockedPage: View {
    let model: AppModel
    @State private var confirmingStartOver = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Hexagon().fill((model.canStartOver ? Theme.amber : Theme.mint).opacity(0.1))
                Hexagon().stroke((model.canStartOver ? Theme.amber : Theme.mint).opacity(0.5), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                Image(systemName: model.canStartOver ? "key.slash" : "lock.fill")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(model.canStartOver ? Theme.amber : Theme.mint)
            }
            .frame(width: 84, height: 84)

            if model.canStartOver {
                VStack(spacing: 5) {
                    Text("Sesame can't open its saved data").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.primary)
                    Text("It was saved by a different build of Sesame, such as one built in Xcode, which keeps its key somewhere this one can't reach. Start over to set up your face and password again.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                }
                HStack(spacing: 10) {
                    Button("Try again") { Task { await model.openVault() } }
                        .controlSize(.large)
                    Button("Start over…") { confirmingStartOver = true }
                        .buttonStyle(FilledButtonStyle(color: Theme.amber))
                        .controlSize(.large)
                }
            } else {
                VStack(spacing: 5) {
                    Text("Sesame is locked").font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.primary)
                    Text(model.errorMessage ?? "Your faces and password are encrypted. Use Touch ID or your Mac password to open them.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(model.errorMessage == nil ? Theme.secondary : Theme.coral)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)
                }
                PrimaryButton(title: "Unlock", symbol: "touchid") { Task { await model.openVault() } }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line))
        .confirmationDialog("Start over?", isPresented: $confirmingStartOver) {
            Button("Delete and Start Over", role: .destructive) { Task { await model.startOver() } }
        } message: {
            Text("Sesame deletes the saved data it can't open: faces, saved password, history, and settings. Your Mac and its password aren't affected.")
        }
    }
}

// MARK: - Overview

struct OverviewPage: View {
    let model: AppModel
    let open: (Page) -> Void

    private var vault: Vault { model.vault }
    private var status: UnlockStatus { model.unlockStatus }

    var body: some View {
        hero

        if let error = vault.saveError {
            Banner(symbol: "externaldrive.badge.exclamationmark", tint: Theme.coral, title: "Sesame couldn't save your changes",
                   detail: "\(error) Recent changes may be lost when Sesame quits. Check that your disk isn't full.")
        }
        if vault.restoredFromBackup {
            Banner(symbol: "arrow.counterclockwise.circle.fill", tint: Theme.amber, title: "Restored from the last good copy",
                   detail: "Sesame's saved data was damaged, so it went back to the copy from the last time it opened. Recent changes may be missing.")
        }
        if !model.loginItem.isOn, vault.hasPassword {
            Banner(symbol: "power", tint: Theme.sky, title: "Open Sesame when you log in",
                   detail: model.loginItem.needsApproval
                       ? "Allow Sesame under Login Items in System Settings."
                       : "Face unlock only works while Sesame is running. Without this, a restart turns it off.") {
                if model.loginItem.needsApproval {
                    Button("Open Settings") { model.loginItem.openSystemSettings() }
                } else {
                    Button("Turn on") { model.loginItem.set(true) }
                        .buttonStyle(FilledButtonStyle(color: Theme.sky))
                }
            }
        }

        if model.whatsNew.isUnseen, let release = model.whatsNew.release {
            Banner(symbol: "sparkles", tint: Theme.mint, title: "Updated to Sesame \(release.version)",
                   detail: release.changes.first) {
                HStack(spacing: 8) {
                    Button("What's new") { open(.about) }
                        .buttonStyle(FilledButtonStyle(color: Theme.mint))
                    Button { model.whatsNew.markSeen() } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondary)
                    .help("Dismiss")
                }
            }
        }

        if let version = model.updates.availableVersion {
            Banner(symbol: "arrow.down.circle.fill", tint: Theme.sky, title: "Sesame \(version) is available",
                   detail: "Your faces, password, and permissions carry over.") {
                Button("Update") { model.updates.checkNow() }
                    .buttonStyle(FilledButtonStyle(color: Theme.sky))
            }
        }

        if case .setupNeeded = status {
            setup
        } else {
            stats
            week
            recent
        }
    }

    /// Unlocks and failed attempts for each of the last seven days.
    private var week: some View {
        let days = vault.contents.activity.daily(days: 7, endingAt: Date(), calendar: .current)
        let peak = max(days.map { $0.unlocks + $0.failures }.max() ?? 0, 1)
        let unlocks = days.map(\.unlocks).reduce(0, +)
        let failures = days.map(\.failures).reduce(0, +)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primary)
                Spacer()
                legend(Theme.mint, "\(unlocks) \(unlocks == 1 ? "unlock" : "unlocks")")
                legend(Theme.amber, "\(failures) failed").padding(.leading, 10)
            }
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        VStack(spacing: 2) {
                            Spacer(minLength: 0)
                            if day.failures > 0 {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(Theme.amber)
                                    .frame(height: max(4, 56 * CGFloat(day.failures) / CGFloat(peak)))
                            }
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(day.unlocks > 0 ? Theme.mint : Color.white.opacity(0.08))
                                .frame(height: day.unlocks > 0 ? max(4, 56 * CGFloat(day.unlocks) / CGFloat(peak)) : 3)
                        }
                        .frame(height: 62)
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10, weight: Calendar.current.isDateInToday(day.date) ? .bold : .regular))
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Theme.primary : Theme.tertiary)
                    }
                    .frame(maxWidth: 44)
                    .frame(maxWidth: .infinity)
                    .help("\(day.date.formatted(.dateTime.weekday(.wide))): \(day.unlocks) unlocked, \(day.failures) failed")
                }
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line))
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
        }
    }

    private var hero: some View {
        HStack(spacing: 18) {
            ScanMark(state: status == .ready ? .success : (status.color == Theme.coral ? .failure : .scanning))
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(status.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.primary)
                Text(status.detail).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if case .paused = status, vault.contents.passwordHealth.isOutdated {
                Button("Update password") { open(.password) }.tint(Theme.coral)
            } else if case .off = status {
                Button("Conditions") { open(.conditions) }
            } else if case .pausedByUser = status {
                Button("Turn back on") { model.pause(nil) }
                    .buttonStyle(FilledButtonStyle(color: Theme.amber))
            } else if status == .ready {
                PauseMenu(model: model)
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [status.color.opacity(0.16), status.color.opacity(0.03)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: Theme.radius + 2, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: Theme.radius + 2, style: .continuous).strokeBorder(status.color.opacity(0.28)))
    }

    private var setup: some View {
        let steps = model.setupSteps
        let done = steps.filter(\.isDone).count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(text: "Setup")
                Spacer()
                Text("\(done) of \(steps.count) done").font(.system(size: 11.5)).foregroundStyle(Theme.secondary).padding(.top, 8)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Theme.mint)
                        .frame(width: max(6, proxy.size.width * Double(done) / Double(max(steps.count, 1))))
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 4)
            .animation(.easeOut(duration: 0.3), value: done)
            Card {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { RowDivider() }
                    SettingRow(icon: step.symbol, tint: step.isDone ? Theme.mint : Theme.secondary, title: step.title, detail: step.detail) {
                        if step.isDone {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.mint)
                        } else {
                            HStack(spacing: 8) {
                                if let secondary = step.secondary {
                                    Button(secondary) { perform(step, secondary: true) }
                                }
                                Button(step.action) { perform(step, secondary: false) }
                                    .buttonStyle(FilledButtonStyle(color: Theme.mint))
                            }
                        }
                    }
                }
            }
        }
    }

    private func perform(_ step: SetupStep, secondary: Bool) {
        switch step.id {
        case "camera": Task { await model.permissions.askForCamera() }
        case "typing":
            switch (model.permissions.typing.state, secondary) {
            case (.needsRestart, true): model.permissions.openTypingSettings()
            case (.needsRestart, false): Permissions.restartSesame()
            default: model.permissions.askForTyping()
            }
        case "face": open(.faces)
        default: open(.password)
        }
    }

    private var stats: some View {
        let contents = vault.contents
        return HStack(spacing: 10) {
            StatTile(symbol: "person.crop.square.fill", value: "\(contents.profiles.filter(\.isActive).count)", label: "Active faces")
            StatTile(symbol: "checkmark.seal.fill", tint: Theme.sky, value: relative(contents.passwordHealth.lastUnlock) ?? "Not yet", label: "Last face unlock")
            StatTile(
                symbol: "exclamationmark.shield.fill",
                tint: contents.activity.failuresWhileAway > 0 ? Theme.amber : Theme.violet,
                value: "\(contents.activity.failuresWhileAway)", label: "Failed while away"
            )
            StatTile(symbol: "touchid", tint: Theme.coral, value: relative(model.trustEndsAt) ?? "Now", label: "Touch ID needed")
        }
    }

    private var recent: some View {
        let entries = Array(vault.contents.activity.entries.prefix(4))
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(text: "Recent activity")
                Spacer()
                Button("See all") { open(.activity) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.mint)
                    .padding(.top, 8)
            }
            Card {
                if entries.isEmpty {
                    SettingRow(icon: "clock", tint: Theme.secondary, title: "Nothing yet", detail: "Unlocks and failed attempts will show up here.")
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { RowDivider() }
                    ActivityRow(entry: entry)
                }
            }
        }
    }

    private func relative(_ date: Date?) -> String? {
        guard let date else { return nil }
        if abs(date.timeIntervalSinceNow) < 60 { return "Just now" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

// MARK: - Password

struct PasswordPage: View {
    let model: AppModel
    @State private var entry = ""
    @State private var message: String?
    @State private var messageIsError = false
    @State private var isSaving = false

    private var vault: Vault { model.vault }
    private var health: PasswordHealth { vault.contents.passwordHealth }

    var body: some View {
        if health.isOutdated {
            Banner(symbol: "exclamationmark.triangle.fill", tint: Theme.amber, title: "Your saved password looks out of date",
                   detail: "Face unlock is paused so Sesame doesn't cause failed logins. Save your new Mac password below.")
        }

        Card {
            SettingRow(
                icon: vault.hasPassword ? "key.fill" : "key",
                tint: vault.hasPassword ? (health.isOutdated ? Theme.amber : Theme.mint) : Theme.secondary,
                title: vault.hasPassword ? "Password saved" : "No password saved",
                detail: vault.hasPassword ? "Encrypted with AES-GCM on this Mac. It never leaves it." : "Sesame needs it to sign you in."
            )
            RowDivider(inset: 16)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SecureField(vault.hasPassword ? "New Mac password" : "Mac password", text: $entry)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.line))
                        .onSubmit(save)
                    Button(isSaving ? "Checking…" : (vault.hasPassword ? "Replace" : "Save"), action: save)
                        .buttonStyle(FilledButtonStyle(color: Theme.mint))
                        .controlSize(.large)
                        .disabled(entry.isEmpty || isSaving)
                }
                if let message {
                    Label(message, systemImage: messageIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(messageIsError ? Theme.coral : Theme.mint)
                }
            }
            .padding(16)
        }

        if vault.hasPassword {
            SectionHeader(text: "Health")
            HStack(spacing: 10) {
                StatTile(symbol: "checkmark.shield.fill", value: date(health.lastVerified) ?? "Not verified", label: "Last checked with macOS")
                StatTile(symbol: "faceid", tint: Theme.sky, value: date(health.lastUnlock) ?? "Not yet", label: "Last typed by Sesame")
            }
            Card {
                SettingRow(icon: "arrow.triangle.2.circlepath", tint: Theme.sky, title: "Check saved password", detail: "Asks macOS whether it still works. A wrong one counts as a failed login.") {
                    Button("Check now") { Task { await vault.recheckPassword() } }
                }
            }
        }

        SectionHeader(text: "Danger zone")
        Card(tint: Theme.coral) {
            SettingRow(icon: "trash.fill", tint: Theme.coral, title: "Erase everything", detail: "Deletes your faces, password, history, and settings from this Mac.") {
                Button("Erase…", role: .destructive) { Task { await model.eraseAll() } }
                    .tint(Theme.coral)
            }
        }
    }

    private func date(_ date: Date?) -> String? {
        date?.formatted(.dateTime.month(.abbreviated).day().hour().minute())
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
                message = "Saved and checked with macOS."
                messageIsError = false
            } catch {
                message = error.localizedDescription
                messageIsError = true
            }
        }
    }
}

// MARK: - Security

/// Wraps settings that need a fresh Touch ID before they can change.
struct ApprovalGate<Content: View>: View {
    let vault: Vault
    let reason: String
    @ViewBuilder let content: Content

    var body: some View {
        if !vault.hasRecentApproval {
            Banner(symbol: "lock.fill", tint: Theme.sky, title: "Locked to prevent changes", detail: "Authenticate to change how face unlock works.") {
                Button("Unlock") { Task { _ = await vault.requireApproval(reason) } }
                    .buttonStyle(FilledButtonStyle(color: Theme.sky))
            }
        }
        VStack(alignment: .leading, spacing: 14) { content }
            .disabled(!vault.hasRecentApproval)
            .opacity(vault.hasRecentApproval ? 1 : 0.5)
    }
}

struct SecurityPage: View {
    let model: AppModel

    private var vault: Vault { model.vault }

    private func binding<Value>(_ path: WritableKeyPath<SecuritySettings, Value>) -> Binding<Value> {
        Binding(
            get: { vault.contents.settings[keyPath: path] },
            set: { newValue in vault.update { $0.settings[keyPath: path] = newValue } }
        )
    }

    var body: some View {
        ApprovalGate(vault: vault, reason: "change Sesame's security settings") {
            SectionHeader(text: "Scanning")
            Card {
                SettingRow(icon: "arrow.left.and.right", tint: Theme.violet, title: "Head-turn check", detail: "Asks you to turn your head two random ways. A video of you can't know which, so this is what stops someone holding up a recording. A wrong turn counts as a failed attempt.") {
                    Switch(isOn: binding(\.usesTurnChallenge))
                }
                RowDivider()
                SettingRow(icon: "eye.fill", tint: Theme.sky, title: "Require attention", detail: "Only unlocks with both eyes open, facing the screen.") {
                    Switch(isOn: binding(\.requiresAttention))
                }
                RowDivider()
                SettingRow(icon: "eye.slash.fill", tint: Theme.violet, title: "Require a blink", detail: "Only a blink proves you're really there. When off, a natural head movement also counts.") {
                    Switch(isOn: binding(\.requiresBlink))
                }
                RowDivider()
                SettingRow(icon: "bolt.fill", tint: Theme.amber, title: "Scan as soon as the Mac locks", detail: "Faster, but may unlock again if you're still in view.") {
                    Switch(isOn: binding(\.scansWhenLocking))
                }
            }

            SectionHeader(text: "Scan again")
            Card {
                SettingRow(icon: "arrow.clockwise", tint: Theme.sky, title: "Retries on its own", detail: "Up to three more tries when it sees you but you haven't blinked, and one when it didn't see anyone.")
                RowDivider()
                SettingRow(icon: "cursorarrow.motionlines", tint: Theme.sky, title: "Move the pointer to scan again", detail: "Anywhere on screen, once those tries are used up. The keyboard can't be used: macOS hides key presses from every app at the lock screen.")
            }

            SectionHeader(text: "Trust")
            Card {
                SettingRow(icon: "touchid", tint: Theme.coral, title: "Ask for Touch ID every", detail: "Also after every restart.") {
                    Picker("", selection: binding(\.trustHours)) {
                        Text("24 hours").tag(24)
                        Text("48 hours").tag(48)
                        Text("7 days").tag(168)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                RowDivider()
                SettingRow(icon: "dial.medium.fill", title: "Match strictness", detail: "Strict needs a closer match, so it may ask you to try again more often.") {
                    Picker("", selection: binding(\.matchRule.acceptScore)) {
                        Text("Standard").tag(Float(0.48))
                        Text("Strict").tag(Float(0.55))
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }

            SectionHeader(text: "Feedback")
            Card {
                SettingRow(icon: "bell.badge.fill", tint: Theme.amber, title: "Alert me about failed attempts", detail: "A notification after you unlock, if someone else tried while you were away.") {
                    Switch(isOn: binding(\.alertsOnFailedAttempts))
                }
                RowDivider()
                SettingRow(icon: "speaker.wave.2.fill", tint: Theme.sky, title: "Play a sound when unlocked", detail: "A short chime when face unlock signs you in.") {
                    Switch(isOn: binding(\.playsUnlockSound))
                }
            }

            SectionHeader(text: "Always on")
            Card {
                SettingRow(icon: "hand.raised.fill", tint: Theme.secondary, title: "Pauses after 5 failed attempts", detail: "Until the Mac is unlocked another way.")
                RowDivider()
                SettingRow(icon: "video.slash.fill", tint: Theme.secondary, title: "Ignores virtual cameras", detail: "Only the built-in, Continuity, or a USB camera is used.")
            }
        }
    }
}

/// Allow, or Open Settings and Restart once macOS needs a fresh copy of Sesame.
struct PermissionButtons: View {
    let state: PermissionGate.State
    let allow: () -> Void
    let openSettings: () -> Void

    var body: some View {
        switch state {
        case .ready:
            EmptyView()
        case .needsPermission:
            Button("Allow", action: allow)
        case .needsRestart:
            HStack(spacing: 8) {
                Button("Open Settings", action: openSettings)
                Button("Restart") { Permissions.restartSesame() }
                    .buttonStyle(FilledButtonStyle(color: Theme.mint))
            }
        }
    }
}

// MARK: - Activity

struct ActivityRow: View {
    let entry: ActivityEntry

    var body: some View {
        SettingRow(icon: Self.symbol(entry.kind), tint: Self.tint(entry.kind), title: Self.title(entry.kind), detail: entry.note) {
            Text(entry.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(Theme.secondary)
        }
    }

    static func title(_ kind: ActivityEntry.Kind) -> String {
        switch kind {
        case .unlocked: return "Unlocked"
        case .stranger: return "Face not recognized"
        case .spoof: return "Possible spoof"
        case .paused: return "Face unlock paused"
        case .passwordProblem: return "Password problem"
        }
    }

    static func symbol(_ kind: ActivityEntry.Kind) -> String {
        switch kind {
        case .unlocked: return "lock.open.fill"
        case .stranger: return "person.fill.questionmark"
        case .spoof: return "exclamationmark.shield.fill"
        case .paused: return "pause.fill"
        case .passwordProblem: return "key.fill"
        }
    }

    static func tint(_ kind: ActivityEntry.Kind) -> Color {
        switch kind {
        case .unlocked: return Theme.mint
        case .stranger, .paused: return Theme.amber
        case .spoof, .passwordProblem: return Theme.coral
        }
    }
}

struct ActivityPage: View {
    let model: AppModel

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case unlocks = "Unlocks"
        case failed = "Failed"

        var id: Self { self }

        func includes(_ kind: ActivityEntry.Kind) -> Bool {
            switch self {
            case .all: return true
            case .unlocks: return kind == .unlocked
            case .failed: return kind != .unlocked
            }
        }
    }

    @State private var filter = Filter.all

    private var history: ActivityHistory { model.vault.contents.activity }

    private var days: [(Date, [ActivityEntry])] {
        let calendar = Calendar.current
        let shown = history.entries.filter { filter.includes($0.kind) }
        let grouped = Dictionary(grouping: shown) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        if history.failuresWhileAway > 0 {
            Banner(symbol: "exclamationmark.shield.fill", tint: Theme.amber,
                   title: "\(history.failuresWhileAway) failed \(history.failuresWhileAway == 1 ? "attempt" : "attempts") while you were away",
                   detail: "Someone else may have tried to unlock your Mac.")
        }

        let entries = history.entries
        HStack(spacing: 10) {
            StatTile(symbol: "lock.open.fill", value: "\(entries.filter { $0.kind == .unlocked }.count)", label: "Unlocks")
            StatTile(symbol: "person.fill.questionmark", tint: Theme.amber, value: "\(entries.filter { $0.kind == .stranger }.count)", label: "Not recognized")
            StatTile(symbol: "exclamationmark.shield.fill", tint: Theme.coral, value: "\(entries.filter { $0.kind == .spoof }.count)", label: "Possible spoofs")
        }

        if entries.isEmpty {
            Card {
                SettingRow(icon: "clock", tint: Theme.secondary, title: "No activity yet", detail: "Unlocks and failed attempts will show up here.")
            }
        } else {
            Picker("", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .padding(.top, 4)
            if days.isEmpty {
                Text("Nothing here for this filter.").font(.system(size: 12.5)).foregroundStyle(Theme.secondary).padding(.leading, 4)
            }
        }

        ForEach(days, id: \.0) { day, items in
            SectionHeader(text: dayTitle(day))
            Card {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { RowDivider() }
                    ActivityRow(entry: entry)
                }
            }
        }

        if !entries.isEmpty {
            Button("Clear history") { model.vault.update { $0.activity.clear() } }
                .padding(.top, 4)
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }
}

// MARK: - About

struct AboutPage: View {
    let updates: UpdateService
    let whatsNew: WhatsNew
    let loginItem: LoginItem

    private var updateDetail: String {
        if let error = updates.lastError { return "Last check failed: \(error)" }
        guard let checked = updates.lastChecked else { return "Updates are signed and verified before installing." }
        return "Last checked \(checked.formatted(.relative(presentation: .named)))."
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Hexagon().fill(LinearGradient(colors: [Theme.mint.opacity(0.35), Theme.mint.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                Hexagon().stroke(Theme.mint, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            }
            .frame(width: 72, height: 72)
            .padding(.bottom, 4)
            Text("Sesame").font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(Theme.primary)
            Text("Version \(UpdateService.currentVersion) · Face unlock for your Mac")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 10)

        if let release = whatsNew.release {
            SectionHeader(text: "What's new in \(release.version)")
            Card {
                ForEach(Array(release.changes.enumerated()), id: \.offset) { index, change in
                    if index > 0 { RowDivider(inset: 44) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.mint)
                            .frame(width: 16)
                        Text(change)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                RowDivider(inset: 16)
                Link(destination: URL(string: "https://github.com/sagarrokade006/sesame/releases")!) {
                    Label("Every release", systemImage: "arrow.up.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.mint)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .onAppear { whatsNew.markSeen() }
        }

        SectionHeader(text: "General")
        Card {
            SettingRow(icon: "power", tint: Theme.mint, title: "Open at login",
                       detail: loginItem.error ?? (loginItem.needsApproval
                           ? "Allow Sesame under Login Items in System Settings."
                           : "Face unlock only works while Sesame is running. It asks for Touch ID when it starts.")) {
                if loginItem.needsApproval {
                    Button("Open Settings") { loginItem.openSystemSettings() }
                } else {
                    Switch(isOn: Binding(get: { loginItem.isOn }, set: { loginItem.set($0) }))
                }
            }
        }

        if updates.isEnabled {
            SectionHeader(text: "Updates")
            Card {
                SettingRow(
                    icon: updates.availableVersion == nil ? "checkmark.seal.fill" : "arrow.down.circle.fill",
                    tint: updates.availableVersion == nil ? Theme.mint : Theme.sky,
                    title: updates.availableVersion.map { "Version \($0) is available" } ?? "Sesame is up to date",
                    detail: updateDetail
                ) {
                    if updates.availableVersion != nil {
                        Button("Update") { updates.checkNow() }.buttonStyle(FilledButtonStyle(color: Theme.mint))
                    } else {
                        Button("Check now") { updates.checkNow() }
                    }
                }
                RowDivider()
                SettingRow(icon: "clock.arrow.circlepath", tint: Theme.sky, title: "Check automatically", detail: "Once a day. You'll get a notification when there's a new version.") {
                    Switch(isOn: Binding(get: { updates.checksAutomatically }, set: { updates.checksAutomatically = $0 }))
                }
            }
        }

        SectionHeader(text: "Credits")
        Card {
            SettingRow(icon: "brain.head.profile", tint: Theme.violet, title: "Face recognition", detail: "SFace by OpenCV, Apache License 2.0")
            RowDivider()
            SettingRow(icon: "lock.doc.fill", tint: Theme.violet, title: "Everything stays on this Mac", detail: "Faces, password, and history live in one encrypted file.")
        }

        Banner(symbol: "info.circle.fill", tint: Theme.secondary, title: "A convenience, not Face ID",
               detail: "A webcam sees a flat image, and Sesame signs in by typing your saved password. Use Touch ID or your password when security matters most.")
            .padding(.top, 6)
    }
}

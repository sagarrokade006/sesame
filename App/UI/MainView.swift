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
    static let size = CGSize(width: 820, height: 640)

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
                .padding(.horizontal, 28)
                .padding(.top, 46)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
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
            case .conditions: ConditionsPage(model: model)
            case .activity: ActivityPage(model: model)
            case .help: HelpPage()
            case .about: AboutPage(updates: model.updates)
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
        let isSelected = page == item
        return Button { page = item } label: {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Theme.mint : Theme.secondary)
                    .frame(width: 20)
                Text(item.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Theme.primary : Theme.primary.opacity(0.8))
                Spacer(minLength: 0)
                if item == .activity, model.vault.isOpen, model.vault.contents.activity.failuresWhileAway > 0 {
                    Text("\(model.vault.contents.activity.failuresWhileAway)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black.opacity(0.75))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Theme.amber, in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Theme.mint.opacity(0.14) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

// MARK: - Locked

struct LockedPage: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Hexagon().fill(Theme.mint.opacity(0.1))
                Hexagon().stroke(Theme.mint.opacity(0.5), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                Image(systemName: "lock.fill").font(.system(size: 30, weight: .semibold)).foregroundStyle(Theme.mint)
            }
            .frame(width: 84, height: 84)

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
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line))
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

        if case .setupNeeded = status {
            setup
        } else {
            stats
            recent
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
            ProgressView(value: Double(done), total: Double(steps.count))
                .tint(Theme.mint)
                .padding(.horizontal, 4)
            Card {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    if index > 0 { RowDivider() }
                    SettingRow(icon: step.symbol, tint: step.isDone ? Theme.mint : Theme.secondary, title: step.title, detail: step.detail) {
                        if step.isDone {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 18)).foregroundStyle(Theme.mint)
                        } else {
                            Button(step.action) { perform(step) }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.mint)
                        }
                    }
                }
            }
        }
    }

    private func perform(_ step: SetupStep) {
        switch step.id {
        case "camera": Task { await model.requestCamera() }
        case "typing": model.requestTyping()
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
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.mint)
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
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.sky)
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
                SettingRow(icon: "arrow.left.and.right", tint: Theme.violet, title: "Turn challenge", detail: "Asks you to turn your head to a random side, which a video can't predict.") {
                    Switch(isOn: binding(\.usesTurnChallenge))
                }
                RowDivider()
                SettingRow(icon: "eye.fill", tint: Theme.sky, title: "Require attention", detail: "Only unlocks with your eyes open, facing the screen.") {
                    Switch(isOn: binding(\.requiresAttention))
                }
                RowDivider()
                SettingRow(icon: "bolt.fill", tint: Theme.amber, title: "Scan as soon as the Mac locks", detail: "Faster, but may unlock again if you're still in view.") {
                    Switch(isOn: binding(\.scansWhenLocking))
                }
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

            SectionHeader(text: "Always on")
            Card {
                SettingRow(icon: "hand.raised.fill", tint: Theme.secondary, title: "Pauses after 5 failed attempts", detail: "Until the Mac is unlocked another way.")
                RowDivider()
                SettingRow(icon: "video.slash.fill", tint: Theme.secondary, title: "Ignores virtual cameras", detail: "Only the built-in, Continuity, or a USB camera is used.")
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

    private var history: ActivityHistory { model.vault.contents.activity }

    private var days: [(Date, [ActivityEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: history.entries) { calendar.startOfDay(for: $0.date) }
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

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
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
            Text(version.isEmpty ? "Face unlock for your Mac" : "Version \(version) · Face unlock for your Mac")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .padding(.bottom, 10)

        if updates.isEnabled {
            SectionHeader(text: "Updates")
            Card {
                SettingRow(
                    icon: "arrow.down.circle.fill", tint: Theme.sky,
                    title: updates.availableVersion.map { "Version \($0) is available" } ?? "Sesame is up to date",
                    detail: updates.availableVersion == nil ? "Updates are signed and checked before installing." : nil
                ) {
                    if updates.availableVersion != nil {
                        Button("Update") { updates.checkNow() }.buttonStyle(.borderedProminent).tint(Theme.mint)
                    } else {
                        Button("Check now") { updates.checkNow() }
                    }
                }
                RowDivider()
                SettingRow(icon: "clock.arrow.circlepath", tint: Theme.sky, title: "Check automatically", detail: "Once a day.") {
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

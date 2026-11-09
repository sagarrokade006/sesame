import SesameCore
import SwiftUI

/// One answer to "will face unlock work right now?", shared by the sidebar, Overview, and Conditions.
enum UnlockStatus: Equatable {
    case locked
    case setupNeeded(remaining: Int)
    case paused(String)
    case off(String)
    case ready

    var title: String {
        switch self {
        case .locked: return "Sesame is locked"
        case .setupNeeded: return "Finish setting up"
        case .paused: return "Face unlock is paused"
        case .off: return "Face unlock is off here"
        case .ready: return "Face unlock is on"
        }
    }

    var detail: String {
        switch self {
        case .locked: return "Use Touch ID to open Sesame."
        case .setupNeeded(let remaining): return remaining == 1 ? "One step left before Sesame can unlock your Mac." : "\(remaining) steps left before Sesame can unlock your Mac."
        case .paused(let reason), .off(let reason): return reason
        case .ready: return "Sesame scans for you when your Mac wakes."
        }
    }

    var short: String {
        switch self {
        case .locked: return "Locked"
        case .setupNeeded: return "Setup needed"
        case .paused: return "Paused"
        case .off: return "Off here"
        case .ready: return "On"
        }
    }

    var color: Color {
        switch self {
        case .ready: return Theme.mint
        case .locked: return Theme.tertiary
        case .setupNeeded, .off: return Theme.amber
        case .paused: return Theme.coral
        }
    }
}

struct SetupStep: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let detail: String
    let isDone: Bool
    let action: String
    /// A quieter second button, such as Open Settings next to Restart.
    var secondary: String?
}

extension AppModel {
    var setupSteps: [SetupStep] {
        [
            SetupStep(id: "camera", symbol: "camera.fill", title: "Camera", detail: "Sees your face when your Mac wakes.", isDone: cameraAccess == .authorized, action: "Allow"),
            typingStep,
            SetupStep(id: "face", symbol: "person.crop.square.fill", title: "Your face", detail: "A quick scan, like setting up Face ID.", isDone: vault.contents.profiles.contains(where: \.isActive), action: "Add"),
            SetupStep(id: "password", symbol: "key.fill", title: "Mac password", detail: "Encrypted on this Mac and typed for you.", isDone: vault.hasPassword, action: "Add"),
        ]
    }

    private var typingStep: SetupStep {
        switch permissions.typing.state {
        case .ready:
            return SetupStep(id: "typing", symbol: "keyboard.fill", title: "Accessibility", detail: "Lets Sesame type your password at the lock screen.", isDone: true, action: "")
        case .needsPermission:
            return SetupStep(id: "typing", symbol: "keyboard.fill", title: "Accessibility", detail: "Lets Sesame type your password at the lock screen.", isDone: false, action: "Allow")
        case .needsRestart:
            return SetupStep(
                id: "typing", symbol: "keyboard.fill", title: "Accessibility",
                detail: "Turn Sesame on in System Settings, then restart it. macOS only applies this to a fresh copy of Sesame.",
                isDone: false, action: "Restart", secondary: "Open Settings"
            )
        }
    }

    var unlockStatus: UnlockStatus {
        guard vault.isOpen else { return .locked }
        let remaining = setupSteps.filter { !$0.isDone }.count
        if remaining > 0 { return .setupNeeded(remaining: remaining) }
        if !controller.isModelAvailable { return .paused("The face recognition model is missing from this build.") }
        if vault.contents.passwordHealth.isOutdated { return .paused("Your saved password looks out of date.") }
        let rules = vault.contents.settings.unlockRules
        if !rules.isEmpty, let unmet = Surroundings.shared.firstUnmet(rules) { return .off(unmet.explanation) }
        return .ready
    }

    /// When Touch ID will be needed again.
    var trustEndsAt: Date? {
        vault.trust.map { $0.grantedAt.addingTimeInterval(TimeInterval($0.hours) * 3600) }
    }
}

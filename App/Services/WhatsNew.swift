import Foundation
import Observation
import SesameCore

/// The installed version's entry from the bundled CHANGELOG.md, and whether to point it out after an update.
@MainActor
@Observable
final class WhatsNew {
    let version: String
    let release: Changelog.Release?
    /// True after an update until the person has seen the notes or dismissed the banner.
    private(set) var isUnseen: Bool

    private static let seenKey = "WhatsNewSeenVersion"

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        release = bundle.url(forResource: "CHANGELOG", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map(Changelog.init(markdown:))?
            .release(version)
        #if DEBUG
        if Snapshot.folder != nil {
            // Snapshots share the real app's preferences, and must neither read nor change what's been seen.
            isUnseen = false
            return
        }
        #endif
        let seen = defaults.string(forKey: Self.seenKey)
        if seen == nil, !Vault.hasSavedData {
            // A fresh install has nothing to compare against, so there's no "new" to announce.
            defaults.set(version, forKey: Self.seenKey)
            isUnseen = false
        } else {
            isUnseen = seen != version && release != nil
        }
    }

    func markSeen() {
        guard isUnseen else { return }
        isUnseen = false
        #if DEBUG
        if Snapshot.folder != nil { return }
        #endif
        UserDefaults.standard.set(version, forKey: Self.seenKey)
    }

    #if DEBUG
    func pretendUnseen() { isUnseen = release != nil }
    #endif
}

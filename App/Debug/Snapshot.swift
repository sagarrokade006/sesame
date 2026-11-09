#if DEBUG
import AppKit
import SesameCore
import SwiftUI

/// Renders each page with sample data to PNGs, then quits. Debug builds only:
/// SESAME_SNAPSHOT_DIR=/some/folder Sesame.app/Contents/MacOS/Sesame
/// Optional: SESAME_SNAPSHOT_PAGES=overview,faces  SESAME_SNAPSHOT_SCENARIO=new|locked  SESAME_SNAPSHOT_HEIGHT=900
@MainActor
enum Snapshot {
    static var folder: URL? {
        ProcessInfo.processInfo.environment["SESAME_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func run(in folder: URL) {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let environment = ProcessInfo.processInfo.environment
        let scenario = environment["SESAME_SNAPSHOT_SCENARIO"] ?? "ready"
        let watch = UnlockRules.Device(name: "Apple Watch", address: "00-00-00-00-00-01")
        Surroundings.shared.sample = .init(
            network: "Home",
            devices: [.init(name: "AirPods Pro", address: "00-00-00-00-00-02"), watch],
            connected: [watch.address]
        )
        let model = AppModel()
        model.pretendPermissions(granted: scenario != "new")
        switch scenario {
        case "new": model.vault.openForSnapshot(VaultContents())
        case "locked": break
        default: model.vault.openForSnapshot(sample)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let pages = environment["SESAME_SNAPSHOT_PAGES"]?
            .split(separator: ",").compactMap { name in Page.allCases.first { $0.rawValue.lowercased() == name.lowercased() } }
            ?? Page.allCases
        let size = CGSize(width: MainView.size.width, height: Double(environment["SESAME_SNAPSHOT_HEIGHT"] ?? "") ?? MainView.size.height)
        for page in pages {
            let view = MainView(model: model, page: page)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
            write(view, size: size, to: folder.appendingPathComponent("\(page.rawValue.lowercased()).png"))
        }
        exit(0)
    }

    private static func write(_ view: some View, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        // Lets SwiftUI finish onAppear updates and entry animations before capturing.
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        host.layoutSubtreeIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static var sample: VaultContents {
        let now = Date()
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        let vector = FaceVector([1, 0, 0])
        var contents = VaultContents()
        contents.profiles = [
            FaceProfile(name: "Sagar", vectors: Array(repeating: vector, count: 29), modelVersion: FaceReader.modelVersion, createdAt: ago(24 * 9)),
            FaceProfile(name: "Sagar Glasses", vectors: Array(repeating: vector, count: 26), modelVersion: FaceReader.modelVersion, createdAt: ago(24 * 3)),
            FaceProfile(name: "Guest", vectors: Array(repeating: vector, count: 24), modelVersion: FaceReader.modelVersion, createdAt: ago(24 * 2), isActive: false),
        ]
        contents.sealedPassword = Data([0])
        contents.passwordHealth.record(.accepted, at: ago(30))
        contents.passwordHealth.recordUnlock(at: ago(0.4))
        let events: [(Double, ActivityEntry.Kind, String?)] = [
            (0.4, .unlocked, "Sagar"), (2.1, .stranger, nil), (2.2, .stranger, nil), (3.5, .unlocked, "Sagar Glasses"),
            (26, .unlocked, "Sagar"), (27, .spoof, "A screen or card shape surrounded the face."), (29, .unlocked, "Sagar"),
            (52, .passwordProblem, "The Mac stayed locked after typing the password."), (53, .unlocked, "Sagar"),
        ]
        for (hours, kind, note) in events.reversed() {
            contents.activity.add(ActivityEntry(date: ago(hours), kind: kind, note: note))
        }
        contents.settings.unlockRules.trustedNetworks = ["Home", "Studio 5G"]
        contents.settings.unlockRules.device = watch
        contents.settings.unlockRules.hours = .init(start: 8 * 60, end: 23 * 60 + 30)
        return contents
    }

    private static let watch = UnlockRules.Device(name: "Apple Watch", address: "00-00-00-00-00-01")
}
#endif

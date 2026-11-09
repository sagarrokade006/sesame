import AppKit
import SesameCore
import SwiftUI

/// Bridges to the window server so one window can appear above the login screen.
///
/// These are private Apple symbols and may change in any macOS update. If they can't be found, Sesame still unlocks
/// and simply shows nothing at the lock screen.
private final class LockScreenLayer {
    private typealias ConnectionFunction = @convention(c) () -> Int32
    private typealias CreateSpace = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SetLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias MoveWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    private let connection: Int32
    private let space: Int32
    private let moveWindows: MoveWindows

    init?() {
        guard let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let connectionSymbol = dlsym(library, "SLSMainConnectionID"),
              let createSymbol = dlsym(library, "SLSSpaceCreate"),
              let levelSymbol = dlsym(library, "SLSSpaceSetAbsoluteLevel"),
              let showSymbol = dlsym(library, "SLSShowSpaces"),
              let moveSymbol = dlsym(library, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else { return nil }

        connection = unsafeBitCast(connectionSymbol, to: ConnectionFunction.self)()
        space = unsafeBitCast(createSymbol, to: CreateSpace.self)(connection, 1, 0)
        moveWindows = unsafeBitCast(moveSymbol, to: MoveWindows.self)
        _ = unsafeBitCast(levelSymbol, to: SetLevel.self)(connection, space, 400)
        _ = unsafeBitCast(showSymbol, to: ShowSpaces.self)(connection, [space] as CFArray)
    }

    func adopt(_ window: NSWindow) {
        _ = moveWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }
}

/// A small floating card, near the top of the screen, that shows what Sesame is doing while the Mac is locked.
@MainActor
final class LockBadge {
    enum Content: Equatable {
        case scanning
        case turn(TurnDirection, progress: Double)
        case success
        case failure
        case message(String, String)
    }

    @Observable
    @MainActor
    final class State {
        var content = Content.scanning
    }

    private let state = State()
    private let layer = LockScreenLayer()
    private var hideTask: Task<Void, Never>?

    private lazy var panel: NSPanel = {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .screenSaver
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: LockBadgeView(state: state))
        return panel
    }()

    func show(_ content: Content) {
        state.content = content
        hideTask?.cancel()
        if let screen = NSScreen.main {
            panel.setFrameOrigin(NSPoint(
                x: screen.frame.midX - panel.frame.width / 2,
                y: screen.frame.maxY - panel.frame.height - screen.frame.height * 0.08
            ))
        }
        panel.orderFrontRegardless()
        layer?.adopt(panel)

        switch content {
        case .success, .failure, .message:
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        case .scanning, .turn:
            break
        }
    }

    func hide() {
        hideTask?.cancel()
        panel.orderOut(nil)
    }
}

private struct LockBadgeView: View {
    let state: LockBadge.State

    var body: some View {
        Group {
            switch state.content {
            case .scanning:
                ScanMark(state: .scanning).frame(width: 64, height: 64).padding(24).background(card)
            case .success:
                ScanMark(state: .success).frame(width: 64, height: 64).padding(24).background(card)
            case .failure:
                ScanMark(state: .failure).frame(width: 64, height: 64).padding(24).background(card)
            case .turn(let direction, let progress):
                HStack(spacing: 14) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.18), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(Theme.mint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: direction == .left ? "arrow.left" : "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 36, height: 36)
                    Text(direction == .left ? "Slowly turn left" : "Slowly turn right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(card)
            case .message(let title, let detail):
                VStack(spacing: 3) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    Text(detail).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(card)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: state.content)
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(Theme.ink.opacity(0.92))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.12)))
    }
}

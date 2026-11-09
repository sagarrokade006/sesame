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

/// Lets the window sit against the very top of a notched display.
private final class EdgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Shows what Sesame is doing while the Mac is locked: growing out of the notch, or as a floating card on a Mac without one.
@MainActor
final class LockBadge {
    enum Content: Equatable {
        case scanning
        case turn(TurnDirection, progress: Double)
        case success
        case failure
        case message(String, String)

        var usesWidePanel: Bool {
            switch self {
            case .turn, .message: return true
            case .scanning, .success, .failure: return false
            }
        }
    }

    @Observable
    @MainActor
    final class State {
        var content = Content.scanning
        var isOpen = false
        /// The camera housing's size, or nil on a screen without a notch.
        var notchSize: CGSize?
    }

    private static let windowSize = CGSize(width: 460, height: 260)
    private static let closingDuration: Duration = .milliseconds(420)

    private let state = State()
    private let layer = LockScreenLayer()
    private var hideTask: Task<Void, Never>?

    private lazy var panel: NSPanel = {
        let panel = EdgePanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
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

    /// The notched built-in display if there is one, otherwise the main screen.
    private static var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    /// Where moving the pointer asks for another scan: the notch, or the top center of a screen without one.
    static var hotZone: CGRect? {
        guard let screen = targetScreen else { return nil }
        let size = notchSize(on: screen) ?? CGSize(width: 240, height: 30)
        let width = size.width + 40
        let height = size.height + 12
        return CGRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height)
    }

    static var retryHint: String {
        let hasNotch = targetScreen.flatMap(notchSize(on:)) != nil
        return "Press Space or move the pointer to the \(hasNotch ? "notch" : "top of the screen")."
    }

    private static func notchSize(on screen: NSScreen) -> CGSize? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea?.width,
              let right = screen.auxiliaryTopRightArea?.width
        else { return nil }
        return CGSize(width: screen.frame.width - left - right, height: screen.safeAreaInsets.top)
    }

    func show(_ content: Content) {
        hideTask?.cancel()
        guard let screen = Self.targetScreen else { return }

        let wasVisible = panel.isVisible && state.isOpen
        state.notchSize = Self.notchSize(on: screen)
        state.content = content

        let topGap = state.notchSize == nil ? screen.frame.height * 0.08 : 0
        panel.setFrameOrigin(NSPoint(
            x: screen.frame.midX - Self.windowSize.width / 2,
            y: screen.frame.maxY - Self.windowSize.height - topGap
        ))
        panel.orderFrontRegardless()
        layer?.adopt(panel)

        if !wasVisible {
            // Starts collapsed for one frame, so the panel visibly grows out of the notch.
            state.isOpen = false
            panel.displayIfNeeded()
            DispatchQueue.main.async { [state] in state.isOpen = true }
        }

        switch content {
        case .failure, .message:
            hide(after: .seconds(3))
        case .success:
            // Only a safety net. Normally the unlock result decides when this goes away.
            hide(after: .seconds(8))
        case .scanning, .turn:
            break
        }
    }

    func hide(after delay: Duration = .zero) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.state.isOpen = false
            try? await Task.sleep(for: Self.closingDuration)
            guard !Task.isCancelled else { return }
            self.panel.orderOut(nil)
        }
    }
}

/// The black shape: flush with the top edge, flaring into it at the sides, and rounded at the bottom.
private struct NotchBody: Shape {
    var flare: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(flare, bottomRadius) }
        set {
            flare = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, (rect.width - 2 * flare) / 2, rect.height - flare)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + flare, y: rect.minY + flare), control: CGPoint(x: rect.minX + flare, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + flare, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + flare + radius, y: rect.maxY), control: CGPoint(x: rect.minX + flare, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - flare - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - flare, y: rect.maxY - radius), control: CGPoint(x: rect.maxX - flare, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - flare, y: rect.minY + flare))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - flare, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct LockBadgeView: View {
    let state: LockBadge.State

    var body: some View {
        Group {
            if let notch = state.notchSize {
                notchPanel(notch)
            } else {
                floatingCard
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: state.isOpen)
        .animation(.spring(response: 0.34, dampingFraction: 0.8), value: state.content)
    }

    private func notchPanel(_ notch: CGSize) -> some View {
        let wide = state.content.usesWidePanel
        let openSize = wide
            ? CGSize(width: notch.width + 120, height: notch.height + 70)
            : CGSize(width: notch.width + 36, height: notch.height + 116)
        let size = state.isOpen ? openSize : notch
        let flare: CGFloat = state.isOpen ? 14 : 6
        let radius: CGFloat = state.isOpen ? (wide ? 30 : 44) : 10

        return ZStack(alignment: .top) {
            NotchBody(flare: flare, bottomRadius: radius)
                .fill(.black)
                .frame(width: size.width + flare * 2, height: size.height)
                .shadow(color: .black.opacity(state.isOpen ? 0.3 : 0), radius: 9)

            BadgeContent(content: state.content)
                .padding(.top, notch.height)
                .frame(width: openSize.width, height: openSize.height)
                .opacity(state.isOpen ? 1 : 0)
                .scaleEffect(state.isOpen ? 1 : 0.5, anchor: .top)
        }
    }

    private var floatingCard: some View {
        BadgeContent(content: state.content)
            .padding(state.content.usesWidePanel ? 18 : 24)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.ink.opacity(0.92))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(.white.opacity(0.12)))
            )
            .opacity(state.isOpen ? 1 : 0)
            .scaleEffect(state.isOpen ? 1 : 0.8)
    }
}

private struct BadgeContent: View {
    let content: LockBadge.Content

    var body: some View {
        switch content {
        case .scanning:
            ScanMark(state: .scanning).frame(width: 76, height: 76)
        case .success:
            ScanMark(state: .success).frame(width: 76, height: 76)
        case .failure:
            ScanMark(state: .failure).frame(width: 76, height: 76)
        case .turn(let direction, let progress):
            HStack(spacing: 12) {
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
        case .message(let title, let detail):
            VStack(spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 22)
        }
    }
}

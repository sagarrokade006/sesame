import AppKit
import SesameCore
import SwiftUI

/// Shows the face scan where you're already looking: growing out of the notch, right under the camera, like Face ID
/// setup on a phone. On a screen without a notch it's a card at the top center. It floats above every window, so the
/// scan stays visible even when Sesame's window is behind another app, and it never takes focus or clicks.
@MainActor
final class NotchScanner {
    static let shared = NotchScanner()

    @Observable
    @MainActor
    final class State {
        var enrollment: Enrollment?
        var isOpen = false
        var notchSize: CGSize?
    }

    private static let windowSize = CGSize(width: 420, height: 400)
    private let state = State()
    private var hideTask: Task<Void, Never>?
    private var completionWatch: Task<Void, Never>?

    private lazy var panel: NSPanel = {
        let panel = TopEdgePanel(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: NotchScannerView(state: state))
        return panel
    }()

    private static var targetScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private static func notchSize(on screen: NSScreen) -> CGSize? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea?.width,
              let right = screen.auxiliaryTopRightArea?.width
        else { return nil }
        return CGSize(width: screen.frame.width - left - right, height: screen.safeAreaInsets.top)
    }

    func show(_ enrollment: Enrollment) {
        hideTask?.cancel()
        guard let screen = Self.targetScreen else { return }
        state.enrollment = enrollment
        state.notchSize = Self.notchSize(on: screen)
        let topGap = state.notchSize == nil ? 40 : 0
        panel.setFrameOrigin(NSPoint(
            x: screen.frame.midX - Self.windowSize.width / 2,
            y: screen.frame.maxY - Self.windowSize.height - CGFloat(topGap)
        ))
        state.isOpen = false
        panel.orderFrontRegardless()
        // Opens a frame later, so the panel visibly grows out of the notch.
        DispatchQueue.main.async { [state] in state.isOpen = true }

        // Shows the checkmark briefly once the scan is done, then gets out of the way for naming the face.
        completionWatch?.cancel()
        completionWatch = Task { [weak self] in
            while !Task.isCancelled, enrollment.scan.stage != .complete {
                try? await Task.sleep(for: .milliseconds(150))
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled, self?.state.enrollment === enrollment else { return }
            self?.hide()
        }
    }

    func hide() {
        completionWatch?.cancel()
        hideTask?.cancel()
        state.isOpen = false
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled, let self else { return }
            self.panel.orderOut(nil)
            self.state.enrollment = nil
        }
    }
}

#if DEBUG
extension NotchScanner {
    /// For snapshots: the open panel under a typical notch.
    static func snapshot(_ enrollment: Enrollment, notch: Bool = true) -> some View {
        let state = State()
        state.enrollment = enrollment
        state.isOpen = true
        state.notchSize = notch ? CGSize(width: 200, height: 32) : nil
        return NotchScannerView(state: state).frame(width: windowSize.width, height: windowSize.height)
    }
}
#endif

/// Lets the panel sit against the very top of a notched display.
private final class TopEdgePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private struct NotchScannerView: View {
    let state: NotchScanner.State

    private let openWidth: CGFloat = 300
    private let openHeight: CGFloat = 300

    var body: some View {
        Group {
            if let enrollment = state.enrollment {
                if let notch = state.notchSize {
                    notchPanel(notch, enrollment: enrollment)
                } else {
                    floatingCard(enrollment)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.42, dampingFraction: 0.8), value: state.isOpen)
    }

    private func content(_ enrollment: Enrollment) -> some View {
        VStack(spacing: 14) {
            FaceScannerDial(scan: enrollment.scan, previewSize: 170, dialSize: 222) {
                CameraPreview(session: enrollment.camera.session)
            }
            Text(scannerPrompt(for: enrollment.scan.stage))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.2), value: enrollment.scan.stage)
        }
    }

    private func notchPanel(_ notch: CGSize, enrollment: Enrollment) -> some View {
        let size = state.isOpen ? CGSize(width: openWidth, height: notch.height + openHeight) : notch
        let flare: CGFloat = state.isOpen ? 14 : 6
        return ZStack(alignment: .top) {
            NotchBody(flare: flare, bottomRadius: state.isOpen ? 46 : 10)
                .fill(.black)
                .frame(width: size.width + flare * 2, height: size.height)
                .shadow(color: .black.opacity(state.isOpen ? 0.35 : 0), radius: 12)
            content(enrollment)
                .padding(.top, notch.height + 12)
                .opacity(state.isOpen ? 1 : 0)
                .scaleEffect(state.isOpen ? 1 : 0.4, anchor: .top)
        }
    }

    private func floatingCard(_ enrollment: Enrollment) -> some View {
        content(enrollment)
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Color.black.opacity(0.92))
                    .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white.opacity(0.12)))
            )
            .opacity(state.isOpen ? 1 : 0)
            .scaleEffect(state.isOpen ? 1 : 0.85, anchor: .top)
    }
}

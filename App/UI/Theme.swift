import SwiftUI

enum Theme {
    static let ink = Color(red: 0.07, green: 0.10, blue: 0.09)
    static let page = Color(red: 0.075, green: 0.10, blue: 0.092)
    static let rail = Color(red: 0.055, green: 0.075, blue: 0.07)
    static let card = Color.white.opacity(0.045)
    static let raised = Color.white.opacity(0.075)
    static let line = Color.white.opacity(0.08)
    static let primary = Color.white.opacity(0.93)
    static let secondary = Color.white.opacity(0.56)
    static let tertiary = Color.white.opacity(0.34)
    static let mint = Color(red: 0.18, green: 0.77, blue: 0.60)
    static let coral = Color(red: 0.94, green: 0.36, blue: 0.29)
    static let amber = Color(red: 0.96, green: 0.65, blue: 0.26)
    static let sky = Color(red: 0.36, green: 0.62, blue: 0.98)
    static let violet = Color(red: 0.62, green: 0.50, blue: 0.98)

    static let radius: CGFloat = 16
}

struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        for corner in 0..<6 {
            let angle = Double(corner) * .pi / 3 - .pi / 2
            let point = CGPoint(x: rect.midX + radius * cos(angle), y: rect.midY + radius * sin(angle))
            if corner == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

struct ScanMark: View {
    enum State: Equatable {
        case scanning
        case success
        case failure
    }

    let state: State

    private let outline = StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)

    var body: some View {
        ZStack {
            switch state {
            case .scanning:
                TimelineView(.animation) { context in
                    let time = context.date.timeIntervalSinceReferenceDate
                    let head = time.truncatingRemainder(dividingBy: 1.3) / 1.3
                    let tail = head + 0.28
                    ZStack {
                        Hexagon().stroke(Theme.mint.opacity(0.22), style: outline)
                        Hexagon().trim(from: head, to: min(tail, 1)).stroke(Theme.mint, style: outline)
                        if tail > 1 {
                            Hexagon().trim(from: 0, to: tail - 1).stroke(Theme.mint, style: outline)
                        }
                    }
                }
            case .success:
                ResolvedGem(style: .success)
            case .failure:
                ResolvedGem(style: .failure)
            }
        }
        .padding(2)
        .aspectRatio(1, contentMode: .fit)
    }
}

/// One of the six triangles running from the hexagon's center to two neighboring corners.
private struct HexagonFacet: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        func corner(_ number: Int) -> CGPoint {
            let angle = Double(number) * .pi / 3 - .pi / 2
            return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
        var path = Path()
        path.move(to: center)
        path.addLine(to: corner(index))
        path.addLine(to: corner(index + 1))
        path.closeSubpath()
        return path
    }
}

private struct CheckStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.29, y: rect.minY + rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.67))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.35))
        return path
    }
}

private struct CrossStroke: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.65, y: rect.minY + rect.height * 0.65))
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.65, y: rect.minY + rect.height * 0.35))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY + rect.height * 0.65))
        return path
    }
}

/// A cut-gem hexagon that lands with a pop, then draws its symbol in. Success ripples outward; failure shakes.
private struct ResolvedGem: View {
    enum Style {
        case success
        case failure

        /// Lightest at the top left, as if lit from above.
        var facets: [Color] {
            switch self {
            case .success:
                return [0x8DEBD0, 0x5FDDB8, 0x2EC49A, 0x1FA582, 0x28B38C, 0x56D6B0].map(Self.color)
            case .failure:
                return [0xFF9C8C, 0xFB7766, 0xF0503F, 0xC93A2D, 0xDD4638, 0xF56F5E].map(Self.color)
            }
        }

        var symbolColor: Color {
            self == .success ? Color(red: 0.03, green: 0.20, blue: 0.15) : .white
        }

        private static func color(_ hex: Int) -> Color {
            Color(
                red: Double((hex >> 16) & 0xFF) / 255,
                green: Double((hex >> 8) & 0xFF) / 255,
                blue: Double(hex & 0xFF) / 255
            )
        }
    }

    let style: Style

    @State private var hasLanded = false
    @State private var symbolProgress = 0.0
    @State private var rippleProgress = 0.0
    @State private var shakeOffset = 0.0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let symbolStyle = StrokeStyle(lineWidth: width * 0.1, lineCap: .round, lineJoin: .round)

            ZStack {
                if style == .success {
                    Hexagon()
                        .stroke(style.facets[2], lineWidth: max(1.5, width * 0.035))
                        .scaleEffect(1 + rippleProgress * 0.42)
                        .opacity((1 - rippleProgress) * 0.8)
                }

                ZStack {
                    ForEach(0..<6, id: \.self) { index in
                        HexagonFacet(index: index).fill(style.facets[index])
                    }
                    Hexagon()
                        .stroke(.white.opacity(0.28), lineWidth: max(0.75, width * 0.012))
                        .scaleEffect(0.78)

                    Group {
                        if style == .success {
                            CheckStroke().trim(from: 0, to: symbolProgress).stroke(style.symbolColor, style: symbolStyle)
                        } else {
                            CrossStroke().trim(from: 0, to: symbolProgress).stroke(style.symbolColor, style: symbolStyle)
                        }
                    }
                }
                .scaleEffect(hasLanded ? 1 : 0.55)
                .opacity(hasLanded ? 1 : 0)
                .offset(x: shakeOffset * width)
                .shadow(color: style.facets[2].opacity(0.45), radius: width * 0.12)
            }
            .frame(width: width, height: proxy.size.height)
        }
        .onAppear(perform: play)
    }

    private func play() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.6)) { hasLanded = true }
        withAnimation(.easeOut(duration: 0.28).delay(0.14)) { symbolProgress = 1 }
        switch style {
        case .success:
            withAnimation(.easeOut(duration: 0.7).delay(0.1)) { rippleProgress = 1 }
        case .failure:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(180))
                for offset in [-0.07, 0.06, -0.04, 0.025, 0.0] {
                    withAnimation(.easeInOut(duration: 0.06)) { shakeOffset = offset }
                    try? await Task.sleep(for: .milliseconds(60))
                }
            }
        }
    }
}

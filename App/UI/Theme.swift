import SwiftUI

enum Theme {
    static let ink = Color(red: 0.07, green: 0.10, blue: 0.09)
    static let page = Color(red: 0.09, green: 0.125, blue: 0.11)
    static let rail = Color(red: 0.07, green: 0.10, blue: 0.09)
    static let card = Color.white.opacity(0.06)
    static let line = Color.white.opacity(0.09)
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.55)
    static let mint = Color(red: 0.18, green: 0.77, blue: 0.60)
    static let coral = Color(red: 0.94, green: 0.36, blue: 0.29)
    static let amber = Color(red: 0.96, green: 0.65, blue: 0.26)
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
                filled(Theme.mint, symbol: "checkmark", symbolColor: .black)
            case .failure:
                filled(Theme.coral, symbol: "xmark", symbolColor: .white)
            }
        }
        .padding(2)
        .aspectRatio(1, contentMode: .fit)
    }

    private func filled(_ color: Color, symbol: String, symbolColor: Color) -> some View {
        GeometryReader { proxy in
            ZStack {
                Hexagon().fill(color)
                Hexagon().stroke(color, style: outline)
                Image(systemName: symbol)
                    .font(.system(size: proxy.size.width * 0.36, weight: .heavy))
                    .foregroundStyle(symbolColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct Panel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
    }
}

struct PanelRow<Trailing: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13)).foregroundStyle(Theme.primary)
                if let detail {
                    Text(detail).font(.system(size: 11)).foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct PanelDivider: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, 14)
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.secondary)
            .padding(.leading, 4)
    }
}

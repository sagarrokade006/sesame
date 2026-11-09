import SwiftUI

/// Big title and a one-line explanation at the top of every page.
struct PageHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .padding(.bottom, 6)
    }
}

struct Card<Content: View>: View {
    var tint: Color?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder((tint ?? .white).opacity(tint == nil ? 0.08 : 0.35))
            )
    }
}

/// A small rounded square holding a symbol, like the icons in System Settings.
struct IconBadge: View {
    let symbol: String
    var tint: Color = Theme.mint
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.opacity(0.18))
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.47, weight: .semibold))
                    .foregroundStyle(tint)
            )
            .frame(width: size, height: size)
    }
}

struct SettingRow<Trailing: View>: View {
    var icon: String?
    var tint: Color = Theme.mint
    let title: String
    var detail: String?
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            if let icon { IconBadge(symbol: icon, tint: tint) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.primary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 54)
    }
}

extension SettingRow where Trailing == EmptyView {
    init(icon: String? = nil, tint: Color = Theme.mint, title: String, detail: String? = nil) {
        self.init(icon: icon, tint: tint, title: title, detail: detail) { EmptyView() }
    }
}

struct RowDivider: View {
    var inset: CGFloat = 58

    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, inset)
    }
}

struct SectionHeader: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.tertiary)
            .padding(.leading, 4)
            .padding(.top, 8)
    }
}

/// A mint switch with no label, which every setting row uses. Drawn by hand so it looks the same whether or not the
/// window is in front, and in snapshots.
struct Switch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(SesameSwitchStyle())
    }
}

struct SesameSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { configuration.isOn.toggle() }
        } label: {
            Capsule()
                .fill(configuration.isOn ? Theme.mint : Color.white.opacity(0.16))
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                        .padding(2)
                }
                .frame(width: 34, height: 20)
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// A filled, rounded button for the main action in a row. Drawn by hand for the same reason as `SesameSwitchStyle`.
struct FilledButtonStyle: ButtonStyle {
    var color: Color = Theme.mint
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(red: 0.03, green: 0.12, blue: 0.10))
            .padding(.horizontal, controlSize == .large ? 16 : 12)
            .frame(height: controlSize == .large ? 32 : 26)
            .background(color.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct StatTile: View {
    let symbol: String
    var tint: Color = Theme.mint
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            IconBadge(symbol: symbol, tint: tint, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line))
    }
}

/// A colored strip that explains a state, with an optional action.
struct Banner<Action: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    var detail: String?
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primary)
                if let detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            action
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.3)))
    }
}

extension Banner where Action == EmptyView {
    init(symbol: String, tint: Color, title: String, detail: String? = nil) {
        self.init(symbol: symbol, tint: tint, title: title, detail: detail) { EmptyView() }
    }
}

struct StatusDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .background(Circle().fill(color.opacity(0.35)).frame(width: 13, height: 13))
    }
}

struct PrimaryButton: View {
    let title: String
    var symbol: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let symbol { Image(systemName: symbol) }
            }
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 6)
        }
        .buttonStyle(FilledButtonStyle(color: Theme.mint))
        .controlSize(.large)
    }
}

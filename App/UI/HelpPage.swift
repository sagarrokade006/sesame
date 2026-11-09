import SwiftUI

struct HelpPage: View {
    private struct Topic: Identifiable {
        let id = UUID()
        let question: String
        let answer: String
    }

    private let setup = [
        Topic(question: "How do I set up Sesame?", answer: "On Overview, allow Camera and Accessibility. Then add your face on Faces and save your Mac password on Password."),
        Topic(question: "How do I add my face?", answer: "Go to Faces and choose Add a face. Center your face, hold still, then move your head slowly in a circle until the ring fills. Add another profile if you often wear glasses."),
        Topic(question: "Why does Sesame need my password?", answer: "macOS has no way for an app to approve a login, so Sesame types your password for you once it recognizes you. It's encrypted on this Mac and never leaves it."),
    ]

    private let unlocking = [
        Topic(question: "When does Sesame scan?", answer: "When your Mac wakes: opening the lid, waking the display, or a screen saver ending."),
        Topic(question: "I locked my Mac and the screen stayed on", answer: "Sesame doesn't scan right away, so it can't unlock behind you as you walk off. Press Space or move the pointer to the notch when you're ready. To scan immediately instead, turn on \"Scan as soon as the Mac locks\" in Security."),
        Topic(question: "The first scan failed. What now?", answer: "Sesame tries once more by itself. After that, press Space or move the pointer to the notch to scan again. You can always type your password as usual."),
        Topic(question: "Why does it ask me to blink or move?", answer: "Sesame needs proof you're a real person and not a photo, so it watches for a natural blink or a small head movement."),
    ]

    private let trouble = [
        Topic(question: "\"Sesame paused: too many attempts\"", answer: "After 5 failed attempts, face unlock stops until you unlock with your password or Touch ID."),
        Topic(question: "\"Your saved password looks out of date\"", answer: "You probably changed your Mac password. Save the new one on the Password page."),
        Topic(question: "It stopped working after a day or two", answer: "For safety, Sesame asks for Touch ID or your password every 48 hours and after every restart. Open Sesame and choose Unlock. You can change this in Security."),
        Topic(question: "Accessibility is on, but Sesame doesn't see it", answer: "macOS can keep an old permission after an app is updated. In System Settings, open Privacy & Security, then Accessibility. Select Sesame, remove it with the minus button, then choose Allow in Sesame again."),
        Topic(question: "Space doesn't start a scan", answer: "macOS may be blocking keyboard access. Allow Sesame under Privacy & Security, or move the pointer to the notch instead."),
        Topic(question: "It doesn't recognize me", answer: "Face the screen in good light with your eyes open. If your look has changed, add another face on the Faces page."),
    ]

    var body: some View {
        section("Getting started", setup)
        section("Unlocking", unlocking)
        section("Troubleshooting", trouble)

        Text("Sesame is a convenience tool and isn't as secure as Face ID or Touch ID. Someone with a very convincing video or mask may be able to fool it.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondary)
    }

    private func section(_ title: String, _ topics: [Topic]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title)
            Panel {
                ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                    if index > 0 { PanelDivider() }
                    TopicRow(question: topic.question, answer: topic.answer)
                }
            }
        }
    }
}

private struct TopicRow: View {
    let question: String
    let answer: String
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) { isOpen.toggle() }
            } label: {
                HStack {
                    Text(question)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(answer)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

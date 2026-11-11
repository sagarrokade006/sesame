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
        Topic(question: "I locked my Mac and the screen stayed on", answer: "Sesame doesn't scan right away, so it can't unlock behind you as you walk off. Move the pointer or trackpad when you're ready. To scan immediately instead, turn on \"Scan as soon as the Mac locks\" in Security."),
        Topic(question: "The first scan failed. What now?", answer: "Sesame tries again by itself: up to three times when it sees you but you haven't blinked, once when it didn't see anyone. After that, move the pointer or trackpad to scan again. You can always type your password as usual."),
        Topic(question: "How do I turn face unlock off for a while?", answer: "Choose Pause in Sesame's menu bar panel or on Overview: for 1 hour, until tomorrow, or until you turn it back on. Meanwhile your Mac unlocks with your password or Touch ID."),
        Topic(question: "How can I check that it recognizes me?", answer: "On Faces, choose Test. Sesame runs the same checks as the lock screen and shows how well you match and whether it saw you blink, without typing anything or locking your Mac."),
        Topic(question: "Why does it ask me to turn my head?", answer: "It's the check a video of you can't pass. Sesame picks two directions at random when the scan starts, so a recording can't know them in advance. Turn slowly the way the arrow shows, look back at the screen, then turn the second way. A turn the wrong way counts as a failed attempt. You can switch it off in Security, but then a video of you could unlock your Mac."),
        Topic(question: "Why does it ask me to blink or move?", answer: "Sesame needs proof you're a real person and not a photo, so it watches for a natural blink or a small head movement, seen while your face is clearly visible. To accept only a blink, turn on Require a blink in Security."),
    ]

    private let trouble = [
        Topic(question: "\"Sesame paused: too many attempts\"", answer: "After 5 failed attempts, face unlock stops until you unlock with your password or Touch ID."),
        Topic(question: "\"Your saved password looks out of date\"", answer: "You probably changed your Mac password. Save the new one on the Password page."),
        Topic(question: "It stopped working after I restarted my Mac", answer: "Sesame has to be running, and needs Touch ID once after every restart. Turn on Open at login in About, and approve the Touch ID prompt Sesame shows when it starts."),
        Topic(question: "\"It's too dark to see you\"", answer: "The camera couldn't make out a face because the room is dark. Turn on a light or face a window, or enter your password."),
        Topic(question: "\"Camera isn't responding\"", answer: "Another app may be using the camera, or it was unplugged. Sesame tries once more, then stops so it never gets stuck. Close the other app, or enter your password."),
        Topic(question: "It stopped working after a day or two", answer: "For safety, Sesame asks for Touch ID or your password every 48 hours and after every restart. Open Sesame and choose Unlock. You can change this in Security."),
        Topic(question: "Accessibility is on, but Sesame doesn't see it", answer: "macOS can keep an old permission after an app is updated. In System Settings, open Privacy & Security, then Accessibility. Select Sesame, remove it with the minus button, then choose Allow in Sesame again."),
        Topic(question: "Pressing a key doesn't start a scan", answer: "At the lock screen macOS hides every key press from apps, to protect your password, so Sesame can't see them. Move the pointer or trackpad instead."),
        Topic(question: "\"Sesame's key is missing\"", answer: "Sesame's data was saved by a different build, such as one built in Xcode, and this one can't reach its key. Choose Start over on the locked screen and set up your face and password again. Releases from GitHub always share one key, so updating doesn't cause this."),
        Topic(question: "It recognizes me but the Mac stays locked", answer: "macOS stops an app from typing if its Accessibility permission changed while it was running, and keeps blocking it until the app restarts. Sesame shows Restart Sesame when this happens. Quit Sesame from the menu bar and open it again."),
        Topic(question: "It doesn't recognize me", answer: "Face the screen in good light with your eyes open. If your look has changed, add another face on the Faces page."),
    ]

    @State private var search = ""

    private func matching(_ topics: [Topic]) -> [Topic] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return topics }
        return topics.filter { $0.question.localizedCaseInsensitiveContains(query) || $0.answer.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiary)
            TextField("Search help", text: $search).textFieldStyle(.plain).font(.system(size: 13))
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.line))

        section("Getting started", symbol: "sparkles", tint: Theme.mint, matching(setup))
        section("Unlocking", symbol: "lock.open.fill", tint: Theme.sky, matching(unlocking))
        section("Troubleshooting", symbol: "wrench.and.screwdriver.fill", tint: Theme.amber, matching(trouble))

        if [setup, unlocking, trouble].allSatisfy({ matching($0).isEmpty }) {
            Text("No answers match \u{201C}\(search)\u{201D}.").font(.system(size: 12.5)).foregroundStyle(Theme.secondary).padding(.leading, 4)
        }

        Banner(symbol: "info.circle.fill", tint: Theme.secondary, title: "A convenience, not Face ID",
               detail: "Someone with a very convincing video or mask may be able to fool a webcam.")
            .padding(.top, 6)
    }

    @ViewBuilder
    private func section(_ title: String, symbol: String, tint: Color, _ topics: [Topic]) -> some View {
        if !topics.isEmpty {
            HStack(spacing: 8) {
                IconBadge(symbol: symbol, tint: tint, size: 22)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.primary)
            }
            .padding(.top, 8)
            Card {
                ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                    if index > 0 { RowDivider(inset: 16) }
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
                        .font(.system(size: 13, weight: .medium))
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

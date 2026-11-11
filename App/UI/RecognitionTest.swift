import Observation
import SesameCore
import SwiftUI

/// Runs the same checks as the lock screen, inside the app, without typing anything. Shows why a scan passes or
/// doesn't: whether a face is found, how well it matches, and whether proof of life was seen.
@MainActor
@Observable
final class RecognitionTest {
    enum Result: Equatable {
        case passed(name: String, seconds: Double)
        case noProof
        case noFace
        case tooDark
        case stranger
        case spoof
        case wrongTurn
        case cameraSilent
    }

    private(set) var result: Result?
    private(set) var faceVisible = false
    private(set) var matchedName: String?
    /// 0 to 1, the best match on the latest frame.
    private(set) var score: Float?
    private(set) var isAttentive = false
    private(set) var isWaitingForProof = false
    /// The current head-turn step, when the check is on.
    private(set) var challenge: TurnChallenge?

    let requiresAttention: Bool
    let requiresBlink: Bool
    let unlockScore: Float
    let usesChallenge: Bool

    @ObservationIgnored let camera = CameraFeed()
    @ObservationIgnored private let reader = FaceReader()
    @ObservationIgnored private let profiles: [FaceProfile]
    @ObservationIgnored private let matchRule: MatchRule
    @ObservationIgnored private var attempt: UnlockAttempt
    @ObservationIgnored private var darkness = DarknessJudge()
    @ObservationIgnored private var startedAt: TimeInterval = 0
    @ObservationIgnored private var sawFrame = false
    @ObservationIgnored private var timeout: Task<Void, Never>?
    @ObservationIgnored private let rules: UnlockAttempt.Rules

    init(contents: VaultContents) {
        profiles = contents.profiles
        matchRule = contents.settings.matchRule
        unlockScore = contents.settings.matchRule.unlockScore
        requiresAttention = contents.settings.requiresAttention
        requiresBlink = contents.settings.requiresBlink
        usesChallenge = contents.settings.usesTurnChallenge
        var rules = UnlockAttempt.Rules()
        rules.requiresAttention = contents.settings.requiresAttention
        rules.requiresBlink = contents.settings.requiresBlink
        // Longer than the lock screen's, to leave time to read what's happening.
        rules.duration = 12
        self.rules = rules
        attempt = UnlockAttempt(rules: rules, startedAt: 0)
    }

    func start() {
        result = nil
        faceVisible = false
        matchedName = nil
        score = nil
        isAttentive = false
        isWaitingForProof = false
        sawFrame = false
        darkness = DarknessJudge()
        startedAt = ProcessInfo.processInfo.systemUptime
        var generator = SystemRandomNumberGenerator()
        attempt = UnlockAttempt(rules: rules, challenge: usesChallenge ? .random(steps: 2, using: &generator) : nil, startedAt: startedAt)
        challenge = attempt.challenge

        let reader = self.reader
        camera.start { [weak self] pixels, time in
            let capture = reader.read(pixels, at: time)
            let brightness = capture == nil ? FaceReader.brightness(of: pixels) : nil
            Task { @MainActor in self?.receive(capture, brightness: brightness, at: time) }
        }
        // Ends the test even if the camera never delivers a frame.
        timeout?.cancel()
        timeout = Task { [weak self, duration = rules.duration] in
            try? await Task.sleep(for: .seconds(duration + 2))
            guard !Task.isCancelled, let self, self.result == nil else { return }
            self.finish(self.sawFrame ? .noFace : .cameraSilent)
        }
    }

    func stop() {
        timeout?.cancel()
        camera.stop()
    }

    private func finish(_ result: Result) {
        guard self.result == nil else { return }
        self.result = result
        stop()
    }

    private func receive(_ capture: FaceCapture?, brightness: Double?, at time: TimeInterval) {
        guard result == nil else { return }
        sawFrame = true
        let outcome: UnlockAttempt.Outcome
        if let capture {
            let best = matchRule.bestScore(for: capture.vector, among: profiles, modelVersion: FaceReader.modelVersion)
            let verdict = matchRule.verdict(for: capture.vector, among: profiles, modelVersion: FaceReader.modelVersion)
            outcome = attempt.observe(capture.reading, verdict: verdict)
            faceVisible = true
            score = best?.score
            if case .owner(let name) = verdict { matchedName = name } else { matchedName = nil }
            isAttentive = capture.reading.isAttentive()
        } else {
            outcome = attempt.observeNoFace(at: time)
            if let brightness { darkness.observe(brightness: brightness) }
            faceVisible = false
            score = nil
            matchedName = nil
            isAttentive = false
        }
        isWaitingForProof = attempt.isWaitingForProof
        challenge = attempt.challenge

        switch outcome {
        case .keepWatching: break
        case .unlock(let name): finish(.passed(name: name, seconds: time - startedAt))
        case .stranger: finish(.stranger)
        case .spoof: finish(.spoof)
        case .wrongTurn: finish(.wrongTurn)
        case .expired: finish(attempt.sawOwner ? .noProof : (darkness.isTooDark ? .tooDark : .noFace))
        }
    }

    #if DEBUG
    /// For snapshots: a test partway through, recognized and waiting for a blink.
    func pretendWaitingForProof() {
        faceVisible = true
        matchedName = profiles.first?.name
        score = 0.86
        isAttentive = true
        isWaitingForProof = true
        var steps = TurnChallenge(directions: [.left, .right])
        steps.observe(yaw: 0)
        steps.observe(yaw: 0.3)
        challenge = steps
    }
    #endif
}

struct RecognitionTestPanel: View {
    let test: RecognitionTest
    let done: () -> Void

    var body: some View {
        Card {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 22) {
                    CameraPreview(session: test.camera.session)
                        .scaleEffect(x: -1, y: 1)
                        .frame(width: 168, height: 168)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(ringColor, lineWidth: 3))
                        .background(Circle().fill(.black))

                    VStack(alignment: .leading, spacing: 12) {
                        check("Face found", detail: test.faceVisible ? nil : "Look at the camera.", isDone: test.faceVisible)
                        check(matchTitle, detail: matchDetail, isDone: test.matchedName != nil)
                        if test.requiresAttention {
                            check("Both eyes open, facing the screen",
                                  detail: test.faceVisible && !test.isAttentive ? "Open both eyes and look at the screen." : nil,
                                  isDone: test.isAttentive)
                        }
                        if let challenge = test.challenge {
                            check(turnTitle(challenge), detail: turnDetail(challenge), isDone: challenge.isComplete)
                        }
                        check(test.requiresBlink ? "Blinked" : "Blinked or moved", detail: proofDetail, isDone: isPassed)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }

                if let result = test.result {
                    Banner(symbol: symbol(for: result), tint: tint(for: result), title: title(for: result), detail: detail(for: result))
                }

                HStack {
                    Text("Nothing is typed and nothing is saved.").font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                    Spacer()
                    if test.result != nil {
                        Button("Test again") { test.start() }
                    }
                    Button(test.result == nil ? "Cancel" : "Done", action: done)
                        .buttonStyle(FilledButtonStyle(color: Theme.mint))
                }
            }
            .padding(20)
        }
    }

    private func turnTitle(_ challenge: TurnChallenge) -> String {
        if challenge.isComplete { return "Turned both ways asked" }
        return "Turn \(challenge.direction == .left ? "left" : "right") (\(challenge.step + 1) of \(challenge.stepCount))"
    }

    private func turnDetail(_ challenge: TurnChallenge) -> String? {
        guard !challenge.isComplete, test.result == nil else { return nil }
        return challenge.step == 0 ? "Slowly, then look back at the screen." : "Look back at the screen first, then turn."
    }

    private var isPassed: Bool {
        if case .passed = test.result { return true }
        return false
    }

    private var ringColor: Color {
        if isPassed { return Theme.mint }
        if test.result != nil { return Theme.amber }
        return test.matchedName != nil ? Theme.mint.opacity(0.6) : Color.white.opacity(0.15)
    }

    private var matchTitle: String {
        test.matchedName.map { "Matches \($0)" } ?? "Matches a saved face"
    }

    private var matchDetail: String? {
        guard let score = test.score else { return nil }
        let percent = Int((max(0, min(1, score)) * 100).rounded())
        let needed = Int((test.unlockScore * 100).rounded())
        return test.matchedName != nil ? "\(percent)% match (needs \(needed)%)." : "\(percent)% match, below the \(needed)% needed."
    }

    private var proofDetail: String? {
        guard !isPassed, test.isWaitingForProof else { return nil }
        return test.requiresBlink ? "Blink now." : "Blink, or move your head a little."
    }

    private func check(_ title: String, detail: String?, isDone: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(isDone ? Theme.mint : Theme.tertiary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(isDone ? Theme.primary : Theme.secondary)
                if let detail {
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: isDone)
    }

    private func symbol(for result: RecognitionTest.Result) -> String {
        switch result {
        case .passed: return "checkmark.circle.fill"
        case .tooDark: return "moon.fill"
        case .cameraSilent: return "video.slash.fill"
        case .spoof, .wrongTurn: return "exclamationmark.shield.fill"
        case .noProof, .noFace, .stranger: return "exclamationmark.circle.fill"
        }
    }

    private func tint(for result: RecognitionTest.Result) -> Color {
        switch result {
        case .passed: return Theme.mint
        case .spoof, .wrongTurn, .cameraSilent: return Theme.coral
        default: return Theme.amber
        }
    }

    private func title(for result: RecognitionTest.Result) -> String {
        switch result {
        case .passed(let name, let seconds):
            return "This would unlock your Mac as \(name), in \(seconds.formatted(.number.precision(.fractionLength(1)))) seconds"
        case .noProof: return "Recognized, but no blink or movement was seen"
        case .noFace: return "No face was found"
        case .tooDark: return "It's too dark to see you"
        case .stranger: return "This face doesn't match a saved one"
        case .spoof: return "This looked like a screen or a photo"
        case .wrongTurn: return "That was the wrong way"
        case .cameraSilent: return "The camera isn't responding"
        }
    }

    private func detail(for result: RecognitionTest.Result) -> String? {
        switch result {
        case .passed: return nil
        case .noProof: return "Blink naturally while looking at the camera. At the lock screen Sesame would try again on its own."
        case .noFace: return "Sit so your whole face is in view, facing the camera."
        case .tooDark: return "Turn on a light or face a window."
        case .stranger: return "If your look has changed, add another face. Glasses and hats are worth their own."
        case .spoof: return "A rectangle surrounded the face. Move away from frames or screens behind you."
        case .wrongTurn: return "At the lock screen this counts as a failed attempt, which is what stops a video of you. Follow the arrow, and look back at the screen between turns."
        case .cameraSilent: return "Another app may be using it. Close that app and test again."
        }
    }
}

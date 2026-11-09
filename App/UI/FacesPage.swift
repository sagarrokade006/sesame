import AVFoundation
import Observation
import SesameCore
import SwiftUI

struct FacesPage: View {
    let model: AppModel
    @State private var enrollment: Enrollment?
    @State private var test: RecognitionTest?

    private var vault: Vault { model.vault }
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        if let enrollment {
            EnrollmentPanel(enrollment: enrollment) { finished in
                if let finished {
                    vault.update { $0.profiles.append(finished) }
                }
                enrollment.stop()
                NotchScanner.shared.hide()
                self.enrollment = nil
            }
        } else if let test {
            RecognitionTestPanel(test: test) {
                test.stop()
                self.test = nil
            }
        } else if vault.contents.profiles.isEmpty {
            emptyState
        } else {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(vault.contents.profiles) { profile in
                    FaceCard(profile: profile, setActive: { setActive(profile, $0) }, rename: { rename(profile, to: $0) }, remove: { remove(profile) })
                }
                addCard
            }
            Card {
                SettingRow(icon: "checkmark.seal.fill", tint: Theme.sky, title: "Test face unlock",
                           detail: "See how well you match and what Sesame is waiting for, without locking your Mac.") {
                    Button("Test") { startTest() }
                        .disabled(!vault.contents.profiles.contains(where: \.isActive))
                }
            }
            Text("Add another face if you often wear glasses or a hat. Switch a face off to keep it without using it.")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
                .padding(.leading, 4)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Hexagon().fill(Theme.mint.opacity(0.1))
                Hexagon().stroke(Theme.mint.opacity(0.45), style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                Image(systemName: "person.crop.square.fill").font(.system(size: 28)).foregroundStyle(Theme.mint)
            }
            .frame(width: 84, height: 84)
            VStack(spacing: 4) {
                Text("Add your face").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.primary)
                Text("Center your face, hold still, then move your head in a slow circle. It takes about 20 seconds.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            PrimaryButton(title: "Scan my face", symbol: "camera.viewfinder") { startEnrollment() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line))
    }

    private var addCard: some View {
        Button { startEnrollment() } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.mint)
                Text("Add a face").font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 132)
            .background(Theme.mint.opacity(0.04), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.mint.opacity(0.4), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setActive(_ profile: FaceProfile, _ isOn: Bool) {
        vault.update { contents in
            contents.profiles.indices
                .filter { contents.profiles[$0].id == profile.id }
                .forEach { contents.profiles[$0].isActive = isOn }
        }
    }

    private func rename(_ profile: FaceProfile, to name: String) {
        vault.update { contents in
            contents.profiles.indices
                .filter { contents.profiles[$0].id == profile.id }
                .forEach { contents.profiles[$0].name = name }
        }
    }

    private func remove(_ profile: FaceProfile) {
        vault.update { $0.profiles.removeAll { $0.id == profile.id } }
    }

    private func startTest() {
        Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else { return }
            let session = RecognitionTest(contents: vault.contents)
            session.start()
            test = session
        }
    }

    /// `showingTest` is for snapshots: it opens with the test panel partway through.
    init(model: AppModel, showingTest: Bool = false) {
        self.model = model
        #if DEBUG
        if showingTest {
            let session = RecognitionTest(contents: model.vault.contents)
            session.pretendWaitingForProof()
            _test = State(initialValue: session)
        }
        #endif
    }

    private func startEnrollment() {
        Task {
            // Adding a face is the most sensitive change there is, so an open vault isn't enough.
            guard await vault.requireApproval("add a face to Sesame"),
                  await AVCaptureDevice.requestAccess(for: .video)
            else { return }
            AppModel.bringToFront()
            let session = Enrollment()
            session.start()
            enrollment = session
            NotchScanner.shared.show(session)
        }
    }
}

private struct FaceCard: View {
    let profile: FaceProfile
    let setActive: (Bool) -> Void
    let rename: (String) -> Void
    let remove: () -> Void
    @State private var confirmingRemove = false
    @State private var isRenaming = false
    @State private var newName = ""

    private var usage: String {
        guard let count = profile.unlockCount, count > 0, let last = profile.lastUsedAt else { return "Not used yet" }
        return "\(count) \(count == 1 ? "unlock" : "unlocks") · Last \(last.formatted(.relative(presentation: .named)))"
    }

    private var initials: String {
        let letters = profile.name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                ZStack {
                    Hexagon().fill(profile.isActive ? Theme.mint.opacity(0.2) : Color.white.opacity(0.06))
                    Hexagon().stroke(profile.isActive ? Theme.mint : Theme.tertiary, lineWidth: 1.5)
                    Text(initials)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(profile.isActive ? Theme.mint : Theme.secondary)
                }
                .frame(width: 44, height: 44)
                Spacer()
                Menu {
                    Button("Rename…") {
                        newName = profile.name
                        isRenaming = true
                    }
                    Divider()
                    Button("Remove \(profile.name)…", role: .destructive) { confirmingRemove = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.primary).lineLimit(1)
                Text("\(profile.vectors.count) samples · Added \(profile.createdAt.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.secondary)
                Text(usage).font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
            }
            HStack {
                Text(profile.isActive ? "Used for unlock" : "Switched off")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(profile.isActive ? Theme.mint : Theme.tertiary)
                Spacer()
                Switch(isOn: Binding(get: { profile.isActive }, set: { setActive($0) }))
            }
        }
        .padding(16)
        .frame(minHeight: 132)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).strokeBorder(Theme.line))
        .confirmationDialog("Remove \(profile.name)?", isPresented: $confirmingRemove) {
            Button("Remove", role: .destructive, action: remove)
        } message: {
            Text("Sesame will stop recognizing this face. You can scan it again later.")
        }
        .alert("Rename face", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Save") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { rename(trimmed) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// Feeds camera frames into the scan and keeps its state for the scanner screen.
@MainActor
@Observable
final class Enrollment {
    private(set) var scan = FaceScan()
    var name = ""

    @ObservationIgnored let camera = CameraFeed()
    @ObservationIgnored private let reader = FaceReader()

    func start() {
        let reader = self.reader
        camera.start { [weak self] pixels, time in
            let capture = reader.read(pixels, at: time)
            Task { @MainActor in self?.receive(capture) }
        }
    }

    func stop() {
        camera.stop()
    }

    private func receive(_ capture: FaceCapture?) {
        guard let capture, scan.stage != .complete else { return }
        scan.observe(
            vector: capture.vector,
            yaw: capture.reading.yaw,
            pitch: capture.reading.pitch ?? 0,
            time: capture.reading.time,
            isWellPlaced: capture.widthFraction >= 0.2 && capture.distanceFromCenter <= 0.24 && capture.captureQuality >= 0.25
        )
        if scan.stage == .complete { camera.stop() }
    }

    #if DEBUG
    /// For snapshots: feeds made-up head poses through the real scan, lighting part of the ring.
    func simulateScan(share: Double) {
        let vector = FaceVector([1, 0, 0])
        var time = 0.0
        for _ in 0..<8 {
            time += 0.2
            scan.observe(vector: vector, yaw: 0, pitch: 0, time: time, isWellPlaced: true)
        }
        let steps = Int(Double(FaceScan.tickCount) * share)
        for step in 0..<steps {
            time += 0.2
            let angle = Double(step) / Double(FaceScan.tickCount) * 2 * .pi
            scan.observe(vector: vector, yaw: -sin(angle) * 0.4, pitch: -cos(angle) * 0.3, time: time, isWellPlaced: true)
        }
    }
    #endif

    func makeProfile() -> FaceProfile {
        FaceProfile(
            name: name.trimmingCharacters(in: .whitespaces),
            vectors: scan.vectors,
            modelVersion: FaceReader.modelVersion,
            createdAt: Date()
        )
    }
}

/// The window's half of adding a face. The camera and ring show in the notch, right under the camera you're looking
/// at; this tracks progress and, once the scan is done, asks for a name.
private struct EnrollmentPanel: View {
    @Bindable var enrollment: Enrollment
    let finish: (FaceProfile?) -> Void

    private var isComplete: Bool { enrollment.scan.stage == .complete }

    var body: some View {
        Card {
            VStack(spacing: 16) {
                if isComplete {
                    ScanMark(state: .success).frame(width: 64, height: 64)
                } else {
                    ZStack {
                        Hexagon().fill(Theme.mint.opacity(0.1))
                        Image(systemName: "arrow.up").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.mint)
                    }
                    .frame(width: 64, height: 64)
                }

                VStack(spacing: 4) {
                    Text(isComplete ? "Face scanned" : scannerPrompt(for: enrollment.scan.stage))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .contentTransition(.opacity)
                    Text(isComplete ? "Give this face a name." : "Look at the camera. Your scan is showing at the top of the screen.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.secondary)
                }
                .animation(.easeOut(duration: 0.2), value: enrollment.scan.stage)

                if isComplete {
                    TextField("Name", text: $enrollment.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .onSubmit(save)
                } else {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule().fill(Theme.mint).frame(width: max(6, proxy.size.width * enrollment.scan.progress))
                        }
                    }
                    .frame(width: 260, height: 6)
                    .animation(.easeOut(duration: 0.2), value: enrollment.scan.progress)
                }

                HStack {
                    Button("Cancel") { finish(nil) }
                    Spacer()
                    if isComplete {
                        Button("Save", action: save)
                            .buttonStyle(FilledButtonStyle(color: Theme.mint))
                            .disabled(enrollment.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: isComplete) { _, done in
            if done { AppModel.bringToFront() }
        }
    }

    private func save() {
        guard !enrollment.name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        finish(enrollment.makeProfile())
    }
}

func scannerPrompt(for stage: FaceScan.Stage) -> String {
    switch stage {
    case .position: return "Center your face in the circle"
    case .holdStill: return "Hold still"
    case .turn: return "Move your head slowly in a circle"
    case .complete: return "Face scanned"
    }
}

/// The round camera view with its ring of tick marks.
struct FaceScannerDial<Preview: View>: View {
    let scan: FaceScan
    var previewSize: CGFloat = 212
    var dialSize: CGFloat = 276
    @ViewBuilder let preview: Preview

    var body: some View {
        ZStack {
            ForEach(0..<FaceScan.tickCount, id: \.self) { tick in
                let isLit = scan.litTicks.contains(tick) || scan.stage == .complete
                let isActive = scan.activeTick == tick
                Capsule()
                    .fill(isActive ? Color.white : (isLit ? Theme.mint : Color.white.opacity(0.2)))
                    .frame(width: 3.5, height: isActive ? 24 : (isLit ? 20 : 14))
                    .offset(y: -(dialSize / 2 - dialSize * 0.05))
                    .rotationEffect(.degrees(Double(tick) / Double(FaceScan.tickCount) * 360))
                    .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isLit)
                    .animation(.easeOut(duration: 0.12), value: isActive)
            }

            preview
                // Mirrored, so moving your head left moves it left on screen.
                .scaleEffect(x: -1, y: 1)
                .frame(width: previewSize, height: previewSize)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.12)))

            if scan.stage == .complete {
                Circle()
                    .fill(.black.opacity(0.55))
                    .frame(width: previewSize, height: previewSize)
                ScanMark(state: .success)
                    .frame(width: 92, height: 92)
            }
        }
        .frame(width: dialSize, height: dialSize)
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = preview
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

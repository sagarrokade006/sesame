import AVFoundation
import Observation
import SesameCore
import SwiftUI

struct FacesPage: View {
    let model: AppModel
    @State private var enrollment: Enrollment?

    private var vault: Vault { model.vault }

    var body: some View {
        if let enrollment {
            EnrollmentPanel(enrollment: enrollment) { finished in
                if let finished {
                    vault.update { $0.profiles.append(finished) }
                }
                enrollment.stop()
                self.enrollment = nil
            }
        } else {
            Panel {
                if vault.contents.profiles.isEmpty {
                    PanelRow(title: "No faces yet") { EmptyView() }
                }
                ForEach(Array(vault.contents.profiles.enumerated()), id: \.element.id) { index, profile in
                    if index > 0 { PanelDivider() }
                    PanelRow(title: profile.name, detail: "\(profile.vectors.count) samples") {
                        Toggle("", isOn: Binding(
                            get: { profile.isActive },
                            set: { isOn in
                                vault.update { contents in
                                    contents.profiles.indices
                                        .filter { contents.profiles[$0].id == profile.id }
                                        .forEach { contents.profiles[$0].isActive = isOn }
                                }
                            }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(Theme.mint)
                        Button(role: .destructive) {
                            vault.update { $0.profiles.removeAll { $0.id == profile.id } }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Button("Add a face") { startEnrollment() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.mint)
        }
    }

    private func startEnrollment() {
        Task {
            // Adding a face is the most sensitive change there is, so an open vault isn't enough.
            guard await vault.requireApproval("add a face to Sesame"),
                  await AVCaptureDevice.requestAccess(for: .video)
            else { return }
            let session = Enrollment()
            session.start()
            enrollment = session
        }
    }
}

/// Guides someone through looking in a few directions and collects face samples at each.
@MainActor
@Observable
final class Enrollment {
    struct Pose {
        let prompt: String
        let yaw: ClosedRange<Double>
        let pitch: ClosedRange<Double>
    }

    private static let poses = [
        Pose(prompt: "Look straight ahead", yaw: -0.14...0.14, pitch: -0.18...0.18),
        Pose(prompt: "Turn slightly left", yaw: 0.2...0.5, pitch: -0.25...0.25),
        Pose(prompt: "Turn slightly right", yaw: -0.5 ... -0.2, pitch: -0.25...0.25),
        Pose(prompt: "Tilt your head up", yaw: -0.25...0.25, pitch: -0.5 ... -0.14),
        Pose(prompt: "Tilt your head down", yaw: -0.25...0.25, pitch: 0.14...0.5),
    ]
    private static let samplesPerPose = 4

    private(set) var prompt = Enrollment.poses[0].prompt
    private(set) var progress = 0.0
    private(set) var isComplete = false
    var name = ""

    @ObservationIgnored let camera = CameraFeed()
    @ObservationIgnored private let reader = FaceReader()
    @ObservationIgnored private var vectors: [FaceVector] = []
    @ObservationIgnored private var poseIndex = 0
    @ObservationIgnored private var samplesInPose = 0
    @ObservationIgnored private var lastSampleAt: TimeInterval = 0

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
        guard !isComplete, let capture else { return }
        let pose = Self.poses[poseIndex]
        guard let pitch = capture.reading.pitch, pose.yaw.contains(capture.reading.yaw), pose.pitch.contains(pitch),
              capture.widthFraction >= 0.2, capture.captureQuality >= 0.3,
              capture.reading.time - lastSampleAt >= 0.2
        else { return }

        lastSampleAt = capture.reading.time
        vectors.append(capture.vector)
        samplesInPose += 1
        progress = Double(vectors.count) / Double(Self.poses.count * Self.samplesPerPose)

        guard samplesInPose >= Self.samplesPerPose else { return }
        samplesInPose = 0
        poseIndex += 1
        if poseIndex < Self.poses.count {
            prompt = Self.poses[poseIndex].prompt
        } else {
            isComplete = true
            prompt = "All done"
            camera.stop()
        }
    }

    func makeProfile() -> FaceProfile {
        FaceProfile(
            name: name.trimmingCharacters(in: .whitespaces),
            vectors: vectors,
            modelVersion: FaceReader.modelVersion,
            createdAt: Date()
        )
    }
}

private struct EnrollmentPanel: View {
    @Bindable var enrollment: Enrollment
    let finish: (FaceProfile?) -> Void

    var body: some View {
        Panel {
            VStack(spacing: 14) {
                CameraPreview(session: enrollment.camera.session)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(enrollment.prompt)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                ProgressView(value: enrollment.progress).tint(Theme.mint)

                if enrollment.isComplete {
                    TextField("Name", text: $enrollment.name).textFieldStyle(.roundedBorder)
                }
                HStack {
                    Button("Cancel") { finish(nil) }
                    Spacer()
                    if enrollment.isComplete {
                        Button("Save") { finish(enrollment.makeProfile()) }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.mint)
                            .disabled(enrollment.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .padding(14)
        }
    }
}

private struct CameraPreview: NSViewRepresentable {
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

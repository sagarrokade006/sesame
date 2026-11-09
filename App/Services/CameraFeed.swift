@preconcurrency import AVFoundation
import CoreVideo
import Foundation

/// Delivers camera frames on a background queue. Frames are analyzed and discarded, never stored.
final class CameraFeed: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    typealias Handler = @Sendable (CVPixelBuffer, TimeInterval) -> Void

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.sagarrokade.sesame.camera")
    private var handler: Handler?
    private var isConfigured = false

    /// A virtual camera can feed prerecorded video past every liveness check, so only real hardware is used.
    static func trustedDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let usbTransport = Int32(bitPattern: 0x7573_6220)
        return discovery.devices.first { $0.deviceType == .builtInWideAngleCamera }
            ?? discovery.devices.first(where: \.isContinuityCamera)
            ?? discovery.devices.first { $0.transportType == usbTransport }
    }

    func start(_ handler: Handler?) {
        queue.async { [self] in
            self.handler = handler
            configureIfNeeded()
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            handler = nil
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured, let device = Self.trustedDevice(),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        if session.canAddInput(input) { session.addInput(input) }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        isConfigured = true
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let handler, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        handler(pixels, ProcessInfo.processInfo.systemUptime)
    }
}

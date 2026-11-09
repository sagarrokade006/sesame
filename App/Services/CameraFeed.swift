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

    override init() {
        super.init()
        // A camera that errors out or is unplugged mid-session is set up from scratch next time.
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self, queue] _ in
                queue.async { [weak self] in self?.needsFreshSetup = true }
            }
        }
    }

    private var needsFreshSetup = false

    func start(_ handler: Handler?) {
        queue.async { [self] in
            self.handler = handler
            configureIfNeeded()
            if isConfigured, !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            handler = nil
            if session.isRunning { session.stopRunning() }
        }
    }

    /// Sets the session up once, and again whenever its camera has gone away or failed.
    private func configureIfNeeded() {
        let currentDevice = (session.inputs.first as? AVCaptureDeviceInput)?.device
        if isConfigured, needsFreshSetup || currentDevice?.isConnected != true || currentDevice?.uniqueID != Self.trustedDevice()?.uniqueID {
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            session.outputs.forEach(session.removeOutput)
            session.commitConfiguration()
            isConfigured = false
        }
        needsFreshSetup = false
        guard !isConfigured, let device = Self.trustedDevice(),
              let input = try? AVCaptureDeviceInput(device: device)
        else { return }
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
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

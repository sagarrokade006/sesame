import CoreImage
import CoreML
import CoreVideo
import SesameCore
import Vision

struct FaceCapture: Sendable {
    let reading: FaceReading
    let vector: FaceVector
    /// Share of the frame's width the face fills.
    let widthFraction: Double
    let captureQuality: Double
}

/// Turns one camera frame into a face description. Everything happens on the calling background queue.
final class FaceReader: @unchecked Sendable {
    static let modelVersion = "sface-2021dec"
    private static let minimumFaceWidth = 0.16

    private let model: MLModel?
    private let context = CIContext(options: [.workingColorSpace: NSNull()])

    init() {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        model = Bundle.main.url(forResource: "SFace", withExtension: "mlmodelc")
            .flatMap { try? MLModel(contentsOf: $0, configuration: configuration) }
    }

    var isReady: Bool { model != nil }

    func read(_ pixels: CVPixelBuffer, at time: TimeInterval) -> FaceCapture? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixels)
        let rectangles = VNDetectFaceRectanglesRequest()
        rectangles.revision = VNDetectFaceRectanglesRequestRevision3
        guard (try? handler.perform([rectangles])) != nil,
              let face = rectangles.results?.max(by: { Self.area($0.boundingBox) < Self.area($1.boundingBox) }),
              face.boundingBox.width >= Self.minimumFaceWidth
        else { return nil }

        let landmarks = VNDetectFaceLandmarksRequest()
        landmarks.inputFaceObservations = [face]
        let quality = VNDetectFaceCaptureQualityRequest()
        quality.inputFaceObservations = [face]
        let outlines = VNDetectRectanglesRequest()
        outlines.minimumSize = 0.25
        outlines.maximumObservations = 4
        guard (try? handler.perform([landmarks, quality, outlines])) != nil,
              let marked = landmarks.results?.first,
              let features = Self.features(of: marked, in: pixels),
              let aligned = align(pixels, features: features),
              let vector = embed(aligned)
        else { return nil }

        let reading = FaceReading(
            time: time,
            yaw: face.yaw?.doubleValue ?? 0,
            pitch: face.pitch?.doubleValue,
            leftEyeOpenness: features.leftEyeOpenness,
            rightEyeOpenness: features.rightEyeOpenness,
            noseShift: features.noseShift,
            isFramedByRectangle: Self.isFramed(face.boundingBox, by: outlines.results ?? [])
        )
        return FaceCapture(
            reading: reading,
            vector: vector,
            widthFraction: Double(face.boundingBox.width),
            captureQuality: Double(quality.results?.first?.faceCaptureQuality ?? 0)
        )
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }

    /// A phone or printout shows up as a rectangle around the face, one that isn't just the whole picture.
    private static func isFramed(_ face: CGRect, by outlines: [VNRectangleObservation]) -> Bool {
        let expected = face.insetBy(dx: -face.width * 0.05, dy: -face.height * 0.05)
        return outlines.contains { outline in
            outline.boundingBox.contains(expected) && area(outline.boundingBox) < 0.85
        }
    }

    private struct Features {
        let points: [PlanePoint]
        let leftEyeOpenness: Double
        let rightEyeOpenness: Double
        let noseShift: Double
    }

    private static func features(of face: VNFaceObservation, in pixels: CVPixelBuffer) -> Features? {
        guard let marks = face.landmarks, let leftEye = marks.leftEye, let rightEye = marks.rightEye,
              let nose = marks.nose, let lips = marks.outerLips
        else { return nil }
        let size = CGSize(width: CVPixelBufferGetWidth(pixels), height: CVPixelBufferGetHeight(pixels))

        let first = leftEye.pointsInImage(imageSize: size)
        let second = rightEye.pointsInImage(imageSize: size)
        guard let firstCenter = center(first), let secondCenter = center(second),
              let noseCenter = center(nose.pointsInImage(imageSize: size))
        else { return nil }

        let lipPoints = lips.pointsInImage(imageSize: size)
        guard let mouthLeft = lipPoints.min(by: { $0.x < $1.x }),
              let mouthRight = lipPoints.max(by: { $0.x < $1.x })
        else { return nil }

        let (imageLeftEye, imageRightEye) = firstCenter.x < secondCenter.x ? (firstCenter, secondCenter) : (secondCenter, firstCenter)
        let eyeSpan = imageRightEye.x - imageLeftEye.x
        guard eyeSpan > 0 else { return nil }

        return Features(
            points: [imageLeftEye, imageRightEye, noseCenter, mouthLeft, mouthRight].map { PlanePoint(x: $0.x, y: $0.y) },
            leftEyeOpenness: openness(first),
            rightEyeOpenness: openness(second),
            noseShift: (noseCenter.x - (imageLeftEye.x + imageRightEye.x) / 2) / eyeSpan
        )
    }

    private static func center(_ points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let count = CGFloat(points.count)
        return CGPoint(x: points.map(\.x).reduce(0, +) / count, y: points.map(\.y).reduce(0, +) / count)
    }

    private static func openness(_ points: [CGPoint]) -> Double {
        guard let left = points.map(\.x).min(), let right = points.map(\.x).max(),
              let bottom = points.map(\.y).min(), let top = points.map(\.y).max(), right > left
        else { return 0 }
        return Double((top - bottom) / (right - left))
    }

    private func align(_ pixels: CVPixelBuffer, features: Features) -> CVPixelBuffer? {
        guard let fit = SimilarityTransform.fit(from: features.points, to: FaceTemplate.landmarks) else { return nil }
        let side = Int(FaceTemplate.side)
        var output: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()]
        CVPixelBufferCreate(nil, side, side, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &output)
        guard let output else { return nil }

        let transform = CGAffineTransform(a: fit.a, b: fit.b, c: -fit.b, d: fit.a, tx: fit.tx, ty: fit.ty)
        let warped = CIImage(cvPixelBuffer: pixels).transformed(by: transform)
        context.render(
            warped,
            to: output,
            bounds: CGRect(x: 0, y: 0, width: side, height: side),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return output
    }

    private func embed(_ face: CVPixelBuffer) -> FaceVector? {
        guard let model,
              let input = try? MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: face)]),
              let array = try? model.prediction(from: input).featureValue(for: "embedding")?.multiArrayValue
        else { return nil }
        return FaceVector((0..<array.count).map { array[$0].floatValue })
    }
}

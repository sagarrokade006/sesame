import Foundation
import Testing
@testable import SesameCore

private let vector = FaceVector([1, 0])

private struct ScanRun {
    var scan = FaceScan()
    var time = 0.0

    mutating func feed(yaw: Double = 0, pitch: Double = 0, placed: Bool = true) {
        time += 0.05
        scan.observe(vector: vector, yaw: yaw, pitch: pitch, time: time, isWellPlaced: placed)
    }

    mutating func hold(frames: Int = 30) {
        for _ in 0..<frames { feed() }
    }

    /// Rolls the head around a full circle, slowly enough for the camera to catch every direction.
    mutating func circle(radius: Double = 1.4, steps: Int = 240) {
        for step in 0..<steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            feed(yaw: -sin(angle) * radius * 0.26, pitch: -cos(angle) * radius * 0.2)
        }
    }
}

@Suite struct FaceScanTests {
    @Test func headDirectionsMapToTheRing() {
        #expect(FaceScan.tick(yaw: 0, pitch: -0.3) == 0)
        #expect(FaceScan.tick(yaw: -0.4, pitch: 0) == 15)
        #expect(FaceScan.tick(yaw: 0, pitch: 0.3) == 30)
        #expect(FaceScan.tick(yaw: 0.4, pitch: 0) == 45)
    }

    @Test func aCenteredOrExtremeHeadLightsNothing() {
        #expect(FaceScan.tick(yaw: 0, pitch: 0) == nil)
        #expect(FaceScan.tick(yaw: 0.05, pitch: 0.05) == nil)
        #expect(FaceScan.tick(yaw: 1.2, pitch: 0) == nil)
    }

    @Test func aPoorlyPlacedFaceCanNotStart() {
        var run = ScanRun()
        for _ in 0..<30 { run.feed(placed: false) }
        #expect(run.scan.stage == .position)
    }

    @Test func aTurnedHeadCanNotStart() {
        var run = ScanRun()
        for _ in 0..<30 { run.feed(yaw: 0.4) }
        #expect(run.scan.stage == .position)
    }

    @Test func holdingStillLeadsToTurning() {
        var run = ScanRun()
        run.hold()
        #expect(run.scan.stage == .turn)
        #expect(run.scan.vectors.count == 5)
    }

    @Test func aFullCircleCompletes() {
        var run = ScanRun()
        run.hold()
        run.circle()
        #expect(run.scan.stage == .complete)
        #expect(run.scan.progress == 1)
        #expect(run.scan.activeTick == nil)
    }

    @Test func aFullCircleCollectsSamplesFromAllAround() {
        var run = ScanRun()
        run.hold()
        run.circle()
        #expect(run.scan.vectors.count >= 20)
        #expect(run.scan.vectors.count <= 29)
    }

    @Test func halfACircleIsNotEnough() {
        var run = ScanRun()
        run.hold()
        for step in 0..<60 {
            let angle = Double(step) / 60 * .pi
            run.feed(yaw: -sin(angle) * 0.36, pitch: -cos(angle) * 0.28)
        }
        #expect(run.scan.stage == .turn)
        #expect(run.scan.progress < 1)
    }

    @Test func staringAtTheCameraNeverFinishes() {
        var run = ScanRun()
        run.hold(frames: 400)
        #expect(run.scan.stage == .turn)
        #expect(run.scan.litTicks.isEmpty)
    }

    @Test func aFaceLeavingTheCircleStopsLightingTicks() {
        var run = ScanRun()
        run.hold()
        for _ in 0..<10 { run.feed(yaw: -0.4, placed: false) }
        #expect(run.scan.litTicks.isEmpty)
    }
}

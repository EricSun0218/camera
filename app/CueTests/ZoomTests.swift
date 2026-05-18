// app/CueTests/ZoomTests.swift
import Testing
import Foundation
import CoreGraphics
import Vision
@testable import Cue

@Suite("ZoomMapping") struct ZoomMappingTests {

    @Test func singleCamMapping() {
        // Single-wide camera: raw 1x == optical 1x, no 0.5x.
        let m = ZoomMapping(oneXRawFactor: 1.0, minRaw: 1.0, maxRaw: 120.0)
        #expect(m.minOptical == 1.0)
        #expect(m.maxOptical == 3.0)
        #expect(m.rawFor(optical: 2.0) == 2.0)
        #expect(m.rawFor(optical: 0.2) == 1.0)   // clamped up to minOptical
        #expect(m.rawFor(optical: 9.0) == 3.0)   // clamped down to maxOptical
    }

    @Test func dualWideMapping() {
        // Virtual dual-wide: raw 2.0 is the main "1x" lens, raw 1.0 is 0.5x.
        let m = ZoomMapping(oneXRawFactor: 2.0, minRaw: 1.0, maxRaw: 12.0)
        #expect(m.minOptical == 0.5)
        #expect(m.maxOptical == 3.0)
        #expect(m.rawFor(optical: 0.5) == 1.0)
        #expect(m.rawFor(optical: 1.0) == 2.0)
        #expect(m.rawFor(optical: 3.0) == 6.0)
        #expect(m.rawFor(optical: 0.1) == 1.0)   // clamp to 0.5x -> raw 1.0
        #expect(m.rawFor(optical: 9.0) == 6.0)   // clamp to 3.0x -> raw 6.0
    }

    @Test func clampOptical() {
        let m = ZoomMapping(oneXRawFactor: 2.0, minRaw: 1.0, maxRaw: 12.0)
        #expect(m.clampOptical(0.1) == 0.5)
        #expect(m.clampOptical(5.0) == 3.0)
        #expect(m.clampOptical(1.5) == 1.5)
    }

    @Test func initClampsInvalidInputs() {
        // oneXRawFactor below 1.0 is clamped up to 1.0.
        #expect(ZoomMapping(oneXRawFactor: 0.5, minRaw: 1.0, maxRaw: 10.0).oneXRawFactor == 1.0)
        // minRaw below 1.0 is clamped up to 1.0.
        #expect(ZoomMapping(oneXRawFactor: 1.0, minRaw: 0.0, maxRaw: 10.0).minRaw == 1.0)
        // maxRaw below minRaw is clamped up to minRaw.
        let m = ZoomMapping(oneXRawFactor: 1.0, minRaw: 4.0, maxRaw: 2.0)
        #expect(m.maxRaw == 4.0)
    }
}

@Suite("NeededOpticalZoom") struct NeededOpticalZoomTests {

    @Test func personHeightMatch() {
        // detected height 0.3, target height 0.6 -> needs 2x.
        let z = AlignmentChecker.neededOpticalZoom(
            kind: .person,
            targetSize: CGSize(width: 0.3, height: 0.6),
            detectedSize: CGSize(width: 0.15, height: 0.3),
            currentOptical: 1.0, calibration: 1.0)
        #expect(abs(z - 2.0) < 1e-9)
    }

    @Test func personRespectsCurrentOptical() {
        // Same ratio but already at 1.5x -> 3.0x.
        let z = AlignmentChecker.neededOpticalZoom(
            kind: .person,
            targetSize: CGSize(width: 0.3, height: 0.6),
            detectedSize: CGSize(width: 0.15, height: 0.3),
            currentOptical: 1.5, calibration: 1.0)
        #expect(abs(z - 3.0) < 1e-9)
    }

    @Test func personCalibration() {
        // calibration 0.85: 1.0 * 0.6 * 0.85 / 0.3 = 1.7.
        let z = AlignmentChecker.neededOpticalZoom(
            kind: .person,
            targetSize: CGSize(width: 0.3, height: 0.6),
            detectedSize: CGSize(width: 0.15, height: 0.3),
            currentOptical: 1.0, calibration: 0.85)
        #expect(abs(z - 1.7) < 1e-9)
    }

    @Test func sceneAreaMatch() {
        // target area 0.24, detected area 0.06 -> sqrt(4) = 2x.
        let z = AlignmentChecker.neededOpticalZoom(
            kind: .scene,
            targetSize: CGSize(width: 0.4, height: 0.6),
            detectedSize: CGSize(width: 0.2, height: 0.3),
            currentOptical: 1.0)
        #expect(abs(z - 2.0) < 1e-9)
    }

    @Test func degenerateDetectedReturnsCurrent() {
        let z = AlignmentChecker.neededOpticalZoom(
            kind: .person,
            targetSize: CGSize(width: 0.3, height: 0.6),
            detectedSize: CGSize(width: 0, height: 0),
            currentOptical: 1.3)
        #expect(z == 1.3)
    }
}

@Suite("MeasuredSubject") struct MeasuredSubjectTests {

    @Test func personFromBodyPose() {
        // Joints span x 0.4..0.5 (w 0.1), y 0.1..0.9 (h 0.8).
        let joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [
            .nose: CGPoint(x: 0.5, y: 0.9),
            .leftAnkle: CGPoint(x: 0.4, y: 0.1),
        ]
        let state = ComposeState(subjectBox: nil, faceBoxes: [],
                                 horizonDegrees: 0,
                                 bodyPose: BodyPose(joints: joints, confidence: 0.9),
                                 trackedBox: nil)
        let m = AlignmentChecker.measuredSubject(kind: .person, state: state)
        #expect(m?.comparable == true)
        #expect(abs((m?.size.width ?? -1) - 0.1) < 1e-6)
        #expect(abs((m?.size.height ?? -1) - 0.8) < 1e-6)
    }

    @Test func personFaceFallbackNotComparable() {
        let state = ComposeState(subjectBox: nil,
                                 faceBoxes: [CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.25)],
                                 horizonDegrees: 0, bodyPose: .none, trackedBox: nil)
        let m = AlignmentChecker.measuredSubject(kind: .person, state: state)
        #expect(m?.comparable == false)
        #expect(abs((m?.size.height ?? -1) - 0.25) < 1e-6)
    }

    @Test func personNothingDetected() {
        let m = AlignmentChecker.measuredSubject(kind: .person, state: .initial)
        #expect(m == nil)
    }

    @Test func sceneFromSubjectBox() {
        let state = ComposeState(subjectBox: CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.4),
                                 faceBoxes: [], horizonDegrees: 0,
                                 bodyPose: .none, trackedBox: nil)
        let m = AlignmentChecker.measuredSubject(kind: .scene, state: state)
        #expect(m?.comparable == true)
        #expect(abs((m?.size.width ?? -1) - 0.3) < 1e-6)
    }

    @Test func sceneNothingDetected() {
        let m = AlignmentChecker.measuredSubject(kind: .scene, state: .initial)
        #expect(m == nil)
    }
}

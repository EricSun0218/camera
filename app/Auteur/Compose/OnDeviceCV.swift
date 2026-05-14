// app/Auteur/Compose/OnDeviceCV.swift
import Vision
import CoreMotion
import CoreImage
import Combine
import UIKit

public struct BodyPose: Equatable {
    /// Joint points in normalized [0,1] image coords. Empty when no body detected.
    public var joints: [VNHumanBodyPoseObservation.JointName: CGPoint]
    /// Confidence-weighted overall body presence (0..1).
    public var confidence: Float
    /// Shoulder slant in degrees (positive = right shoulder higher). nil if shoulders not detected.
    public var shoulderSlantDegrees: Double?
    /// Spine tilt in degrees off vertical (positive = leaning right). nil if hips+shoulders not detected.
    public var spineTiltDegrees: Double?
    /// Head tilt in degrees off vertical (positive = right ear lower). nil if ears not detected.
    public var headTiltDegrees: Double?

    public static let none = BodyPose(joints: [:], confidence: 0,
                                       shoulderSlantDegrees: nil,
                                       spineTiltDegrees: nil,
                                       headTiltDegrees: nil)
}

public struct ComposeState: Equatable {
    public var subjectBox: CGRect?     // normalized to [0,1] in image coords
    public var faceBoxes: [CGRect]     // normalized
    public var horizonDegrees: Double  // device roll relative to ground, -180..180
    public var bodyPose: BodyPose      // pose skeleton when a person is in frame

    public static let initial = ComposeState(subjectBox: nil, faceBoxes: [],
                                              horizonDegrees: 0, bodyPose: .none)
}

public final class OnDeviceCV: ObservableObject {
    @Published public private(set) var state: ComposeState = .initial

    private let motion = CMMotionManager()
    private let saliencyQ = DispatchQueue(label: "auteur.cv.saliency", qos: .userInitiated)
    private let faceQ     = DispatchQueue(label: "auteur.cv.face",     qos: .userInitiated)
    private let poseQ     = DispatchQueue(label: "auteur.cv.pose",     qos: .userInitiated)
    private var lastSaliencyAt: TimeInterval = 0
    private var lastFaceAt: TimeInterval = 0
    private var lastPoseAt: TimeInterval = 0
    private let cvHz: TimeInterval = 1.0 / 10.0  // 10 Hz throttle

    public init() {
        startMotion()
    }

    deinit { motion.stopDeviceMotionUpdates() }

    private func startMotion() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] dm, _ in
            guard let self, let dm else { return }
            // Convert roll (radians, around z-axis in portrait) to degrees.
            let deg = dm.attitude.roll * 180.0 / .pi
            DispatchQueue.main.async { self.state.horizonDegrees = deg }
        }
    }

    /// Feed each preview frame here. Internally throttles to 10 Hz.
    public func ingest(pixelBuffer: CVPixelBuffer) {
        let now = CACurrentMediaTime()
        if now - lastSaliencyAt > cvHz {
            lastSaliencyAt = now
            runSaliency(pixelBuffer: pixelBuffer)
        }
        if now - lastFaceAt > cvHz {
            lastFaceAt = now
            runFaces(pixelBuffer: pixelBuffer)
        }
        if now - lastPoseAt > cvHz {
            lastPoseAt = now
            runBodyPose(pixelBuffer: pixelBuffer)
        }
    }

    private func runSaliency(pixelBuffer: CVPixelBuffer) {
        saliencyQ.async { [weak self] in
            let req = VNGenerateAttentionBasedSaliencyImageRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([req])
                guard let result = req.results?.first, let salient = result.salientObjects?.first else { return }
                DispatchQueue.main.async { self?.state.subjectBox = salient.boundingBox }
            } catch { /* swallow */ }
        }
    }

    private func runFaces(pixelBuffer: CVPixelBuffer) {
        faceQ.async { [weak self] in
            let req = VNDetectFaceRectanglesRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([req])
                let boxes = (req.results ?? []).map(\.boundingBox)
                DispatchQueue.main.async { self?.state.faceBoxes = boxes }
            } catch { /* swallow */ }
        }
    }

    private func runBodyPose(pixelBuffer: CVPixelBuffer) {
        poseQ.async { [weak self] in
            let req = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([req])
                guard let obs = req.results?.first else {
                    DispatchQueue.main.async { self?.state.bodyPose = .none }
                    return
                }
                let recognized = try obs.recognizedPoints(.all)
                // Keep only joints with usable confidence; convert to image coords (origin bottom-left).
                var joints: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
                for (name, p) in recognized where p.confidence > 0.3 {
                    joints[name] = p.location
                }
                let pose = Self.derivePose(from: joints, confidence: obs.confidence)
                DispatchQueue.main.async { self?.state.bodyPose = pose }
            } catch {
                DispatchQueue.main.async { self?.state.bodyPose = .none }
            }
        }
    }

    /// Compute slant/tilt summaries from key joints. nil for any axis where source joints are missing.
    private static func derivePose(from joints: [VNHumanBodyPoseObservation.JointName: CGPoint],
                                    confidence: Float) -> BodyPose {
        func degrees(from a: CGPoint, to b: CGPoint) -> Double {
            atan2(Double(b.y - a.y), Double(b.x - a.x)) * 180.0 / .pi
        }
        // Shoulder slant: angle of line right-shoulder → left-shoulder relative to horizontal.
        // Positive value when right shoulder is higher than left.
        var shoulderSlant: Double?
        if let l = joints[.leftShoulder], let r = joints[.rightShoulder] {
            shoulderSlant = degrees(from: l, to: r)
        }
        // Spine tilt: angle of line midHip → midShoulder relative to vertical.
        var spineTilt: Double?
        if let lh = joints[.leftHip], let rh = joints[.rightHip],
           let ls = joints[.leftShoulder], let rs = joints[.rightShoulder] {
            let mh = CGPoint(x: (lh.x + rh.x) / 2, y: (lh.y + rh.y) / 2)
            let ms = CGPoint(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
            let raw = degrees(from: mh, to: ms)  // 90° = perfectly upright in image coords
            spineTilt = raw - 90.0
        }
        // Head tilt from ear-to-ear line (positive = right ear lower than left).
        var headTilt: Double?
        if let le = joints[.leftEar], let re = joints[.rightEar] {
            headTilt = degrees(from: le, to: re)
        }
        return BodyPose(
            joints: joints,
            confidence: confidence,
            shoulderSlantDegrees: shoulderSlant,
            spineTiltDegrees: spineTilt,
            headTiltDegrees: headTilt
        )
    }
}

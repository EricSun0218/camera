// app/Cue/Compose/OnDeviceCV.swift
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

    public static let none = BodyPose(joints: [:], confidence: 0)
}

public struct ComposeState: Equatable {
    public var subjectBox: CGRect?     // normalized [0,1], Vision bottom-left — noisy per-frame saliency
    public var faceBoxes: [CGRect]     // normalized, Vision bottom-left
    public var horizonDegrees: Double  // device roll relative to ground, -180..180
    public var bodyPose: BodyPose      // pose skeleton when a person is in frame
    /// The actively-TRACKED subject box (Vision bottom-left), set only while an
    /// alignment session is running. Unlike `subjectBox` this follows ONE locked
    /// subject smoothly across frames, so the alignment ball moves with the phone
    /// instead of jittering.
    public var trackedBox: CGRect?

    public static let initial = ComposeState(subjectBox: nil, faceBoxes: [],
                                              horizonDegrees: 0, bodyPose: .none,
                                              trackedBox: nil)
}

public final class OnDeviceCV: ObservableObject {
    @Published public private(set) var state: ComposeState = .initial

    private let motion = CMMotionManager()
    private let saliencyQ = DispatchQueue(label: "cue.cv.saliency", qos: .userInitiated)
    private let faceQ     = DispatchQueue(label: "cue.cv.face",     qos: .userInitiated)
    private let poseQ     = DispatchQueue(label: "cue.cv.pose",     qos: .userInitiated)
    /// Object tracking must use one serial queue (VNSequenceRequestHandler is stateful).
    private let trackQ    = DispatchQueue(label: "cue.cv.track",    qos: .userInitiated)
    private var lastSaliencyAt: TimeInterval = 0
    private var lastFaceAt: TimeInterval = 0
    private var lastPoseAt: TimeInterval = 0
    private let cvHz: TimeInterval = 1.0 / 10.0  // 10 Hz throttle

    // Tracking state — touched only on trackQ.
    private var sequenceHandler: VNSequenceRequestHandler?
    private var trackingRequest: VNTrackObjectRequest?
    private var trackingActive = false

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

    /// Feed each preview frame here. Detection is throttled to 10 Hz; object
    /// tracking (when active) runs every frame for smooth follow.
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
        runTracking(pixelBuffer: pixelBuffer)
    }

    // MARK: - Object tracking (smooth subject follow during alignment)

    /// Lock onto a subject and start tracking it. `seed` is a normalized rect in
    /// Vision coords (bottom-left origin). Call when an alignment session starts.
    public func beginTracking(seed: CGRect) {
        trackQ.async { [weak self] in
            guard let self else { return }
            let obs = VNDetectedObjectObservation(boundingBox: seed)
            let req = VNTrackObjectRequest(detectedObjectObservation: obs)
            req.trackingLevel = .accurate
            self.trackingRequest = req
            self.sequenceHandler = VNSequenceRequestHandler()
            self.trackingActive = true
            DispatchQueue.main.async { self.state.trackedBox = seed }
        }
    }

    /// Stop tracking. Idempotent — safe to call when not tracking.
    public func endTracking() {
        trackQ.async { [weak self] in
            guard let self else { return }
            self.trackingActive = false
            self.trackingRequest = nil
            self.sequenceHandler = nil
            DispatchQueue.main.async { self.state.trackedBox = nil }
        }
    }

    private func runTracking(pixelBuffer: CVPixelBuffer) {
        trackQ.async { [weak self] in
            guard let self, self.trackingActive,
                  let req = self.trackingRequest,
                  let handler = self.sequenceHandler else { return }
            do {
                try handler.perform([req], on: pixelBuffer)
                guard let obs = req.results?.first as? VNDetectedObjectObservation,
                      obs.confidence > 0.2 else { return }
                req.inputObservation = obs  // feed result back for the next frame
                let box = obs.boundingBox
                DispatchQueue.main.async {
                    guard self.trackingActive else { return }
                    // Light EMA on top of tracking for extra-silky motion.
                    if let prev = self.state.trackedBox {
                        self.state.trackedBox = Self.ema(prev, box, newWeight: 0.6)
                    } else {
                        self.state.trackedBox = box
                    }
                }
            } catch {
                // Tracking lost this frame — keep the last box, try again next frame.
            }
        }
    }

    /// Exponential moving average of two rects (`newWeight` ∈ 0...1).
    private static func ema(_ a: CGRect, _ b: CGRect, newWeight w: CGFloat) -> CGRect {
        let o = 1 - w
        return CGRect(x: a.minX * o + b.minX * w,
                      y: a.minY * o + b.minY * w,
                      width: a.width * o + b.width * w,
                      height: a.height * o + b.height * w)
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
                let pose = BodyPose(joints: joints, confidence: obs.confidence)
                DispatchQueue.main.async { self?.state.bodyPose = pose }
            } catch {
                DispatchQueue.main.async { self?.state.bodyPose = .none }
            }
        }
    }
}

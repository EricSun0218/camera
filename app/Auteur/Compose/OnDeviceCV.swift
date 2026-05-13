// app/Auteur/Compose/OnDeviceCV.swift
import Vision
import CoreMotion
import CoreImage
import Combine
import UIKit

public struct ComposeState: Equatable {
    public var subjectBox: CGRect?     // normalized to [0,1] in image coords
    public var faceBoxes: [CGRect]     // normalized
    public var horizonDegrees: Double  // device roll relative to ground, -180..180

    public static let initial = ComposeState(subjectBox: nil, faceBoxes: [], horizonDegrees: 0)
}

public final class OnDeviceCV: ObservableObject {
    @Published public private(set) var state: ComposeState = .initial

    private let motion = CMMotionManager()
    private let saliencyQ = DispatchQueue(label: "auteur.cv.saliency", qos: .userInitiated)
    private let faceQ     = DispatchQueue(label: "auteur.cv.face",     qos: .userInitiated)
    private var lastSaliencyAt: TimeInterval = 0
    private var lastFaceAt: TimeInterval = 0
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
}

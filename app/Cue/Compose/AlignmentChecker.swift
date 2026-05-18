// app/Cue/Compose/AlignmentChecker.swift
import Foundation
import CoreGraphics
import Vision

public enum SubjectKind { case person, scene }

public struct AlignmentTarget {
    public let kind: SubjectKind
    /// Target box in normalized [0..1] viewfinder space, origin TOP-LEFT
    /// (note: differs from Vision's bottom-left).
    public let box: CGRect

    public init(kind: SubjectKind, box: CGRect) {
        self.kind = kind
        self.box = box
    }
}

public enum AlignmentChecker {
    /// Alignment score 0...1 — how close the detected subject's CENTER is to the
    /// target's center. The UI shows two constant-size balls at those two centers,
    /// so alignment must be a center-distance match, NOT area IoU: two boxes can
    /// share a center but differ wildly in size, which the user can't fix (ball
    /// size is fixed) and which would keep IoU low even when the balls fully overlap.
    /// 1.0 = centers coincide; 0 = centers `maxAlignDistance` apart or further.
    public static let maxAlignDistance: Double = 0.18

    /// Joint-bounding-box height as a fraction of the true pose silhouette
    /// height. Vision's body-pose joints span roughly nose-to-ankle, shorter
    /// than the SF Symbol silhouette the pose target is sized against.
    /// 1.0 = no correction; tune on a real device.
    public static let poseHeightCalibration: Double = 1.0

    /// The live subject's size in normalized [0..1] viewfinder space, for zoom
    /// sizing. `comparable` is false when the measurement can't be matched
    /// against the AI target size (a face box vs a full-body pose height) —
    /// callers should fall back to the backend's suggested zoom in that case.
    /// Does NOT use `trackedBox`: zoom sizing happens before an alignment session.
    public static func measuredSubject(kind: SubjectKind,
                                       state: ComposeState) -> (size: CGSize, comparable: Bool)? {
        switch kind {
        case .person:
            if let pose = boundingBox(of: state.bodyPose.joints) {
                return (pose.size, true)
            } else if let face = state.faceBoxes.first {
                return (face.size, false)
            } else {
                return nil
            }
        case .scene:
            if let s = state.subjectBox {
                return (s.size, true)
            }
            return nil
        }
    }

    /// Optical zoom needed so the detected subject reaches the AI target size.
    /// Person: matched by height (with `poseHeightCalibration`). Scene: matched
    /// by area. Returns `currentOptical` unchanged when `detected` is degenerate.
    public static func neededOpticalZoom(kind: SubjectKind,
                                         targetSize: CGSize,
                                         detectedSize: CGSize,
                                         currentOptical: Double,
                                         calibration: Double = poseHeightCalibration) -> Double {
        switch kind {
        case .person:
            guard detectedSize.height > 0 else { return currentOptical }
            return currentOptical * Double(targetSize.height) * calibration
                 / Double(detectedSize.height)
        case .scene:
            let targetArea = Double(targetSize.width * targetSize.height)
            let detectedArea = Double(detectedSize.width * detectedSize.height)
            guard detectedArea > 0, targetArea > 0 else { return currentOptical }
            return currentOptical * (targetArea / detectedArea).squareRoot()
        }
    }

    public static func score(target: AlignmentTarget, state: ComposeState) -> Double {
        guard let d = detectedBox(kind: target.kind, state: state) else { return 0 }
        let dx = Double(d.midX - target.box.midX)
        let dy = Double(d.midY - target.box.midY)
        let dist = (dx * dx + dy * dy).squareRoot()
        return max(0, 1 - dist / maxAlignDistance)
    }

    /// The live subject box in normalized [0..1] TOP-LEFT viewfinder space.
    /// While an alignment session is running, this is the actively-TRACKED box
    /// (one locked subject, smooth across frames). Without tracking it falls
    /// back to per-frame detection (jittery — only used before a session locks).
    /// Returns nil when no subject is available. Same box the scorer uses, so
    /// the UI draws its center ball exactly where the scorer measures.
    public static func detectedBox(kind: SubjectKind, state: ComposeState) -> CGRect? {
        // Tracked box wins — it follows the phone smoothly.
        if let tracked = state.trackedBox {
            return visionToTopLeft(tracked)
        }
        switch kind {
        case .person:
            if let pose = boundingBox(of: state.bodyPose.joints) {
                return pose
            } else if let face = state.faceBoxes.first {
                return visionToTopLeft(face)
            } else {
                return nil
            }
        case .scene:
            return state.subjectBox.map(visionToTopLeft)
        }
    }

    private static func boundingBox(of joints: [VNHumanBodyPoseObservation.JointName: CGPoint]) -> CGRect? {
        guard !joints.isEmpty else { return nil }
        // Joints are normalized Vision points (bottom-left origin, 0..1).
        let pts = joints.values
        let minX = pts.map { $0.x }.min() ?? 0
        let maxX = pts.map { $0.x }.max() ?? 1
        let minY = pts.map { $0.y }.min() ?? 0
        let maxY = pts.map { $0.y }.max() ?? 1
        // Flip Y to top-left origin.
        let topLeftY = 1 - maxY
        return CGRect(x: minX, y: topLeftY, width: maxX - minX, height: maxY - minY)
    }

    private static func visionToTopLeft(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }

    /// Flip a normalized rect between top-left and bottom-left (Vision) origin.
    /// The transform is its own inverse, so this works both directions.
    public static func flipVertically(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }

    /// The seed box (Vision bottom-left coords) to start tracking from, derived
    /// from current detection. Falls back to a centered box if nothing detected.
    public static func trackingSeed(kind: SubjectKind, state: ComposeState) -> CGRect {
        if let tl = detectedBox(kind: kind, state: state) {
            return flipVertically(tl)  // top-left -> Vision bottom-left
        }
        // Nothing detected — lock the centre patch; it still moves with the phone.
        return CGRect(x: 0.34, y: 0.30, width: 0.32, height: 0.40)
    }
}

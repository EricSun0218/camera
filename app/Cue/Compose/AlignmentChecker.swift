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
    /// Compute IoU between detected subject and target.
    /// - For .person: use the body pose joints bounding box (or face box fallback).
    /// - For .scene: use the saliency box.
    /// Vision boxes come in normalized BOTTOM-LEFT origin; we convert.
    public static func score(target: AlignmentTarget, state: ComposeState) -> Double {
        guard let d = detectedBox(kind: target.kind, state: state) else { return 0 }
        return iou(d, target.box)
    }

    /// The live subject box in normalized [0..1] TOP-LEFT viewfinder space.
    /// While an alignment session is running, this is the actively-TRACKED box
    /// (one locked subject, smooth across frames). Without tracking it falls
    /// back to per-frame detection (jittery — only used before a session locks).
    /// Returns nil when no subject is available. Same box the scorer uses for
    /// IoU, so the UI draws exactly what the scorer measures.
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

    private static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        if inter.isNull || inter.isEmpty { return 0 }
        let ia = Double(inter.width * inter.height)
        let ua = Double(a.width * a.height) + Double(b.width * b.height) - ia
        return ua <= 0 ? 0 : ia / ua
    }
}

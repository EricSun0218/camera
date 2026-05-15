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
        let detected: CGRect?
        switch target.kind {
        case .person:
            if let pose = boundingBox(of: state.bodyPose.joints) {
                detected = pose
            } else if let face = state.faceBoxes.first {
                detected = visionToTopLeft(face)
            } else {
                detected = nil
            }
        case .scene:
            detected = state.subjectBox.map(visionToTopLeft)
        }
        guard let d = detected else { return 0 }
        return iou(d, target.box)
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

    private static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let inter = a.intersection(b)
        if inter.isNull || inter.isEmpty { return 0 }
        let ia = Double(inter.width * inter.height)
        let ua = Double(a.width * a.height) + Double(b.width * b.height) - ia
        return ua <= 0 ? 0 : ia / ua
    }
}

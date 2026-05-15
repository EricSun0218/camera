// app/Cue/Compose/CompositionOverlay.swift
import SwiftUI
import Vision

/// Always-on visual aids over the camera preview: rule-of-thirds grid, horizon line,
/// saliency box, face boxes, and body-pose skeleton. **No text banners or tips** —
/// AI guidance is surfaced via PoseOverlay / TargetFrame, not chatty captions.
public struct CompositionOverlay: View {
    let state: ComposeState
    let showGrid: Bool

    public init(state: ComposeState, showGrid: Bool = true) {
        self.state = state
        self.showGrid = showGrid
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                if showGrid { gridLines.opacity(0.35) }
                horizonLine
                if let box = state.subjectBox {
                    boundingBox(box, in: geo.size, color: .yellow)
                }
                ForEach(Array(state.faceBoxes.enumerated()), id: \.offset) { _, box in
                    boundingBox(box, in: geo.size, color: .green)
                }
                if state.bodyPose.confidence > 0.3 {
                    skeleton(in: geo.size)
                }
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 3x3 grid

    private var gridLines: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { p in
                p.move(to: CGPoint(x: w/3, y: 0));     p.addLine(to: CGPoint(x: w/3, y: h))
                p.move(to: CGPoint(x: 2*w/3, y: 0));   p.addLine(to: CGPoint(x: 2*w/3, y: h))
                p.move(to: CGPoint(x: 0, y: h/3));     p.addLine(to: CGPoint(x: w, y: h/3))
                p.move(to: CGPoint(x: 0, y: 2*h/3));   p.addLine(to: CGPoint(x: w, y: 2*h/3))
            }
            .stroke(Color.white, lineWidth: 0.5)
        }
    }

    // MARK: horizon

    private var horizonLine: some View {
        GeometryReader { geo in
            let deg = state.horizonDegrees
            // Hide if user is intentionally tilted (>30°)
            let visible = abs(deg) < 30
            Rectangle()
                .fill(abs(deg) < 1.5 ? Color.green : Color.yellow)
                .frame(width: geo.size.width * 0.5, height: 1.5)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .rotationEffect(.degrees(deg))
                .opacity(visible ? 0.8 : 0)
        }
    }

    // MARK: bbox

    private func boundingBox(_ norm: CGRect, in size: CGSize, color: Color) -> some View {
        // Vision boxes are in [0,1] with origin at bottom-left.
        let r = CGRect(
            x: norm.minX * size.width,
            y: (1 - norm.maxY) * size.height,
            width: norm.width * size.width,
            height: norm.height * size.height
        )
        return Rectangle()
            .stroke(color.opacity(0.9), lineWidth: 1.5)
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
    }

    // MARK: pose skeleton

    /// Edges to draw. Order from spec: head-shoulders-arms / spine / legs.
    private static let skeletonEdges: [(VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
        // shoulders
        (.leftShoulder, .rightShoulder),
        // arms
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        // torso
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        // legs
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
        // head connections
        (.nose, .leftEye), (.nose, .rightEye),
        (.leftEye, .leftEar), (.rightEye, .rightEar),
    ]

    private func skeleton(in size: CGSize) -> some View {
        let pose = state.bodyPose
        func uiPoint(_ p: CGPoint) -> CGPoint {
            // Vision normalized coords: origin bottom-left; flip Y for UIKit/SwiftUI.
            CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
        }
        return ZStack {
            // bones
            Path { path in
                for (a, b) in Self.skeletonEdges {
                    if let p = pose.joints[a], let q = pose.joints[b] {
                        path.move(to: uiPoint(p))
                        path.addLine(to: uiPoint(q))
                    }
                }
            }
            .stroke(Color.cyan.opacity(0.85), lineWidth: 2)
            // joint dots
            ForEach(Array(pose.joints.keys.enumerated()), id: \.offset) { _, name in
                if let p = pose.joints[name] {
                    let ui = uiPoint(p)
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 6, height: 6)
                        .position(x: ui.x, y: ui.y)
                }
            }
        }
    }
}

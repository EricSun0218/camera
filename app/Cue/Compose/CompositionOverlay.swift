// app/Cue/Compose/CompositionOverlay.swift
import SwiftUI
import Vision

public struct CompositionOverlay: View {
    let state: ComposeState
    let coachTip: CoachTip
    let showGrid: Bool

    public init(state: ComposeState, coachTip: CoachTip, showGrid: Bool = true) {
        self.state = state
        self.coachTip = coachTip
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
                    poseHints(in: geo.size)
                }
                VStack {
                    Spacer()
                    if let tip = coachTip.tip, coachTip.isWorthShowing {
                        coachBanner(tip)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.bottom, 140)
                .animation(.easeInOut(duration: 0.25), value: coachTip)
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

    /// Top-of-screen one-liner that surfaces the worst local pose finding (shoulder slant, spine tilt, head tilt).
    /// Local feedback is fast; LLM coach handles higher-level pose suggestions.
    @ViewBuilder
    private func poseHints(in size: CGSize) -> some View {
        let pose = state.bodyPose
        let issues: [String] = [
            pose.shoulderSlantDegrees.flatMap { abs($0) > 6 ? "肩膀偏斜 \(Int(abs($0)))°,放松一边" : nil },
            pose.spineTiltDegrees.flatMap    { abs($0) > 5 ? "身体微向\($0 > 0 ? "右" : "左")倾,站直一点" : nil },
            pose.headTiltDegrees.flatMap     { abs($0) > 7 ? "头微歪,正一下" : nil },
        ].compactMap { $0 }

        if let hint = issues.first {
            VStack {
                Text(hint)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Capsule())
                    .padding(.top, 80)
                Spacer()
            }
            .frame(width: size.width)
        }
    }

    // MARK: coach banner

    private func coachBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial.opacity(0.6))
            .background(Color.black.opacity(0.35))
            .clipShape(Capsule())
    }
}

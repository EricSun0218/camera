// app/Cue/Compose/CompositionOverlay.swift
import SwiftUI
import Vision

/// Always-on visual aids over the camera preview: rule-of-thirds grid, horizon line,
/// saliency box, face boxes. **No text banners or tips** — AI guidance is surfaced
/// via PoseOverlay / TargetFrame, not chatty captions.
///
/// The on-device body-pose skeleton is detected (OnDeviceCV) but no longer DRAWN:
/// the cyan stick figure was leftover passive-feedback clutter that competed with
/// the loading animation and the pose silhouette. Detection still runs because
/// AlignmentChecker needs `bodyPose.joints` for IoU.
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
}

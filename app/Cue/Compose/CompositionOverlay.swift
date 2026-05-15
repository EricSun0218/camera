// app/Cue/Compose/CompositionOverlay.swift
import SwiftUI

/// Always-on visual aids over the camera preview: rule-of-thirds grid + horizon line.
///
/// The on-device saliency box, face boxes, and body-pose skeleton are all still
/// DETECTED by OnDeviceCV (AlignmentChecker needs them for IoU scoring) but no
/// longer DRAWN here — they jittered every frame and were passive-feedback
/// clutter on the idle camera screen. While aligning, the live subject is shown
/// by AlignmentView's tracking box instead.
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

}

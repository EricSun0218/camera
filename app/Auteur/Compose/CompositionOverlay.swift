// app/Auteur/Compose/CompositionOverlay.swift
import SwiftUI

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

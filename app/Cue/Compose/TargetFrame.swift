// app/Cue/Compose/TargetFrame.swift
import SwiftUI

/// Animated reticle / dashed rectangle for SCENE mode AI guidance.
/// Color reflects live IoU alignment with the detected subject:
///   white  (alignment < 0.5)
///   yellow (0.5 ≤ alignment < 0.85)
///   green  (alignment ≥ 0.85) with pulse animation
public struct TargetFrame: View {
    /// Target rect in normalized 0..1 top-left coords.
    public let target: CGRect
    /// 0..1 alignment score, drives color + pulse.
    public let alignment: Double

    @State private var phase: CGFloat = 0
    @State private var pulse: Double = 1.0

    public init(target: CGRect, alignment: Double) {
        self.target = target
        self.alignment = alignment
    }

    private var color: Color {
        if alignment >= 0.85 { return .green }
        if alignment >= 0.5  { return .yellow }
        return .white
    }

    public var body: some View {
        GeometryReader { geo in
            let r = CGRect(
                x: target.minX * geo.size.width,
                y: target.minY * geo.size.height,
                width: target.width * geo.size.width,
                height: target.height * geo.size.height
            )
            ZStack {
                // dashed border, animated march
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(color.opacity(0.9),
                            style: StrokeStyle(lineWidth: 2.5, dash: [10, 6], dashPhase: phase))
                // 4 corner brackets, slightly thicker, pull eye to the frame
                cornerBrackets(in: r, color: color)
            }
            .frame(width: r.width, height: r.height)
            .position(x: r.midX, y: r.midY)
            .shadow(color: color.opacity(0.6), radius: alignment >= 0.85 ? 14 : 4)
            .scaleEffect(alignment >= 0.85 ? pulse : 1.0)
            .onAppear {
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    phase = -16
                }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    pulse = 1.04
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func cornerBrackets(in r: CGRect, color: Color) -> some View {
        let bracketLen: CGFloat = min(28, min(r.width, r.height) * 0.18)
        return Path { p in
            // top-left
            p.move(to: CGPoint(x: 0, y: bracketLen)); p.addLine(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: bracketLen, y: 0))
            // top-right
            p.move(to: CGPoint(x: r.width - bracketLen, y: 0)); p.addLine(to: CGPoint(x: r.width, y: 0)); p.addLine(to: CGPoint(x: r.width, y: bracketLen))
            // bottom-right
            p.move(to: CGPoint(x: r.width, y: r.height - bracketLen)); p.addLine(to: CGPoint(x: r.width, y: r.height)); p.addLine(to: CGPoint(x: r.width - bracketLen, y: r.height))
            // bottom-left
            p.move(to: CGPoint(x: bracketLen, y: r.height)); p.addLine(to: CGPoint(x: 0, y: r.height)); p.addLine(to: CGPoint(x: 0, y: r.height - bracketLen))
        }
        .stroke(color, lineWidth: 3)
    }
}

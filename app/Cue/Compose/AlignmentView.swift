import SwiftUI

/// Two-ball alignment guide shown while aligning.
/// - target ball: AI-placed, screen-fixed (does NOT move with the phone),
///   colored by `alignment`.
/// - current ball: the live-detected subject's center, moves as the phone moves.
/// An arrow between the two balls shows which way to move the phone so the
/// current ball lands on the target ball. Ball size is constant.
public struct AlignmentView: View {
    public let target: CGRect          // normalized 0..1, top-left
    public let current: CGRect?        // normalized 0..1, top-left; nil if no subject detected
    public let alignment: Double       // 0..1

    @State private var pulse: Double = 1.0
    @State private var arrowPhase: CGFloat = 0

    /// Fixed ball diameter in points — never scales with the subject.
    private let ballSize: CGFloat = 26

    public init(target: CGRect, current: CGRect?, alignment: Double) {
        self.target = target
        self.current = current
        self.alignment = alignment
    }

    /// Green at the 0.65 auto-shutter threshold.
    private var targetColor: Color {
        if alignment >= 0.65 { return .green }
        if alignment >= 0.4  { return .yellow }
        return .white
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let targetPt = centerPoint(of: target, in: size)
            let currentPt = current.map { centerPoint(of: $0, in: size) }
            let aligned = alignment >= 0.65

            ZStack {
                // Arrow from current ball → target ball (only when not yet aligned
                // and a subject is detected).
                if let c = currentPt, !aligned {
                    arrow(from: c, to: targetPt)
                }

                // Target ball — screen-fixed, colored, pulses when aligned.
                ball(color: targetColor, filled: false)
                    .scaleEffect(aligned ? pulse : 1.0)
                    .shadow(color: targetColor.opacity(0.8), radius: aligned ? 12 : 5)
                    .position(targetPt)

                // Current ball — tracks the detected subject, white.
                if let c = currentPt {
                    ball(color: .white, filled: true)
                        .shadow(color: .black.opacity(0.5), radius: 3)
                        .position(c)
                        .animation(.easeOut(duration: 0.15), value: c)
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                pulse = 1.18
            }
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                arrowPhase = -14
            }
        }
    }

    // MARK: - Pieces

    /// A constant-size ball. `filled` = solid dot, else a ring.
    private func ball(color: Color, filled: Bool) -> some View {
        Group {
            if filled {
                Circle()
                    .fill(color)
                    .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 1))
            } else {
                ZStack {
                    Circle().stroke(color, lineWidth: 3)
                    Circle().fill(color.opacity(0.18))
                }
            }
        }
        .frame(width: ballSize, height: ballSize)
    }

    /// A dashed line from `a` to `b` with an arrowhead at `b`, marching toward the target.
    private func arrow(from a: CGPoint, to b: CGPoint) -> some View {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let dist = max(1, hypot(dx, dy))
        let ux = dx / dist, uy = dy / dist
        // Trim the line so it starts/ends at each ball's edge, not its center.
        let pad = ballSize / 2 + 4
        let start = CGPoint(x: a.x + ux * pad, y: a.y + uy * pad)
        let end   = CGPoint(x: b.x - ux * pad, y: b.y - uy * pad)
        // Only draw if the balls are far enough apart to leave a visible shaft.
        let visible = dist > pad * 2 + 10
        let head: CGFloat = 9

        return ZStack {
            if visible {
                Path { p in
                    p.move(to: start)
                    p.addLine(to: end)
                }
                .stroke(.white.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round,
                                           dash: [7, 5], dashPhase: arrowPhase))
                // arrowhead at `end`
                Path { p in
                    let nx = -uy, ny = ux  // perpendicular
                    p.move(to: end)
                    p.addLine(to: CGPoint(x: end.x - ux * head + nx * head * 0.6,
                                          y: end.y - uy * head + ny * head * 0.6))
                    p.move(to: end)
                    p.addLine(to: CGPoint(x: end.x - ux * head - nx * head * 0.6,
                                          y: end.y - uy * head - ny * head * 0.6))
                }
                .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
    }

    private func centerPoint(of norm: CGRect, in size: CGSize) -> CGPoint {
        CGPoint(x: norm.midX * size.width, y: norm.midY * size.height)
    }
}

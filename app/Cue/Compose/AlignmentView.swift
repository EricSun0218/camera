import SwiftUI

/// Two-box alignment guide shown while aligning:
/// - target: AI-placed, screen-fixed, colored by `alignment`
/// - current: live detected subject, white dashed, moves with the phone
public struct AlignmentView: View {
    public let target: CGRect          // normalized 0..1, top-left
    public let current: CGRect?        // normalized 0..1, top-left; nil if no subject detected
    public let alignment: Double       // 0..1

    @State private var pulse: Double = 1.0
    @State private var dash: CGFloat = 0

    public init(target: CGRect, current: CGRect?, alignment: Double) {
        self.target = target; self.current = current; self.alignment = alignment
    }

    private var targetColor: Color {
        if alignment >= 0.85 { return .green }
        if alignment >= 0.5  { return .yellow }
        return .white
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // current subject box — white dashed, marching
                if let c = current {
                    bracketRect(c, in: geo.size, color: .white.opacity(0.9),
                                lineWidth: 2, dashed: true)
                }
                // target box — colored, solid, brackets, pulses when aligned
                bracketRect(target, in: geo.size, color: targetColor,
                            lineWidth: 3, dashed: false)
                    .scaleEffect(alignment >= 0.85 ? pulse : 1.0)
                    .shadow(color: targetColor.opacity(0.7),
                            radius: alignment >= 0.85 ? 14 : 5)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { pulse = 1.05 }
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { dash = -16 }
        }
    }

    /// Draw a rect as 4 corner brackets.
    private func bracketRect(_ norm: CGRect, in size: CGSize, color: Color,
                             lineWidth: CGFloat, dashed: Bool) -> some View {
        let r = CGRect(x: norm.minX * size.width, y: norm.minY * size.height,
                       width: norm.width * size.width, height: norm.height * size.height)
        let bracket = min(26, min(r.width, r.height) * 0.22)
        return Path { p in
            // TL
            p.move(to: CGPoint(x: r.minX, y: r.minY + bracket)); p.addLine(to: CGPoint(x: r.minX, y: r.minY)); p.addLine(to: CGPoint(x: r.minX + bracket, y: r.minY))
            // TR
            p.move(to: CGPoint(x: r.maxX - bracket, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.minY + bracket))
            // BR
            p.move(to: CGPoint(x: r.maxX, y: r.maxY - bracket)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - bracket, y: r.maxY))
            // BL
            p.move(to: CGPoint(x: r.minX + bracket, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - bracket))
        }
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round,
                                          dash: dashed ? [9, 6] : [], dashPhase: dashed ? dash : 0))
    }
}

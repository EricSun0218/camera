// app/Cue/Compose/PoseOverlay.swift
import SwiftUI

/// Renders a translucent pose silhouette on top of the camera preview.
/// **Non-interactive by design** — the LLM picks the pose AND its on-screen
/// placement (composition-aware: rule of thirds, headroom, negative space).
/// The silhouette is screen-fixed, so as the user moves the phone, the real subject
/// in frame can be aligned with the outline.
///
/// Color reflects live IoU alignment with the detected subject:
///   white  (alignment < 0.5)   – far from target
///   yellow (0.5 ≤ alignment < 0.85) – close
///   green  (alignment ≥ 0.85)  – locked in, pulses
public struct PoseOverlay: View {
    public let template: PoseTemplate
    /// Normalized 0..1 horizontal screen position of the silhouette CENTER.
    public let positionX: Double
    /// Normalized 0..1 vertical screen position of the silhouette CENTER.
    public let positionY: Double
    /// Silhouette height as fraction of viewfinder height (0.3..0.95).
    public let heightFraction: Double
    /// 0..1 alignment score from AlignmentChecker.
    public let alignment: Double

    @State private var pulse: Double = 1.0

    public init(template: PoseTemplate,
                positionX: Double = 0.5,
                positionY: Double = 0.55,
                heightFraction: Double = 0.72,
                alignment: Double = 0) {
        self.template = template
        self.positionX = positionX
        self.positionY = positionY
        self.heightFraction = heightFraction
        self.alignment = alignment
    }

    private var color: Color {
        if alignment >= 0.85 { return .green }
        if alignment >= 0.5  { return .yellow }
        return .white
    }

    public var body: some View {
        GeometryReader { geo in
            let height = geo.size.height * CGFloat(heightFraction)
            let width  = height / template.aspect
            let cx = geo.size.width  * CGFloat(positionX)
            let cy = geo.size.height * CGFloat(positionY)

            Image(systemName: template.symbolName)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(color)
                .frame(width: width, height: height)
                .shadow(color: color.opacity(0.9), radius: 8)
                .shadow(color: color.opacity(0.55), radius: 18)
                .opacity(0.65)
                .scaleEffect(alignment >= 0.85 ? pulse : 1.0)
                .position(x: cx, y: cy)
                .animation(.easeInOut(duration: 0.35), value: color)
                .animation(.easeInOut(duration: 0.35), value: cx)
                .animation(.easeInOut(duration: 0.35), value: cy)
                .animation(.easeInOut(duration: 0.35), value: height)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                        pulse = 1.06
                    }
                }
        }
        .allowsHitTesting(false)
    }
}

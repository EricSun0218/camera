// app/Auteur/Compose/PoseOverlay.swift
import SwiftUI

/// Renders a translucent pose silhouette on top of the camera preview.
/// **Non-interactive by design** — the LLM Coach picks the pose AND its on-screen
/// placement (composition-aware: rule of thirds, headroom, negative space).
/// The silhouette is screen-fixed, so as the user moves the phone, the real subject
/// in frame can be aligned with the outline — pose and composition guided together.
public struct PoseOverlay: View {
    public let template: PoseTemplate
    /// Normalized 0..1 horizontal screen position of the silhouette CENTER.
    public let positionX: Double
    /// Normalized 0..1 vertical screen position of the silhouette CENTER.
    public let positionY: Double
    /// Silhouette height as fraction of viewfinder height (0.3..0.95).
    public let heightFraction: Double

    private let opacity: Double = 0.55

    public init(template: PoseTemplate,
                positionX: Double = 0.5,
                positionY: Double = 0.55,
                heightFraction: Double = 0.72) {
        self.template = template
        self.positionX = positionX
        self.positionY = positionY
        self.heightFraction = heightFraction
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
                .foregroundStyle(Color.white)
                .frame(width: width, height: height)
                .shadow(color: .white.opacity(0.85), radius: 6)
                .shadow(color: .white.opacity(0.45), radius: 14)
                .opacity(opacity)
                .position(x: cx, y: cy)
                .animation(.easeInOut(duration: 0.35), value: cx)
                .animation(.easeInOut(duration: 0.35), value: cy)
                .animation(.easeInOut(duration: 0.35), value: height)
        }
        .allowsHitTesting(false)
    }
}

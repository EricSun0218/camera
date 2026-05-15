// app/Cue/Views/LoadingOverlay.swift
import SwiftUI

/// Loading animation overlaid on the live preview while the AI guidance
/// request is in flight. Runs as long as needed; no fixed duration.
public struct LoadingOverlay: View {
    @State private var rotateOuter: Double = 0
    @State private var rotateInner: Double = 0
    @State private var scanY: CGFloat = 0
    @State private var dotsCount = 1

    public init() {}

    public var body: some View {
        ZStack {
            // 0. subtle dim over the live preview
            Color.black.opacity(0.18).ignoresSafeArea()

            // 1. corner brackets sweep
            GeometryReader { geo in
                Rectangle()
                    .stroke(LinearGradient(colors: [.cyan.opacity(0), .cyan, .cyan.opacity(0)],
                                            startPoint: .top, endPoint: .bottom),
                            lineWidth: 2)
                    .blur(radius: 0.6)
                    .opacity(0.8)
                    .mask(
                        Rectangle()
                            .frame(height: 90)
                            .offset(y: scanY)
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .onAppear {
                        scanY = -geo.size.height / 2
                        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                            scanY = geo.size.height / 2
                        }
                    }
            }

            // 2. concentric dashed rings + center pulse
            VStack(spacing: 22) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.85),
                                style: StrokeStyle(lineWidth: 2.5, dash: [4, 8]))
                        .frame(width: 112, height: 112)
                        .rotationEffect(.degrees(rotateOuter))
                        .shadow(color: .white.opacity(0.5), radius: 6)
                    Circle()
                        .stroke(Color.cyan.opacity(0.9),
                                style: StrokeStyle(lineWidth: 2, dash: [3, 6]))
                        .frame(width: 76, height: 76)
                        .rotationEffect(.degrees(rotateInner))
                        .shadow(color: .cyan.opacity(0.6), radius: 6)
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.white)
                        .shadow(color: .white.opacity(0.7), radius: 6)
                }

                Text("Cue 正在为你构图\(String(repeating: ".", count: dotsCount))")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .shadow(color: .black.opacity(0.6), radius: 4)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 3.4).repeatForever(autoreverses: false)) {
                rotateOuter = 360
            }
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                rotateInner = -360
            }
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 380_000_000)
                    await MainActor.run { dotsCount = (dotsCount % 3) + 1 }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

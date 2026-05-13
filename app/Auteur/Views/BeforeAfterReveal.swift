// app/Auteur/Views/BeforeAfterReveal.swift
import SwiftUI

public struct BeforeAfterReveal: View {
    let before: CGImage
    let after: CGImage
    @State private var revealed = false

    public init(before: CGImage, after: CGImage) {
        self.before = before
        self.after = after
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(decorative: before, scale: 1, orientation: .up)
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                Image(decorative: after, scale: 1, orientation: .up)
                    .resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .mask(
                        Rectangle()
                            .frame(width: revealed ? geo.size.width : 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )
            }
            .overlay(alignment: .top) {
                Text(revealed ? "after" : "before").font(.caption.weight(.medium))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.black.opacity(0.5)).clipShape(Capsule())
                    .foregroundStyle(.white)
                    .padding(.top, 60)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.0).delay(0.2)) {
                    revealed = true
                }
            }
        }
    }
}

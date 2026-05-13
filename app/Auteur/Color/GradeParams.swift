// app/Auteur/Color/GradeParams.swift
import Foundation

public struct HSLBand: Codable, Equatable, Sendable {
    public var hue: Double         // -30 ... +30
    public var saturation: Double  // -100 ... +100
    public var luminance: Double   // -100 ... +100

    public static let zero = HSLBand(hue: 0, saturation: 0, luminance: 0)
}

public struct HSLBands: Codable, Equatable, Sendable {
    public var red: HSLBand
    public var orange: HSLBand
    public var yellow: HSLBand
    public var green: HSLBand
    public var aqua: HSLBand
    public var blue: HSLBand
    public var purple: HSLBand
    public var magenta: HSLBand

    public static let zero = HSLBands(
        red: .zero, orange: .zero, yellow: .zero, green: .zero,
        aqua: .zero, blue: .zero, purple: .zero, magenta: .zero
    )
}

public struct GradeParams: Codable, Equatable, Sendable {
    public var exposure_ev: Double       // -2 ... +2
    public var contrast: Double          // -50 ... +50
    public var highlights: Double        // -100 ... +100
    public var shadows: Double           // -100 ... +100
    public var whites: Double
    public var blacks: Double
    public var saturation: Double        // -100 ... +100
    public var vibrance: Double          // -100 ... +100
    public var temperature: Double       // -100 ... +100
    public var tint: Double              // -100 ... +100
    public var hsl: HSLBands
    public var vignette_intensity: Double  // 0 ... 1
    public var vignette_radius: Double     // 0.5 ... 2

    public static let neutral = GradeParams(
        exposure_ev: 0, contrast: 0,
        highlights: 0, shadows: 0, whites: 0, blacks: 0,
        saturation: 0, vibrance: 0,
        temperature: 0, tint: 0,
        hsl: .zero,
        vignette_intensity: 0, vignette_radius: 1
    )

    /// Defensive clamp — backend already validates, but never trust the wire.
    public func clamped() -> GradeParams {
        var g = self
        g.exposure_ev       = g.exposure_ev.clamped(-2, 2)
        g.contrast          = g.contrast.clamped(-50, 50)
        g.highlights        = g.highlights.clamped(-100, 100)
        g.shadows           = g.shadows.clamped(-100, 100)
        g.whites            = g.whites.clamped(-100, 100)
        g.blacks            = g.blacks.clamped(-100, 100)
        g.saturation        = g.saturation.clamped(-100, 100)
        g.vibrance          = g.vibrance.clamped(-100, 100)
        g.temperature       = g.temperature.clamped(-100, 100)
        g.tint              = g.tint.clamped(-100, 100)
        g.vignette_intensity = g.vignette_intensity.clamped(0, 1)
        g.vignette_radius   = g.vignette_radius.clamped(0.5, 2)
        g.hsl = HSLBands(
            red: g.hsl.red.clamped(), orange: g.hsl.orange.clamped(),
            yellow: g.hsl.yellow.clamped(), green: g.hsl.green.clamped(),
            aqua: g.hsl.aqua.clamped(), blue: g.hsl.blue.clamped(),
            purple: g.hsl.purple.clamped(), magenta: g.hsl.magenta.clamped()
        )
        return g
    }
}

private extension HSLBand {
    func clamped() -> HSLBand {
        HSLBand(
            hue: hue.clamped(-30, 30),
            saturation: saturation.clamped(-100, 100),
            luminance: luminance.clamped(-100, 100)
        )
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { min(max(self, lo), hi) }
}

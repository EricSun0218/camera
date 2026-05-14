// app/Cue/Color/CIPipeline.swift
import CoreImage
import CoreImage.CIFilterBuiltins

public enum CIPipeline {

    /// Apply a GradeParams in spec-defined order. Returns a CIImage backed by GPU ops.
    public static func apply(_ raw: GradeParams, to input: CIImage) -> CIImage {
        let p = raw.clamped()
        var img = input

        // 1. Exposure
        if p.exposure_ev != 0 {
            let f = CIFilter.exposureAdjust()
            f.inputImage = img
            f.ev = Float(p.exposure_ev)
            img = f.outputImage ?? img
        }

        // 2. Highlights / Shadows
        if p.highlights != 0 || p.shadows != 0 {
            let f = CIFilter.highlightShadowAdjust()
            f.inputImage = img
            f.highlightAmount = Float(1.0 + p.highlights / 100.0 * -0.5) // negative pulls down
            f.shadowAmount    = Float(p.shadows / 100.0 * 0.6)           // positive lifts
            img = f.outputImage ?? img
        }

        // 3. Whites/Blacks/Contrast via tone curve
        let toneCurve = makeToneCurve(whites: p.whites, blacks: p.blacks, contrast: p.contrast)
        if let curve = toneCurve {
            let f = CIFilter.toneCurve()
            f.inputImage = img
            f.point0 = curve.p0
            f.point1 = curve.p1
            f.point2 = curve.p2
            f.point3 = curve.p3
            f.point4 = curve.p4
            img = f.outputImage ?? img
        }

        // 4. Temperature / Tint
        if p.temperature != 0 || p.tint != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = img
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(
                x: 6500 + p.temperature * 20,    // ±2000K range
                y: p.tint * 0.5                  // ±50
            )
            img = f.outputImage ?? img
        }

        // 5. Saturation (global)
        if p.saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = img
            f.saturation = Float(1.0 + p.saturation / 100.0)
            img = f.outputImage ?? img
        }

        // 6. Vibrance
        if p.vibrance != 0 {
            let f = CIFilter.vibrance()
            f.inputImage = img
            f.amount = Float(p.vibrance / 100.0)
            img = f.outputImage ?? img
        }

        // 7. HSL per band
        if hasAnyHSL(p.hsl) {
            img = HSLKernel.apply(to: img, hsl: p.hsl)
        }

        // 8. Vignette
        if p.vignette_intensity > 0 {
            let f = CIFilter.vignetteEffect()
            f.inputImage = img
            f.intensity = Float(p.vignette_intensity)
            f.radius    = Float(p.vignette_radius * Double(min(img.extent.width, img.extent.height)) * 0.5)
            f.center    = CGPoint(x: img.extent.midX, y: img.extent.midY)
            img = f.outputImage ?? img
        }

        return img
    }

    // MARK: - Tone curve

    private struct ToneCurve {
        let p0: CGPoint
        let p1: CGPoint
        let p2: CGPoint
        let p3: CGPoint
        let p4: CGPoint
    }

    private static func makeToneCurve(whites: Double, blacks: Double, contrast: Double) -> ToneCurve? {
        if whites == 0 && blacks == 0 && contrast == 0 { return nil }
        // Endpoints
        let x0: CGFloat = max(0, CGFloat(-blacks / 100.0 * 0.25))      // blacks raises floor or pushes down
        let y0: CGFloat = blacks >= 0 ? 0 : CGFloat(-blacks / 100.0 * 0.15)
        let x4: CGFloat = min(1, 1 + CGFloat(whites / 100.0 * 0.15))
        let y4: CGFloat = whites >= 0 ? 1 : 1 + CGFloat(whites / 100.0 * 0.25)

        // S-curve from contrast: pull 0.25 down, push 0.75 up
        let c = CGFloat(contrast / 100.0) * 0.20
        let p1 = CGPoint(x: 0.25, y: max(0, 0.25 - c))
        let p2 = CGPoint(x: 0.5, y: 0.5)
        let p3 = CGPoint(x: 0.75, y: min(1, 0.75 + c))

        return ToneCurve(
            p0: CGPoint(x: x0, y: y0),
            p1: p1, p2: p2, p3: p3,
            p4: CGPoint(x: x4, y: y4)
        )
    }

    private static func hasAnyHSL(_ b: HSLBands) -> Bool {
        let all: [HSLBand] = [b.red, b.orange, b.yellow, b.green, b.aqua, b.blue, b.purple, b.magenta]
        return all.contains { $0.hue != 0 || $0.saturation != 0 || $0.luminance != 0 }
    }
}

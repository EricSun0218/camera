// app/Cue/Color/HSLColorCube.swift
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// Per-band HSL adjustment via a CPU-computed 3D color LUT fed to the stock
/// `CIColorCube` filter.
///
/// This replaces the old custom Metal CI kernel (`HSLKernel.ci.metal`). A
/// Core Image Metal kernel must be compiled + linked with `-fcikernel` and
/// loaded from a metallib at runtime — fragile across xcodegen regen and
/// Xcode incremental builds, and it broke repeatedly ("Function 'hslAdjust'
/// does not exist"). `CIColorCube` is a built-in filter that always exists;
/// the LUT is plain Swift math. Nothing to compile, nothing to load, nothing
/// to break.
public enum HSLColorCube {

    /// 8 hue band centers, normalized 0...1 (red, orange, yellow, green,
    /// aqua, blue, purple, magenta).
    private static let bandCenters: [Double] = [
        0.0, 0.0833, 0.1667, 0.3333, 0.5, 0.6667, 0.75, 0.8333,
    ]
    /// Triangular band half-width — 8 bands evenly overlapping.
    private static let halfWidth = 1.0 / 16.0
    /// LUT resolution per axis. 48³ ≈ 110k cells — smooth, computes in well
    /// under 100 ms, and the grade already runs on a detached task.
    private static let dim = 48

    /// Apply HSL bands to an image by building a color cube LUT.
    public static func apply(to image: CIImage, hsl: HSLBands) -> CIImage {
        let bands = [hsl.red, hsl.orange, hsl.yellow, hsl.green,
                     hsl.aqua, hsl.blue, hsl.purple, hsl.magenta]
        // Map UI ranges to native ranges (matches the old kernel's packing):
        //   hue -30..+30 deg -> normalized hue shift   (/360)
        //   saturation -100..+100 -> multiplier delta  (/100)
        //   luminance -100..+100 -> additive lightness (*0.0025)
        let dHue = bands.map { $0.hue / 360.0 }
        let dSat = bands.map { $0.saturation / 100.0 }
        let dLum = bands.map { $0.luminance * 0.0025 }

        let d = dim
        var data = [Float](repeating: 0, count: d * d * d * 4)
        var i = 0
        for bi in 0..<d {
            let b = Double(bi) / Double(d - 1)
            for gi in 0..<d {
                let g = Double(gi) / Double(d - 1)
                for ri in 0..<d {
                    let r = Double(ri) / Double(d - 1)
                    let out = adjusted(r: r, g: g, b: b, dHue: dHue, dSat: dSat, dLum: dLum)
                    data[i]     = Float(out.0)
                    data[i + 1] = Float(out.1)
                    data[i + 2] = Float(out.2)
                    data[i + 3] = 1
                    i += 4
                }
            }
        }

        let cube = CIFilter.colorCube()
        cube.inputImage = image
        cube.cubeDimension = Float(d)
        cube.cubeData = data.withUnsafeBufferPointer { Data(buffer: $0) }
        return cube.outputImage ?? image
    }

    // MARK: - Per-pixel HSL math

    private static func adjusted(r: Double, g: Double, b: Double,
                                 dHue: [Double], dSat: [Double], dLum: [Double]) -> (Double, Double, Double) {
        var hsl = rgbToHSL(r: r, g: g, b: b)
        var dh = 0.0, ds = 0.0, dl = 0.0
        for i in 0..<8 {
            let w = bandWeight(hue: hsl.h, band: i)
            if w > 0 {
                dh += w * dHue[i]
                ds += w * dSat[i]
                dl += w * dLum[i]
            }
        }
        hsl.h = fract(hsl.h + dh)
        hsl.s = clamp01(hsl.s * (1.0 + ds))
        hsl.l = clamp01(hsl.l + dl)
        return hslToRGB(h: hsl.h, s: hsl.s, l: hsl.l)
    }

    private static func bandWeight(hue h: Double, band idx: Int) -> Double {
        let c = bandCenters[idx]
        var dist = abs(h - c)
        dist = min(dist, 1.0 - dist)  // wrap around the hue circle
        return clamp01(1.0 - dist / halfWidth)
    }

    private static func rgbToHSL(r: Double, g: Double, b: Double) -> (h: Double, s: Double, l: Double) {
        let maxc = max(r, max(g, b))
        let minc = min(r, min(g, b))
        let l = (maxc + minc) * 0.5
        let delta = maxc - minc
        guard delta > 1e-9 else { return (0, 0, l) }
        let s = l > 0.5 ? delta / (2.0 - maxc - minc) : delta / (maxc + minc)
        var h: Double
        if maxc == r {
            h = (g - b) / delta + (g < b ? 6.0 : 0.0)
        } else if maxc == g {
            h = (b - r) / delta + 2.0
        } else {
            h = (r - g) / delta + 4.0
        }
        h /= 6.0
        return (h, s, l)
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> (Double, Double, Double) {
        guard s > 1e-9 else { return (l, l, l) }
        let q = l < 0.5 ? l * (1.0 + s) : l + s - l * s
        let p = 2.0 * l - q
        return (hue2rgb(p, q, h + 1.0 / 3.0),
                hue2rgb(p, q, h),
                hue2rgb(p, q, h - 1.0 / 3.0))
    }

    private static func hue2rgb(_ p: Double, _ q: Double, _ t0: Double) -> Double {
        var t = t0
        if t < 0 { t += 1 }
        if t > 1 { t -= 1 }
        if t < 1.0 / 6.0 { return p + (q - p) * 6.0 * t }
        if t < 1.0 / 2.0 { return q }
        if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6.0 }
        return p
    }

    private static func fract(_ x: Double) -> Double { x - floor(x) }
    private static func clamp01(_ x: Double) -> Double { min(1.0, max(0.0, x)) }
}

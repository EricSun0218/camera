// app/Cue/Color/HSLKernel.swift
import CoreImage
import Foundation

public enum HSLKernel {
    /// Singleton kernel, loaded lazily from the .ci.metal blob.
    public static let kernel: CIColorKernel = {
        let url = Bundle.main.url(forResource: "HSLKernel.ci", withExtension: "metallib")
            ?? Bundle.main.url(forResource: "default.metallib", withExtension: nil)!
        let data = try! Data(contentsOf: url)
        return try! CIColorKernel(functionName: "hslAdjust", fromMetalLibraryData: data)
    }()

    /// Apply HSL bands to an image.
    public static func apply(to image: CIImage, hsl: HSLBands) -> CIImage {
        // Map UI ranges to kernel-native ranges.
        //   hue:        -30..+30 degrees → -30/360..+30/360 (normalized hue shift)
        //   saturation: -100..+100 → -1..+1 (multiplier delta)
        //   luminance:  -100..+100 → -0.25..+0.25 (additive)
        func pack(_ b: HSLBand) -> (Double, Double, Double) {
            (b.hue / 360.0, b.saturation / 100.0, b.luminance * 0.0025)
        }
        let bands = [hsl.red, hsl.orange, hsl.yellow, hsl.green,
                     hsl.aqua, hsl.blue, hsl.purple, hsl.magenta]
        let args: [CGFloat] = bands.flatMap { b -> [CGFloat] in
            let (h, s, l) = pack(b)
            return [CGFloat(h), CGFloat(s), CGFloat(l)]
        }
        return kernel.apply(extent: image.extent, arguments: [image] + args.map { $0 as Any }) ?? image
    }
}

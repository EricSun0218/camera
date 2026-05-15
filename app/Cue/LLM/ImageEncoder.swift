// app/Cue/LLM/ImageEncoder.swift
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import UIKit

public enum ImageEncoder {

    /// Downsample a CIImage so longer side = `maxSide`, encode JPEG at `quality`,
    /// return base64 string (no data URL prefix).
    public static func downsampledBase64(from image: CIImage, maxSide: CGFloat, quality: CGFloat) -> String? {
        let extent = image.extent
        let longSide = max(extent.width, extent.height)
        let scale = min(1.0, maxSide / longSide)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cg = SharedCI.context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(dest, cg, [
            kCGImageDestinationLossyCompressionQuality: quality
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (data as Data).base64EncodedString()
    }

    /// Convenience overload for a CVPixelBuffer (preview frame).
    public static func downsampledBase64(from pixelBuffer: CVPixelBuffer, maxSide: CGFloat, quality: CGFloat) -> String? {
        downsampledBase64(from: CIImage(cvPixelBuffer: pixelBuffer), maxSide: maxSide, quality: quality)
    }
}

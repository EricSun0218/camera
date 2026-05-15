// app/Cue/Color/SharedCI.swift
import CoreImage

/// One process-wide Core Image context. CIContext creation is expensive —
/// never create one per render call.
public enum SharedCI {
    public static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Render a CIImage to a CGImage using the shared context.
    public static func cgImage(from image: CIImage) -> CGImage? {
        context.createCGImage(image, from: image.extent)
    }
}

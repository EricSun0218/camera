// app/Cue/Color/PhotoRenderer.swift
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Photos
import UIKit

public enum PhotoRendererError: Error {
    case cgImageFailed
    case jpegEncodeFailed
    case photoLibraryDenied
    case saveFailed(Error)
}

public final class PhotoRenderer {
    /// Process-wide shared Core Image context (CIContext creation is expensive).
    private var context: CIContext { SharedCI.context }

    public init() {}

    /// Render a CIImage to a JPEG `Data`.
    public func renderToJPEG(_ image: CIImage, quality: CGFloat = 0.92) throws -> Data {
        guard let cg = context.createCGImage(image, from: image.extent) else {
            throw PhotoRendererError.cgImageFailed
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            throw PhotoRendererError.jpegEncodeFailed
        }
        let opts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, cg, opts as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw PhotoRendererError.jpegEncodeFailed
        }
        return data as Data
    }

    /// Save a JPEG to the user's Photos library.
    public func saveToPhotoLibrary(_ jpeg: Data) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited: break
        case .denied, .restricted: throw PhotoRendererError.photoLibraryDenied
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if granted != .authorized && granted != .limited {
                throw PhotoRendererError.photoLibraryDenied
            }
        @unknown default: throw PhotoRendererError.photoLibraryDenied
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: jpeg, options: nil)
            }
        } catch {
            throw PhotoRendererError.saveFailed(error)
        }
    }
}

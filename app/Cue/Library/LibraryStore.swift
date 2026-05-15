import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Photos
import os

public enum LibraryStoreError: Error {
    case jpegEncodeFailed
    case imageLoadFailed
    case photoLibraryDenied
    case saveFailed(Error)
}

/// In-app photo library. Captures land here (not the Camera Roll); from the
/// library a photo can be re-graded and exported out to Photos.
///
/// Persists to `Documents/CueLibrary/`:
/// - JPEG image files (`<uuid>_orig.jpg`, `<uuid>_v<n>.jpg`)
/// - metadata in `manifest.json` (`[LibraryItem]`)
@MainActor
public final class LibraryStore: ObservableObject {
    /// Newest first.
    @Published public private(set) var items: [LibraryItem] = []

    private static let log = Logger(subsystem: "com.ericsun.cue", category: "library")
    private let dir: URL
    private let manifestURL: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.dir = docs.appendingPathComponent("CueLibrary", isDirectory: true)
        self.manifestURL = dir.appendingPathComponent("manifest.json")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        loadManifest()
    }

    // MARK: - Manifest

    private func loadManifest() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? decoder.decode([LibraryItem].self, from: data) else {
            items = []
            return
        }
        items = decoded
    }

    private func saveManifest() {
        do {
            let data = try encoder.encode(items)
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            Self.log.error("saveManifest failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - File IO

    public func libraryURL(_ name: String) -> URL {
        dir.appendingPathComponent(name)
    }

    private func writeJPEG(_ cg: CGImage, to filename: String) {
        let url = libraryURL(filename)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            Self.log.error("writeJPEG: destination create failed")
            return
        }
        CGImageDestinationAddImage(dest, cg, [
            kCGImageDestinationLossyCompressionQuality: 0.92
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            Self.log.error("writeJPEG: finalize failed for \(filename, privacy: .public)")
            return
        }
        do {
            try (data as Data).write(to: url, options: .atomic)
        } catch {
            Self.log.error("writeJPEG: disk write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func loadImage(_ filename: String) -> CGImage? {
        let url = libraryURL(filename)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    // MARK: - Mutations

    /// Persist a new capture: original + first graded variant. Returns the item id.
    @discardableResult
    public func addCapture(original: CGImage, graded: CGImage, analysis: SceneAnalysis) -> UUID {
        let id = UUID()
        let now = Date()
        let originalName = "\(id.uuidString)_orig.jpg"
        let variantName  = "\(id.uuidString)_v0.jpg"
        writeJPEG(original, to: originalName)
        writeJPEG(graded, to: variantName)

        let variant = GradeVariant(
            id: UUID(), createdAt: now, imageFilename: variantName,
            scene: analysis.scene.rawValue, lighting: analysis.lighting.rawValue,
            rationale: analysis.rationale
        )
        let item = LibraryItem(
            id: id, createdAt: now, originalFilename: originalName, variants: [variant]
        )
        items.insert(item, at: 0)
        saveManifest()
        return id
    }

    /// Append a new graded variant to an existing item.
    public func addVariant(itemID: UUID, graded: CGImage, analysis: SceneAnalysis) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        let n = items[idx].variants.count
        let variantName = "\(itemID.uuidString)_v\(n).jpg"
        writeJPEG(graded, to: variantName)
        let variant = GradeVariant(
            id: UUID(), createdAt: Date(), imageFilename: variantName,
            scene: analysis.scene.rawValue, lighting: analysis.lighting.rawValue,
            rationale: analysis.rationale
        )
        items[idx].variants.append(variant)
        saveManifest()
    }

    /// Remove an item and all of its image files.
    public func delete(_ itemID: UUID) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        let item = items[idx]
        var names = [item.originalFilename]
        names.append(contentsOf: item.variants.map(\.imageFilename))
        for name in names {
            try? FileManager.default.removeItem(at: libraryURL(name))
        }
        items.remove(at: idx)
        saveManifest()
    }

    // MARK: - Export

    /// Export a stored JPEG out to the user's Photos library (add-only).
    public func exportToPhotos(filename: String) async throws {
        let url = libraryURL(filename)
        guard let data = try? Data(contentsOf: url) else {
            throw LibraryStoreError.imageLoadFailed
        }
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .authorized, .limited: break
        case .denied, .restricted: throw LibraryStoreError.photoLibraryDenied
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if granted != .authorized && granted != .limited {
                throw LibraryStoreError.photoLibraryDenied
            }
        @unknown default: throw LibraryStoreError.photoLibraryDenied
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: nil)
            }
        } catch {
            throw LibraryStoreError.saveFailed(error)
        }
    }
}

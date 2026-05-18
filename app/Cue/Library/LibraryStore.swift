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
        // First launch / no manifest at all — empty library is correct.
        guard let data = try? Data(contentsOf: manifestURL) else {
            items = []
            return
        }
        // Manifest exists and decodes — normal path.
        if let decoded = try? decoder.decode([LibraryItem].self, from: data) {
            items = decoded
            return
        }
        // Manifest exists but is CORRUPT. Never silently wipe — that would let the
        // next saveManifest() destroy every prior photo's metadata.
        Self.log.error("loadManifest: corrupt manifest, preserving + attempting rebuild")
        // 1. Copy the bad manifest aside so it's never overwritten / is recoverable.
        let stamp = Int(Date().timeIntervalSince1970)
        let backupURL = dir.appendingPathComponent("manifest.corrupt-\(stamp).json")
        do {
            try FileManager.default.copyItem(at: manifestURL, to: backupURL)
        } catch {
            Self.log.error("loadManifest: failed to back up corrupt manifest: \(error.localizedDescription, privacy: .public)")
        }
        // 2. Rebuild from the JPEG files actually on disk.
        items = rebuildFromDisk()
    }

    /// Reconstruct minimal `LibraryItem`s by scanning the library directory for
    /// `<uuid>_orig.jpg` originals and their `<uuid>_v<n>.jpg` variants.
    private func rebuildFromDisk() -> [LibraryItem] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }
        let origSuffix = "_orig.jpg"
        var rebuilt: [LibraryItem] = []
        for name in names where name.hasSuffix(origSuffix) {
            let idString = String(name.dropLast(origSuffix.count))
            guard let id = UUID(uuidString: idString) else { continue }
            let createdAt = (try? FileManager.default.attributesOfItem(
                atPath: libraryURL(name).path)[.creationDate] as? Date) ?? Date()
            // Collect variant files for this id: "<uuid>_v<n>.jpg".
            let variantPrefix = "\(idString)_v"
            let variantNames = names
                .filter { $0.hasPrefix(variantPrefix) && $0.hasSuffix(".jpg") }
                .sorted()
            let variants: [GradeVariant] = variantNames.map { vName in
                GradeVariant(
                    id: UUID(), createdAt: createdAt, imageFilename: vName,
                    scene: "recovered", lighting: "recovered", rationale: "recovered"
                )
            }
            rebuilt.append(LibraryItem(
                id: id, createdAt: createdAt,
                originalFilename: name, variants: variants
            ))
        }
        // Newest first, matching the normal ordering invariant.
        rebuilt.sort { $0.createdAt > $1.createdAt }
        Self.log.error("loadManifest: rebuilt \(rebuilt.count, privacy: .public) item(s) from disk")
        return rebuilt
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

    /// Encode and write a JPEG. Returns `true` only if the file is fully on disk.
    /// On any failure the caller MUST NOT record a manifest entry for `filename`.
    @discardableResult
    private func writeJPEG(_ cg: CGImage, to filename: String) -> Bool {
        let url = libraryURL(filename)
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            Self.log.error("writeJPEG: destination create failed")
            return false
        }
        CGImageDestinationAddImage(dest, cg, [
            kCGImageDestinationLossyCompressionQuality: 0.92
        ] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            Self.log.error("writeJPEG: finalize failed for \(filename, privacy: .public)")
            return false
        }
        do {
            try (data as Data).write(to: url, options: .atomic)
            return true
        } catch {
            Self.log.error("writeJPEG: disk write failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    public func loadImage(_ filename: String) -> CGImage? {
        let url = libraryURL(filename)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// Decode a DOWNSAMPLED thumbnail of a stored JPEG without loading the full
    /// (potentially 48MP) image into memory. Use this for grid cells, filmstrip
    /// thumbs, and the editor's on-screen image — never `loadImage` for display.
    public func loadThumbnail(_ filename: String, maxPixel: CGFloat = 400) -> CGImage? {
        let url = libraryURL(filename)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }

    // MARK: - Mutations

    /// Persist a new capture: original + first graded variant.
    /// Returns the item id, or `nil` if writing either image file failed (in
    /// which case nothing is recorded in the manifest and no files are left).
    /// The capture is stored UN-graded — grading is a manual action in the editor.
    @discardableResult
    public func addCapture(original: CGImage) -> UUID? {
        let id = UUID()
        let now = Date()
        let originalName = "\(id.uuidString)_orig.jpg"

        guard writeJPEG(original, to: originalName) else {
            Self.log.error("addCapture: original write failed, aborting insert")
            return nil
        }

        let item = LibraryItem(
            id: id, createdAt: now, originalFilename: originalName, variants: []
        )
        items.insert(item, at: 0)
        saveManifest()
        return id
    }

    /// Append a new graded variant to an existing item.
    /// Returns `true` on success; if the image write fails nothing is recorded.
    @discardableResult
    public func addVariant(itemID: UUID, graded: CGImage, analysis: SceneAnalysis) -> Bool {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return false }
        let n = items[idx].variants.count
        let variantName = "\(itemID.uuidString)_v\(n).jpg"

        guard writeJPEG(graded, to: variantName) else {
            Self.log.error("addVariant: variant write failed, aborting insert")
            // Remove any partially-written file so it doesn't orphan on disk.
            try? FileManager.default.removeItem(at: libraryURL(variantName))
            return false
        }

        let variant = GradeVariant(
            id: UUID(), createdAt: Date(), imageFilename: variantName,
            scene: analysis.scene.rawValue, lighting: analysis.lighting.rawValue,
            rationale: analysis.rationale
        )
        items[idx].variants.append(variant)
        saveManifest()
        return true
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

import SwiftUI
import CoreImage

/// Editor for one library item: view the original or any graded variant,
/// re-roll the AI grade, and export the selected image to Photos.
public struct EditorView: View {
    @ObservedObject var store: LibraryStore
    let itemID: UUID
    let backendClient: BackendClient

    /// nil = original selected; otherwise the selected variant id.
    @State private var selectedVariantID: UUID?
    @State private var isGrading = false
    @State private var errorBanner: String?
    @State private var savedConfirmation = false

    public init(store: LibraryStore, itemID: UUID, backendClient: BackendClient) {
        self.store = store
        self.itemID = itemID
        self.backendClient = backendClient
    }

    private var item: LibraryItem? {
        store.items.first(where: { $0.id == itemID })
    }

    /// Filename of the currently-selected image (original or a variant).
    private var selectedFilename: String? {
        guard let item else { return nil }
        if let vid = selectedVariantID,
           let v = item.variants.first(where: { $0.id == vid }) {
            return v.imageFilename
        }
        return item.originalFilename
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                if let banner = errorBanner {
                    Text(banner)
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 9)
                        .glassEffect(.regular.tint(.red.opacity(0.55)), in: .capsule)
                        .padding(.top, 8)
                }

                Spacer(minLength: 0)
                mainImage
                Spacer(minLength: 0)

                filmstrip
                actionBar
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            if savedConfirmation {
                Text("Saved")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .glassEffect(.regular.tint(.green.opacity(0.5)), in: .capsule)
                    .padding(.top, 12)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Image

    @ViewBuilder
    private var mainImage: some View {
        if let filename = selectedFilename, let cg = store.loadThumbnail(filename, maxPixel: 2000) {
            Image(decorative: cg, scale: 1, orientation: .up)
                .resizable()
                .scaledToFit()
                .padding(.horizontal, 8)
        } else {
            Color.white.opacity(0.05)
                .overlay(Image(systemName: "photo").font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.3)))
        }
    }

    // MARK: - Filmstrip

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let item {
                    thumb(filename: item.originalFilename,
                          label: "Original",
                          isSelected: selectedVariantID == nil) {
                        selectedVariantID = nil
                    }
                    ForEach(Array(item.variants.enumerated()), id: \.element.id) { idx, v in
                        thumb(filename: v.imageFilename,
                              label: "Grade \(idx + 1)",
                              isSelected: selectedVariantID == v.id) {
                            selectedVariantID = v.id
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func thumb(filename: String, label: String,
                       isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Rectangle().fill(Color.white.opacity(0.06))
                    if let cg = store.loadThumbnail(filename, maxPixel: 160) {
                        Image(decorative: cg, scale: 1, orientation: .up)
                            .resizable()
                            .scaledToFill()
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(isSelected ? Color.cyan : Color.clear,
                                lineWidth: 2.5)
                )
                .opacity(isSelected ? 1 : 0.55)
                Text(label)
                    .font(.caption2.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .cyan : .white.opacity(0.55))
            }
        }
    }

    // MARK: - Actions

    /// Floating glass control cluster: Download / AI Grade (hero) / Share.
    private var actionBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                // Download — export selected image to Camera Roll.
                Button {
                    Task { await download() }
                } label: {
                    actionLabel(icon: "square.and.arrow.down", label: "Download")
                }
                .buttonStyle(.glass)
                .disabled(isGrading)

                // AI Grade — the hero action; press again to re-roll.
                Button(action: { Task { await regrade() } }) {
                    VStack(spacing: 5) {
                        if isGrading {
                            ProgressView().tint(.white).frame(height: 21)
                        } else {
                            Image(systemName: "sparkles").font(.system(size: 19))
                        }
                        Text(isGrading ? "Grading…" : "AI Grade")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .foregroundStyle(.white)
                }
                .buttonStyle(.glassProminent)
                .tint(.cyan)
                .disabled(isGrading)

                // Share — system share sheet for the selected image file.
                if let filename = selectedFilename {
                    ShareLink(item: store.libraryURL(filename)) {
                        actionLabel(icon: "square.and.arrow.up", label: "Share")
                    }
                    .buttonStyle(.glass)
                    .disabled(isGrading)
                } else {
                    Button {} label: {
                        actionLabel(icon: "square.and.arrow.up", label: "Share")
                    }
                    .buttonStyle(.glass)
                    .disabled(true)
                    .opacity(0.4)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func actionLabel(icon: String, label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 19))
            Text(label).font(.system(size: 12, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .foregroundStyle(.white)
    }

    /// Grade the ORIGINAL image — pressing again re-rolls (backend temperature 0.7).
    private func regrade() async {
        guard let item, !isGrading else { return }
        guard let original = store.loadImage(item.originalFilename) else {
            errorBanner = "Couldn't load the original image."
            return
        }
        isGrading = true
        errorBanner = nil

        let originalCI = CIImage(cgImage: original)
        let b64 = await Task.detached(priority: .userInitiated) {
            ImageEncoder.downsampledBase64(from: originalCI, maxSide: 1024, quality: 0.85)
        }.value
        guard let b64 else {
            errorBanner = "Image encoding failed."
            isGrading = false
            return
        }
        do {
            let analysis = try await backendClient.grade(imageB64: b64)
            let graded = CIPipeline.apply(analysis.grade, to: originalCI)
            guard let gradedCG = SharedCI.context.createCGImage(graded, from: graded.extent) else {
                errorBanner = "Rendering the graded image failed."
                isGrading = false
                return
            }
            store.addVariant(itemID: itemID, graded: gradedCG, analysis: analysis)
            // Select the new variant.
            selectedVariantID = store.items.first(where: { $0.id == itemID })?
                .variants.last?.id
        } catch {
            errorBanner = "AI grade failed: \(error.localizedDescription)"
        }
        isGrading = false
    }

    /// Export the currently-selected image to the Camera Roll.
    private func download() async {
        guard let filename = selectedFilename else { return }
        do {
            try await store.exportToPhotos(filename: filename)
            withAnimation { savedConfirmation = true }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { savedConfirmation = false }
        } catch {
            errorBanner = "Save failed: \(error.localizedDescription)"
        }
    }
}

import SwiftUI
import CoreImage

/// Full-library photo detail viewer. The current photo fills the screen;
/// swipe it left/right or tap the bottom filmstrip — which shows the WHOLE
/// library, Apple Photos style — to move between photos. AI Grade adds a new
/// graded entry to the library and jumps to it.
public struct EditorView: View {
    @ObservedObject var store: LibraryStore
    let backendClient: BackendClient
    /// Open the thumbnail grid.
    let onShowGrid: () -> Void
    /// Close the whole library browser.
    let onClose: () -> Void

    /// Cue Cyan — the single accent. Used for the current selection.
    private static let accent = Color(red: 0.239, green: 0.839, blue: 0.902)

    /// Which photo is currently shown — owned by the parent PhotoBrowser so the
    /// grid can change it.
    @Binding private var currentID: UUID
    @State private var isGrading = false
    @State private var errorBanner: String?
    @State private var savedConfirmation = false

    public init(store: LibraryStore, currentID: Binding<UUID>, backendClient: BackendClient,
                onShowGrid: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.store = store
        self._currentID = currentID
        self.backendClient = backendClient
        self.onShowGrid = onShowGrid
        self.onClose = onClose
    }

    /// The currently-displayed photo, or `nil` if it no longer exists.
    private var currentPhoto: LibraryPhoto? {
        store.items.first(where: { $0.id == currentID })
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                pager
                filmstrip
                actionBar
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) { topBar }
        .overlay(alignment: .top) { transientBanner }
        // If the library empties or the current photo vanishes, leave gracefully.
        .onChange(of: store.items) { _, items in
            if items.isEmpty {
                onClose()
            } else if !items.contains(where: { $0.id == currentID }) {
                currentID = items[0].id
            }
        }
        .onAppear {
            if store.items.isEmpty {
                onClose()
            } else if currentPhoto == nil {
                currentID = store.items[0].id
            }
        }
    }

    // MARK: - Top bar (grid + close)

    private var topBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack {
                Button(action: onShowGrid) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }
            .padding(.horizontal, 14)
        }
        .padding(.top, 8)
    }

    /// Transient error / saved banners, shown just below the top bar.
    @ViewBuilder
    private var transientBanner: some View {
        if let banner = errorBanner {
            Text(banner)
                .font(.footnote)
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .glassEffect(.regular.tint(.red.opacity(0.55)), in: .capsule)
                .padding(.top, 58)
        } else if savedConfirmation {
            Text("Saved")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .glassEffect(.regular.tint(.green.opacity(0.5)), in: .capsule)
                .padding(.top, 58)
                .transition(.opacity)
        }
    }

    // MARK: - Main image (swipeable pager)

    private var pager: some View {
        TabView(selection: $currentID) {
            ForEach(store.items) { photo in
                pageImage(photo)
                    .tag(photo.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func pageImage(_ photo: LibraryPhoto) -> some View {
        // Decoded off-main + cached — TabView re-renders constantly while
        // swiping; a synchronous decode here janks the swipe.
        AsyncThumbnail(store: store, filename: photo.filename,
                       maxPixel: 2000, contentMode: .fit)
            .padding(.horizontal, 8)
    }

    // MARK: - Filmstrip (the whole library)

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.items) { photo in
                        thumb(photo: photo, isSelected: photo.id == currentID)
                            .id(photo.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onChange(of: currentID) { _, id in
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onAppear {
                proxy.scrollTo(currentID, anchor: .center)
            }
        }
    }

    private func thumb(photo: LibraryPhoto, isSelected: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                currentID = photo.id
            }
        } label: {
            AsyncThumbnail(store: store, filename: photo.filename,
                           maxPixel: 160, contentMode: .fill)
            .frame(width: 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Self.accent : Color.clear, lineWidth: 2.5)
            )
            .opacity(isSelected ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action bar

    /// Compact floating glass control cluster: Download / AI Grade / Share.
    /// Icon-only, no labels — three circular glass buttons.
    private var actionBar: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 14) {
                // Download — export the current photo to the Camera Roll.
                Button {
                    Task { await download() }
                } label: {
                    iconLabel("arrow.down.to.line")
                }
                .buttonStyle(.glass)
                .disabled(isGrading || currentPhoto == nil)

                // AI Grade — the hero action; press again to re-roll.
                Button(action: { Task { await grade() } }) {
                    Group {
                        if isGrading {
                            ProgressView().tint(.white)
                        } else {
                            // Color-themed: AI color grading.
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 21, weight: .medium))
                        }
                    }
                    .frame(width: 52, height: 52)
                    .foregroundStyle(.white)
                }
                .buttonStyle(.glassProminent)
                .tint(Self.accent)
                .disabled(isGrading || currentPhoto == nil)

                // Share — system share sheet for the current photo file.
                if let photo = currentPhoto {
                    ShareLink(item: store.libraryURL(photo.filename)) {
                        iconLabel("square.and.arrow.up")
                    }
                    .buttonStyle(.glass)
                    .disabled(isGrading)
                } else {
                    Button {} label: { iconLabel("square.and.arrow.up") }
                        .buttonStyle(.glass)
                        .disabled(true)
                        .opacity(0.4)
                }
            }
        }
        .padding(.bottom, 18)
    }

    private func iconLabel(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 19, weight: .medium))
            .frame(width: 48, height: 48)
            .foregroundStyle(.white)
    }

    // MARK: - Grading

    /// Grade the CURRENT photo. Always grades its `sourceFilename` (the true
    /// original), so re-pressing on an already-graded photo re-rolls cleanly.
    /// The result becomes a NEW library entry and is shown immediately.
    private func grade() async {
        guard let photo = currentPhoto, !isGrading else { return }
        guard let original = store.loadImage(photo.sourceFilename) else {
            errorBanner = "Couldn't load the source image."
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
            if analysis.degraded == true {
                errorBanner = "Color grading unavailable"
                isGrading = false
                return
            }
            let graded = CIPipeline.apply(analysis.grade, to: originalCI)
            guard let gradedCG = SharedCI.cgImage(from: graded) else {
                errorBanner = "Rendering the graded image failed."
                isGrading = false
                return
            }
            if let newID = store.addGrade(source: photo, graded: gradedCG) {
                // Jump to the freshly graded photo so the user sees the result.
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    currentID = newID
                }
            } else {
                errorBanner = "Couldn't save the graded photo."
            }
        } catch {
            errorBanner = "AI grade failed: \(error.localizedDescription)"
        }
        isGrading = false
    }

    /// Export the current photo to the Camera Roll.
    private func download() async {
        guard let photo = currentPhoto else { return }
        do {
            try await store.exportToPhotos(filename: photo.filename)
            withAnimation { savedConfirmation = true }
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation { savedConfirmation = false }
        } catch {
            errorBanner = "Save failed: \(error.localizedDescription)"
        }
    }
}

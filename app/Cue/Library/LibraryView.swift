import SwiftUI

/// In-app photo library: a dense grid of every photo — originals and AI-graded
/// results sit side by side as siblings. Tap a cell to open the photo detail
/// viewer, where the whole library can be browsed and re-graded.
public struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    let dismiss: () -> Void

    private let backendClient = BackendClient()

    @State private var toast: String?

    /// Dense 3-column grid. 1.5pt gaps read as thin black separator lines
    /// between photos — matches the iOS 26 Photos app Library tab.
    private let gridGap: CGFloat = 1.5
    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: gridGap),
         GridItem(.flexible(), spacing: gridGap),
         GridItem(.flexible(), spacing: gridGap)]
    }

    public init(store: LibraryStore, dismiss: @escaping () -> Void) {
        self.store = store
        self.dismiss = dismiss
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if store.items.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: gridGap) {
                            ForEach(store.items) { photo in
                                NavigationLink {
                                    EditorView(store: store, startPhotoID: photo.id,
                                               backendClient: backendClient)
                                } label: {
                                    cell(for: photo)
                                }
                                .contextMenu {
                                    Button {
                                        saveToPhotos(photo)
                                    } label: {
                                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                                    }
                                    Button(role: .destructive) {
                                        store.delete(photo.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, gridGap)
                        // Leave room for the floating glass nav so the grid
                        // scrolls cleanly under it.
                        .padding(.top, 72)
                        .padding(.bottom, 8)
                    }
                }

                // Floating glass nav — pinned top, grid scrolls beneath it.
                floatingNav

                if let toast {
                    VStack {
                        Spacer()
                        Text(toast)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 11)
                            .glassEffect(.regular, in: .capsule)
                            .padding(.bottom, 44)
                    }
                    .transition(.opacity)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Floating glass nav

    private var floatingNav: some View {
        VStack {
            GlassEffectContainer(spacing: 10) {
                HStack {
                    Text("Library")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer()
        }
    }

    /// Export the photo to the user's Photos library.
    private func saveToPhotos(_ photo: LibraryPhoto) {
        let filename = photo.filename
        Task {
            do {
                try await store.exportToPhotos(filename: filename)
                showToast("Saved to Photos")
            } catch {
                showToast("Save failed")
            }
        }
    }

    private func showToast(_ message: String) {
        withAnimation { toast = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { if toast == message { toast = nil } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text("No photos yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Shoot one from the camera.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    @ViewBuilder
    private func cell(for photo: LibraryPhoto) -> some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.06))
            if let cg = store.loadThumbnail(photo.filename, maxPixel: 400) {
                Image(decorative: cg, scale: 1, orientation: .up)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        // Square cells (no corner radius) so the 1.5pt gaps read as clean
        // thin black grid lines, Apple Photos style.
        // A graded photo carries a small, subtle cyan mark so it reads as
        // "AI" at a glance — accent stays rare per DESIGN.md.
        .overlay(alignment: .bottomTrailing) {
            if photo.isGraded {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.239, green: 0.839, blue: 0.902))
                    .padding(4)
                    .background(.black.opacity(0.35), in: .circle)
                    .padding(4)
            }
        }
    }
}

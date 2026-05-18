import SwiftUI

/// In-app photo library: a grid of captures. Tap a cell to open the editor
/// where the photo can be re-graded and exported.
public struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    let dismiss: () -> Void

    private let backendClient = BackendClient()

    @State private var toast: String?

    /// Dense 3-column grid, 2pt gaps — matches the iOS 26 Photos app Library tab.
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]

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
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(store.items) { item in
                                NavigationLink {
                                    EditorView(store: store, itemID: item.id,
                                               backendClient: backendClient)
                                } label: {
                                    cell(for: item)
                                }
                                .contextMenu {
                                    Button {
                                        saveToPhotos(item)
                                    } label: {
                                        Label("Save to Photos", systemImage: "square.and.arrow.down")
                                    }
                                    Button(role: .destructive) {
                                        store.delete(item.id)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 2)
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

    /// Export the photo (latest graded variant, or the original) to Photos.
    private func saveToPhotos(_ item: LibraryItem) {
        let filename = item.displayFilename
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
    private func cell(for item: LibraryItem) -> some View {
        let filename: String? = item.displayFilename
        ZStack {
            Rectangle().fill(Color.white.opacity(0.06))
            if let filename, let cg = store.loadThumbnail(filename, maxPixel: 400) {
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
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

import SwiftUI

/// In-app photo library: a grid of captures. Tap a cell to open the editor
/// where the photo can be re-graded and exported.
public struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    let dismiss: () -> Void

    private let backendClient = BackendClient()
    private let renderer = PhotoRenderer()

    private let columns = [
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
        GridItem(.flexible(), spacing: 3),
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
                        LazyVGrid(columns: columns, spacing: 3) {
                            ForEach(store.items) { item in
                                NavigationLink {
                                    EditorView(store: store, itemID: item.id,
                                               backendClient: backendClient, renderer: renderer)
                                } label: {
                                    cell(for: item)
                                }
                            }
                        }
                        .padding(3)
                    }
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .tint(.white)
                }
            }
        }
        .preferredColorScheme(.dark)
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
        let filename = item.latestVariant?.imageFilename
        ZStack {
            Rectangle().fill(Color.white.opacity(0.06))
            if let filename, let cg = store.loadImage(filename) {
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
    }
}

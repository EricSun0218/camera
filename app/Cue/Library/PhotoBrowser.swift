import SwiftUI

/// Entry point for the in-app library, presented from the camera's gallery
/// button. Opens straight into the photo detail viewer (EditorView). A grid
/// button there pushes the thumbnail grid (LibraryView); tapping a grid cell
/// returns to the detail viewer on that photo.
public struct PhotoBrowser: View {
    @ObservedObject var store: LibraryStore
    let close: () -> Void

    @State private var currentID: UUID?
    @State private var showGrid = false
    private let backendClient = BackendClient()

    public init(store: LibraryStore, close: @escaping () -> Void) {
        self.store = store
        self.close = close
        // Start on the newest photo — no empty-state flash when the library is non-empty.
        _currentID = State(initialValue: store.items.first?.id)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let id = currentID, store.items.contains(where: { $0.id == id }) {
                    EditorView(
                        store: store,
                        currentID: Binding(get: { id }, set: { currentID = $0 }),
                        backendClient: backendClient,
                        onShowGrid: { showGrid = true },
                        onClose: close
                    )
                } else {
                    emptyState
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showGrid) {
                LibraryView(store: store, onPick: { picked in
                    currentID = picked
                    showGrid = false
                })
            }
        }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text("No photos yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Shoot one from the camera.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
            Button("Close", action: close)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 22).frame(height: 44)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.top, 8)
        }
    }
}

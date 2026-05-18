import SwiftUI

/// Thumbnail grid of the whole library — pushed from the photo detail viewer.
/// Tapping a cell returns to the detail viewer on that photo (`onPick`).
/// Tap "Select" to multi-select photos and download or delete them.
public struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    /// Called with the tapped photo's id — the parent returns to the detail viewer.
    let onPick: (UUID) -> Void

    @Environment(\.dismiss) private var dismissPage

    /// Cue Cyan — the single accent.
    private static let accent = Color(red: 0.239, green: 0.839, blue: 0.902)

    @State private var toast: String?
    @State private var selecting = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var confirmDelete = false

    /// Dense 3-column grid. 1.5pt gaps read as thin black separator lines
    /// between photos — matches the iOS 26 Photos app Library tab.
    private let gridGap: CGFloat = 1.5
    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: gridGap),
         GridItem(.flexible(), spacing: gridGap),
         GridItem(.flexible(), spacing: gridGap)]
    }

    public init(store: LibraryStore, onPick: @escaping (UUID) -> Void) {
        self.store = store
        self.onPick = onPick
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if store.items.isEmpty {
                emptyState
            } else {
                grid
            }

            // Floating glass nav — pinned top, grid scrolls beneath it.
            floatingNav

            // Selection action bar — pinned bottom, only while selecting.
            if selecting {
                selectionBar
            }

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
        .preferredColorScheme(.dark)
        .confirmationDialog("Delete \(selectedIDs.count) photo\(selectedIDs.count == 1 ? "" : "s")?",
                            isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone.")
        }
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: gridGap) {
                ForEach(store.items) { photo in
                    photoTile(for: photo)
                        .onTapGesture {
                            if selecting { toggle(photo.id) } else { onPick(photo.id) }
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
            .padding(.top, 72)   // clear the floating nav
            .padding(.bottom, selecting ? 96 : 8)  // clear the selection bar
        }
    }

    // MARK: - Floating glass nav

    private var floatingNav: some View {
        VStack {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    // Back to the photo detail viewer (hidden during selection).
                    if !selecting {
                        Button {
                            dismissPage()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                        }
                        .glassEffect(.regular.interactive(), in: .circle)
                    }

                    Text(selecting
                         ? (selectedIDs.isEmpty ? "Select Photos" : "\(selectedIDs.count) Selected")
                         : "Library")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)

                    Spacer()

                    // Select / Cancel
                    if !store.items.isEmpty {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selecting.toggle()
                                if !selecting { selectedIDs = [] }
                            }
                        } label: {
                            Text(selecting ? "Cancel" : "Select")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .frame(height: 38)
                        }
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            Spacer()
        }
    }

    // MARK: - Selection action bar

    private var selectionBar: some View {
        VStack {
            Spacer()
            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    selectionAction(icon: "arrow.down.to.line", label: "Download",
                                    tint: nil) {
                        downloadSelected()
                    }
                    selectionAction(icon: "trash", label: "Delete",
                                    tint: .red) {
                        confirmDelete = true
                    }
                }
            }
            .opacity(selectedIDs.isEmpty ? 0.4 : 1)
            .allowsHitTesting(!selectedIDs.isEmpty)
            .padding(.bottom, 28)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func selectionAction(icon: String, label: String, tint: Color?,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon).font(.system(size: 16, weight: .medium))
                Text(label).font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(tint == .red ? Color.red : .white)
            .padding(.horizontal, 22)
            .frame(height: 50)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: - Cell

    @ViewBuilder
    private func photoTile(for photo: LibraryPhoto) -> some View {
        cell(for: photo)
            .overlay(alignment: .bottomTrailing) {
                if selecting {
                    selectionBadge(on: selectedIDs.contains(photo.id))
                }
            }
            // Selected cells get a faint cyan inset frame.
            .overlay {
                if selecting && selectedIDs.contains(photo.id) {
                    Rectangle().stroke(Self.accent, lineWidth: 2.5)
                }
            }
    }

    private func selectionBadge(on selected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(selected ? Self.accent : Color.black.opacity(0.35))
            Circle()
                .stroke(.white.opacity(selected ? 0 : 0.9), lineWidth: 1.5)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
            }
        }
        .frame(width: 22, height: 22)
        .padding(6)
    }

    @ViewBuilder
    private func cell(for photo: LibraryPhoto) -> some View {
        // Off-main decode + cache — keeps grid scrolling smooth.
        AsyncThumbnail(store: store, filename: photo.filename,
                       maxPixel: 400, contentMode: .fill)
        // .fit (not .fill) so the cell stays inside its column slot — .fill
        // overflows the slot and swallows the grid gap.
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        // A graded photo carries a small, subtle cyan mark (top-leading so it
        // never collides with the selection checkmark at bottom-trailing).
        .overlay(alignment: .topLeading) {
            if photo.isGraded {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Self.accent)
                    .padding(4)
                    .background(.black.opacity(0.35), in: .circle)
                    .padding(4)
            }
        }
    }

    // MARK: - Actions

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    private func downloadSelected() {
        let photos = store.items.filter { selectedIDs.contains($0.id) }
        guard !photos.isEmpty else { return }
        Task {
            var ok = 0
            for photo in photos {
                do { try await store.exportToPhotos(filename: photo.filename); ok += 1 }
                catch { /* keep going */ }
            }
            showToast(ok == photos.count
                      ? "Saved \(ok) to Photos"
                      : "Saved \(ok) of \(photos.count)")
            withAnimation(.easeInOut(duration: 0.2)) {
                selecting = false
                selectedIDs = []
            }
        }
    }

    private func deleteSelected() {
        for id in selectedIDs { store.delete(id) }
        withAnimation(.easeInOut(duration: 0.2)) {
            selecting = false
            selectedIDs = []
        }
    }

    /// Export one photo to the user's Photos library (context-menu path).
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
}

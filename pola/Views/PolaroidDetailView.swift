import Photos
import SwiftData
import SwiftUI

struct PolaroidDetailView: View {
    let startIndex: Int
    @Binding var currentEntryID: UUID?

    @Environment(PhotoStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PolaroidEntry.timestamp, order: .reverse) private var entries: [PolaroidEntry]

    @State private var scrollPosition: Int?
    @State private var pendingScrollTarget: Int? = nil
    @State private var isVideoPlaying = true
    @AppStorage("videoLooping") private var isVideoLooping = true
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false
    @State private var isSaving = false
    @State private var saveDidSucceed = false
    @State private var editingEntry: PolaroidEntry?

    init(startIndex: Int, currentEntryID: Binding<UUID?>) {
        self.startIndex = startIndex
        self._currentEntryID = currentEntryID
        self._scrollPosition = State(initialValue: startIndex)
    }

    private var currentIndex: Int { scrollPosition ?? startIndex }

    private var currentEntry: PolaroidEntry? {
        guard currentIndex < entries.count else { return nil }
        return entries[currentIndex]
    }

    var body: some View {
        VStack(spacing: 12) {
            if !entries.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                            PolaroidPhotoCell(
                                image: entry.image,
                                videoURL: entry.videoURL(in: store.videoDirectory),
                                isTimelapse: entry.isTimelapse,
                                playVideo: true,
                                isVideoPlaying: idx == currentIndex ? isVideoPlaying : false,
                                isVideoLooping: isVideoLooping,
                                developmentProgress: entry.developmentProgress,
                                caption: entry.caption,
                                backText: entry.backText,
                                showMap: entry.showMap,
                                coordinate: entry.coordinate,
                                timestamp: entry.timestamp,
                                filterName: entry.filterName,
                                packName: entry.packName,
                                fontScale: 1.7,
                                onDeveloped: {
                                    guard idx < entries.count else { return }
                                    entries[idx].developmentProgress = 1.0
                                }
                            )
                            .aspectRatio(270.0 / 360.0, contentMode: .fit)
                            .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 6)
                            .padding(.horizontal)
                            .containerRelativeFrame([.horizontal, .vertical], alignment: .center)
                            .id(idx)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrollPosition)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                titleView
            }

            if currentEntry?.videoFilename != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Menu {
                            Button {
                                isVideoLooping = true
                            } label: {
                                Label("Loop", systemImage: isVideoLooping ? "checkmark" : "repeat")
                            }
                            Button {
                                isVideoLooping = false
                            } label: {
                                Label("Play Once", systemImage: !isVideoLooping ? "checkmark" : "1.circle")
                            }
                        } label: {
                            Image(systemName: isVideoLooping ? "repeat" : "1.circle")
                        }

                        Button {
                            isVideoPlaying.toggle()
                        } label: {
                            Image(systemName: isVideoPlaying ? "pause.fill" : "play.fill")
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                }
            }
            
            ToolbarItem(placement: .bottomBar) {
                Button {
                    guard let entry = currentEntry else { return }
                    Task {
                        shareItems = await prepareShareItems(for: [entry], videoDirectory: store.videoDirectory)
                        showShareSheet = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }

            ToolbarItem(placement: .bottomBar) {
                Button {
                    guard !isSaving, !saveDidSucceed else { return }
                    Task { await saveCurrentPhoto() }
                } label: {
                    Group {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: saveDidSucceed ? "checkmark" : "square.and.arrow.down")
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                }
                .disabled(isSaving || saveDidSucceed)
            }

            ToolbarItem(placement: .bottomBar) {
                Button {
                    guard let entry = currentEntry else { return }
                    editingEntry = entry
                } label: {
                    Image(systemName: "pencil")
                }
            }

            ToolbarItem(placement: .bottomBar) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
            }
        }
        .sheet(item: $editingEntry) { item in
            EditPolaroidSheet(entry: item)
        }
        .background(ActivitySheet(items: shareItems, isPresented: $showShareSheet))
        .onChange(of: scrollPosition) { _, newPosition in
            guard let idx = newPosition, idx < entries.count else { return }
            currentEntryID = entries[idx].id
            isVideoPlaying = true
        }
        .onChange(of: entries.count) { _, _ in
            if let target = pendingScrollTarget {
                scrollPosition = target
                pendingScrollTarget = nil
            }
        }
        .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteCurrentPhoto()
            }
        }
    }

    @ViewBuilder
    private var titleView: some View {
        if let entry = currentEntry {
            VStack(spacing: 1) {
                Text(entry.timestamp, format: .dateTime.weekday(.wide))
                    .font(.headline)
                Text(entry.timestamp, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .id(currentIndex)
        }
    }

    // MARK: - Thumbnail strip

    private var thumbnailStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                        PolaroidPhotoCell(
                            image: entry.image,
                            videoURL: entry.videoURL(in: store.videoDirectory),
                            isTimelapse: entry.isTimelapse,
                            playVideo: false,
                            developmentProgress: entry.developmentProgress,
                            caption: entry.caption,
                            backText: entry.backText,
                            showMap: entry.showMap,
                            coordinate: entry.coordinate,
                            timestamp: entry.timestamp,
                            filterName: entry.filterName,
                            packName: entry.packName,
                            fontScale: 0.7,
                            onSingleTap: {
                                withAnimation(.snappy) {
                                    scrollPosition = idx
                                }
                            }
                        )
                        .shadow(color: .black.opacity(0.15), radius: 34, x: 0, y: 6)
                        .frame(width: idx == currentIndex ? 52 : 48, height: 64)
                        .overlay {
                            Rectangle()
                                .stroke(
                                    idx == currentIndex ? Color.accentColor : Color.clear,
                                    lineWidth: 1
                                )
                        }
                        .scaleEffect(idx == currentIndex ? 1.3 : 1.0)
                        .animation(.snappy, value: currentIndex)
                        .id(idx)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: currentIndex) { _, newIdx in
                withAnimation {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
        }
    }

    // MARK: - Delete

    private func deleteCurrentPhoto() {
        guard currentIndex < entries.count else { return }
        let entry = entries[currentIndex]
        if let filename = entry.videoFilename {
            store.deleteVideo(filename: filename)
        }
        // Calculate target before deletion (entries.count is still the old count here)
        let target = currentIndex >= entries.count - 1 ? max(0, currentIndex - 1) : currentIndex
        modelContext.delete(entry)
        guard entries.count > 1 else {
            dismiss()
            return
        }
        // Defer scroll navigation until @Query updates (onChange(of: entries.count))
        pendingScrollTarget = target
    }

    // MARK: - Save

    @MainActor
    private func saveCurrentPhoto() async {
        guard let entry = currentEntry else { return }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        isSaving = true
        if let filename = entry.videoFilename {
            let srcURL = store.videoDirectory.appendingPathComponent(filename)
            let url = await compositePolaroidVideo(entry, sourceURL: srcURL) ?? srcURL
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        } else {
            let image = renderPolaroidFrame(entry)
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        }
        isSaving = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            saveDidSucceed = true
        }
        try? await Task.sleep(for: .seconds(2))
        withAnimation {
            saveDidSucceed = false
        }
    }
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    @Binding var isPresented: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uvc: UIViewController, context: Context) {
        guard isPresented, uvc.presentedViewController == nil, !items.isEmpty else { return }
        let avc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        avc.completionWithItemsHandler = { _, _, _, _ in isPresented = false }
        uvc.present(avc, animated: true)
    }
}

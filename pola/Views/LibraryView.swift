import Photos
import SwiftData
import SwiftUI

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

struct LibraryView: View {
    @Environment(PhotoStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(PremiumManager.self) private var premium
    @Query(sort: \PolaroidEntry.timestamp, order: .reverse) private var entries: [PolaroidEntry]

    @State private var showPaywall = false
    @State private var selectedCategory = "All"
    @State private var sortNewest = true
    @State private var searchText = ""
    @State private var editingEntry: PolaroidEntry? = nil
    @State private var selectedEntryID: UUID? = nil
    @State private var currentDetailEntryID: UUID? = nil
    @State private var isSelectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false
    @State private var deletingIDs: Set<UUID> = []
    @State private var isSaving = false
    @State private var saveDidSucceed = false

    @AppStorage("libraryColumnCount") private var columnCount: Int = 3
    @AppStorage("polaroidFont") private var polaroidFontRaw: String = PolaroidFont.handwriting.rawValue
    @AppStorage("polaroidFontWeight") private var polaroidFontWeightRaw: String = PolaroidFontWeight.regular.rawValue
    @GestureState private var pinchScale: CGFloat = 1.0
    @Namespace private var zoomNamespace

    private let categories: [(name: String, color: Color)] = [
        ("All",   .gray),
        ("FLÄRN", Color(red: 0.95, green: 0.78, blue: 0.12)),
        ("SOLVA", Color(red: 0.96, green: 0.72, blue: 0.54)),
        ("BRÖKK", Color(red: 0.78, green: 0.43, blue: 0.22)),
        ("VYLUR", Color(red: 0.68, green: 0.27, blue: 0.82)),
        ("GRÅLT", Color(red: 0.28, green: 0.28, blue: 0.28)),
    ]

    private var filteredEntries: [PolaroidEntry] {
        var result = Array(entries)
        if selectedCategory != "All" {
            result = result.filter {
                $0.packName == selectedCategory || $0.filterName == selectedCategory
            }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.caption.localizedCaseInsensitiveContains(searchText) ||
                $0.backText.localizedCaseInsensitiveContains(searchText)
            }
        }
        return sortNewest ? result : result.reversed()
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
    }

    private var cellFontScale: CGFloat {
        switch columnCount {
        case 1: return 1.7
        case 2: return 1.3
        default: return 1.0
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label("No Photos Yet", systemImage: "camera")
                    } description: {
                        Text("Take your first photo to see it here")
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredEntries.isEmpty {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        let query = searchText.isEmpty ? selectedCategory : searchText
                        Text(verbatim: String(format: NSLocalizedString("No photos matching \"%@\"", comment: ""), query))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 10) {
                            ForEach(filteredEntries) { entry in
                                gridCell(for: entry)
                            }
                        }
                        .animation(.spring(duration: 0.35, bounce: 0.2), value: filteredEntries.map(\.id))
                        .animation(.spring(duration: 0.4, bounce: 0.2), value: columnCount)
                        .padding(12)
                        .padding(.horizontal, columnCount == 1 ? 60 : 0)
                    }
                    .gesture(
                        MagnificationGesture()
                            .updating($pinchScale) { value, state, _ in
                                state = value
                            }
                            .onEnded { value in
                                withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                                    if value > 1.4 && columnCount > 1 {
                                        columnCount -= 1
                                    } else if value < 0.75 && columnCount < 3 {
                                        columnCount += 1
                                    }
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                    )
                }
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search captions…")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(alignment: isSelectMode ? .center : .leading, spacing: 0) {
                        Text("Library")
                            .font(.largeTitle.width(.expanded).weight(.bold))
                            .lineHeight(.normal)
                        if !entries.isEmpty {
                            if isSelectMode && !selectedIDs.isEmpty {
                                Text("\(selectedIDs.count)/\(entries.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                let count = filteredEntries.count
                                let itemLabel = count == 1
                                    ? NSLocalizedString("1 item", comment: "")
                                    : String(format: NSLocalizedString("%d items", comment: ""), count)
                                Text(verbatim: itemLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if isSelectMode && !selectedIDs.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            let selected = entries.filter { selectedIDs.contains($0.id) }
                            Task {
                                shareItems = await prepareShareItems(for: selected, videoDirectory: store.videoDirectory)
                                showShareSheet = true
                            }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            guard !isSaving, !saveDidSucceed else { return }
                            let selected = entries.filter { selectedIDs.contains($0.id) }
                            Task {
                                isSaving = true
                                await saveToPhotosApp(selected)
                                isSaving = false
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    saveDidSucceed = true
                                }
                                try? await Task.sleep(for: .seconds(2))
                                withAnimation {
                                    saveDidSucceed = false
                                }
                            }
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Label("Save", systemImage: saveDidSucceed ? "checkmark" : "square.and.arrow.down")
                                    .contentTransition(.symbolEffect(.replace))
                            }
                        }
                        .disabled(isSaving || saveDidSucceed)
                    }
                    ToolbarSpacer(.fixed, placement: .bottomBar)
                    ToolbarItem(placement: .bottomBar) {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(.red)
                        .buttonStyle(.glassProminent)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if !entries.isEmpty {
                            Button(isSelectMode ? "Cancel" : "Select") {
                                withAnimation {
                                    isSelectMode.toggle()
                                    selectedIDs.removeAll()
                                }
                            }
                        }
                        if !isSelectMode {
                            Menu {
                                Menu {
                                    ForEach(categories, id: \.name) { cat in
                                        Button {
                                            withAnimation(.snappy) {
                                                selectedCategory = (selectedCategory == cat.name && cat.name != "All") ? "All" : cat.name
                                            }
                                        } label: {
                                            Label(cat.name, systemImage: selectedCategory == cat.name ? "checkmark" : "tag")
                                        }
                                    }
                                } label: {
                                    Label("Filter", systemImage: selectedCategory == "All" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                                }

                                Divider()

                                Menu {
                                    Button { withAnimation { sortNewest = true } } label: {
                                        Label("Newest First", systemImage: sortNewest ? "checkmark" : "arrow.up")
                                    }
                                    Button { withAnimation { sortNewest = false } } label: {
                                        Label("Oldest First", systemImage: !sortNewest ? "checkmark" : "arrow.down")
                                    }
                                } label: {
                                    Label("Sort", systemImage: "arrow.up.arrow.down")
                                }

                                Divider()

                                Menu {
                                    Button { withAnimation(.spring(duration: 0.4, bounce: 0.2)) { columnCount = 1 } } label: {
                                        Label("1 Column", systemImage: columnCount == 1 ? "checkmark" : "rectangle.grid.1x2")
                                    }
                                    Button { withAnimation(.spring(duration: 0.4, bounce: 0.2)) { columnCount = 2 } } label: {
                                        Label("2 Columns", systemImage: columnCount == 2 ? "checkmark" : "square.grid.2x2")
                                    }
                                    Button { withAnimation(.spring(duration: 0.4, bounce: 0.2)) { columnCount = 3 } } label: {
                                        Label("3 Columns", systemImage: columnCount == 3 ? "checkmark" : "square.grid.3x2")
                                    }
                                } label: {
                                    Label("Grid", systemImage: "square.grid.2x2")
                                }

                                Divider()

                                if premium.isPremium {
                                    Menu {
                                        ForEach(PolaroidFont.allCases, id: \.rawValue) { font in
                                            Button { polaroidFontRaw = font.rawValue } label: {
                                                Label(font.displayName, systemImage: polaroidFontRaw == font.rawValue ? "checkmark" : "textformat")
                                            }
                                        }
                                    } label: {
                                        Label("Caption Font", systemImage: "textformat")
                                    }

                                    Menu {
                                        ForEach(PolaroidFontWeight.allCases, id: \.rawValue) { w in
                                            Button { polaroidFontWeightRaw = w.rawValue } label: {
                                                Label(w.displayName, systemImage: polaroidFontWeightRaw == w.rawValue ? "checkmark" : "bold")
                                            }
                                        }
                                    } label: {
                                        Label("Font Weight", systemImage: "bold")
                                    }
                                } else {
                                    Button { showPaywall = true } label: {
                                        Label("Caption Font", systemImage: "lock.fill")
                                    }
                                    Button { showPaywall = true } label: {
                                        Label("Font Weight", systemImage: "lock.fill")
                                    }
                                }
                            } label: {
                                Label("Options", systemImage: "ellipsis")
                            }
                        }
                    }
                }
            }
        .navigationDestination(item: $selectedEntryID) { id in
            PolaroidDetailView(
                startIndex: entries.firstIndex(where: { $0.id == id }) ?? 0,
                currentEntryID: $currentDetailEntryID
            )
            .navigationTransition(.zoom(sourceID: currentDetailEntryID ?? id, in: zoomNamespace))
        }
        .onChange(of: selectedEntryID) { _, newID in
            if let newID { currentDetailEntryID = newID }
        }
        }
        .sheet(item: $editingEntry) { item in
            EditPolaroidSheet(entry: item)
        }
        .background(ActivitySheet(items: shareItems, isPresented: $showShareSheet))
        .confirmationDialog(
            selectedIDs.count == 1
                ? NSLocalizedString("Delete 1 photo?", comment: "")
                : String(format: NSLocalizedString("Delete %d photos?", comment: ""), selectedIDs.count),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let ids = selectedIDs
                selectedIDs.removeAll()
                isSelectMode = false
                deleteWithAnimation(ids: ids)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(onClose: { showPaywall = false })
                .environment(PremiumManager.shared)
        }
    }

    // MARK: - Grid cell

    @ViewBuilder
    private func gridCell(for entry: PolaroidEntry) -> some View {
        PolaroidPhotoCell(
            image: entry.image,
            videoURL: entry.videoURL(in: store.videoDirectory),
            isTimelapse: entry.isTimelapse,
            playVideo: entry.isTimelapse,
            developmentProgress: entry.developmentProgress,
            caption: entry.caption,
            backText: entry.backText,
            showMap: entry.showMap,
            coordinate: entry.coordinate,
            timestamp: entry.timestamp,
            filterName: entry.filterName,
            packName: entry.packName,
            fontScale: cellFontScale,
            onDeveloped: {
                entry.developmentProgress = 1.0
            },
            onSingleTap: {
                if isSelectMode {
                    toggleSelection(entry.id)
                } else {
                    selectedEntryID = entry.id
                }
            }
        )
        .aspectRatio(0.75, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            if isSelectMode {
                Image(systemName: selectedIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
                    .padding(6)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .contextMenu {
            Button("Edit Caption & Notes", systemImage: "pencil.and.outline") {
                editingEntry = entry
            }
            Button("Save to Photos", systemImage: "square.and.arrow.down") {
                Task { await saveToPhotosApp([entry]) }
            }
            Button("Share", systemImage: "square.and.arrow.up") {
                Task {
                    shareItems = await prepareShareItems(for: [entry], videoDirectory: store.videoDirectory)
                    showShareSheet = true
                }
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteWithAnimation(ids: [entry.id])
            }
        }
        .scaleEffect(deletingIDs.contains(entry.id) ? 0.5 : 1.0)
        .opacity(deletingIDs.contains(entry.id) ? 0.0 : 1.0)
        .animation(.spring(duration: 0.35, bounce: 0), value: deletingIDs.contains(entry.id))
        .matchedTransitionSource(id: entry.id, in: zoomNamespace)
    }

    // MARK: - Helpers

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    @MainActor
    private func saveToPhotosApp(_ entriesToSave: [PolaroidEntry]) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        var items: [(image: UIImage?, videoURL: URL?)] = []
        for entry in entriesToSave {
            if let filename = entry.videoFilename {
                let srcURL = store.videoDirectory.appendingPathComponent(filename)
                let composited = await compositePolaroidVideo(entry, sourceURL: srcURL) ?? srcURL
                items.append((nil, composited))
            } else {
                items.append((renderPolaroidFrame(entry), nil))
            }
        }
        try? await PHPhotoLibrary.shared().performChanges {
            for item in items {
                if let videoURL = item.videoURL {
                    PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
                } else if let image = item.image {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            }
        }
    }

    private func deleteWithAnimation(ids: Set<UUID>) {
        withAnimation(.spring(duration: 0.35, bounce: 0)) {
            deletingIDs.formUnion(ids)
        }
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            for id in ids {
                if let entry = entries.first(where: { $0.id == id }) {
                    if let filename = entry.videoFilename {
                        store.deleteVideo(filename: filename)
                    }
                    modelContext.delete(entry)
                }
            }
            deletingIDs.subtract(ids)
        }
    }
}

#Preview {
    LibraryView()
        .environment(PhotoStore())
        .environment(PremiumManager.shared)
        .modelContainer(for: PolaroidEntry.self, inMemory: true)
}

import SwiftUI
import Photos

private struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}

struct LibraryView: View {
    @Bindable var store: PhotoStore

    @State private var selectedCategory = "All"
    @State private var editingEntry: PolaroidEntry? = nil
    @State private var detailIndex: Int? = nil
    @State private var showDetail = false
    @State private var isSelectMode = false
    @State private var selectedIDs: Set<UUID> = []
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false
    @State private var deletingIDs: Set<UUID> = []

    @AppStorage("libraryColumnCount") private var columnCount: Int = 3
    @GestureState private var pinchScale: CGFloat = 1.0

    // Ejection animation
    @State private var ejectedEntry: PolaroidEntry? = nil
    @State private var ejectCenterY: CGFloat = -200
    @State private var ejectOffsetX: CGFloat = 0
    @State private var ejectScale: CGFloat = 1.0
    @State private var ejectOpacity: Double = 1.0
    @State private var ejectRotation: Double = 0
    @State private var ejectDevelopmentProgress: Double = 0.0

    private let categories: [(name: String, color: Color)] = [
        ("All",   .gray),
        ("FLÄRN", Color(red: 0.95, green: 0.78, blue: 0.12)),
        ("SOLVA", Color(red: 0.96, green: 0.72, blue: 0.54)),
        ("BRÖKK", Color(red: 0.78, green: 0.43, blue: 0.22)),
        ("VYLUR", Color(red: 0.68, green: 0.27, blue: 0.82)),
        ("GRÅLT", Color(red: 0.28, green: 0.28, blue: 0.28)),
    ]

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
            VStack(spacing: 24) {
                if store.entries.isEmpty {
                    ContentUnavailableView {
                        Label("No Photos Yet", systemImage: "camera")
                    } description: {
                        Text("Take your first photo to see it here")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: gridColumns, spacing: 10) {
                            ForEach(store.entries) { entry in
                                gridCell(for: entry)
                            }
                        }
                        .animation(.spring(duration: 0.35, bounce: 0.2), value: store.entries.map(\.id))
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
            .safeAreaInset(edge: .bottom) {
                if isSelectMode && !selectedIDs.isEmpty {
                    selectActionBar
                }
            }
            .overlay {
                GeometryReader { geo in
                    if let entry = ejectedEntry {
                        PolaroidPhotoCell(
                            image: entry.image,
                            developmentProgress: ejectDevelopmentProgress,
                            animatedExternally: true
                        )
                        .frame(width: 280, height: 340)
                        .rotationEffect(.degrees(ejectRotation))
                        .scaleEffect(ejectScale)
                        .opacity(ejectOpacity)
                        .position(
                            x: geo.size.width / 2 + ejectOffsetX,
                            y: ejectCenterY
                        )
                    }
                }
                .allowsHitTesting(false)
            }
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(alignment: isSelectMode ? .center : .leading, spacing: 0) {
                        Text("Library")
                            .font(.largeTitle.width(.expanded).weight(.bold))
                            .lineHeight(.normal)
                        if !store.entries.isEmpty {
                            if isSelectMode && !selectedIDs.isEmpty {
                                Text("\(selectedIDs.count)/\(store.entries.count)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                let isPlural = store.entries.count == 1 ? "" : "s"
                                Text("\(store.entries.count) item\(isPlural)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        if !store.entries.isEmpty {
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
                                    ForEach(categories, id: \.name) { category in
                                        let isSelected = selectedCategory == category.name
                                        Button {
                                            selectedCategory = category.name
                                        } label: {
                                            if isSelected {
                                                Label(category.name, systemImage: "checkmark")
                                            } else {
                                                Text(category.name)
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                                }

                                Menu {
                                    ForEach(categories, id: \.name) { category in
                                        let isSelected = selectedCategory == category.name
                                        Button {
                                            selectedCategory = category.name
                                        } label: {
                                            HStack {
                                                if isSelected { Image(systemName: "checkmark") }
                                                Text(category.name)
                                            }
                                        }
                                    }
                                } label: {
                                    Label("Sort", systemImage: "arrow.up.arrow.down")
                                }

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
                            } label: {
                                Label("Filter", systemImage: "ellipsis")
                            }
                        }
                    }
                }
                
//                ToolbarItemGroup(placement: .bottomBar) {
//                    Spacer()
//                    Button {
//                        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { columnCount = 1 }
//                    } label: {
//                        Image(systemName: columnCount == 1 ? "rectangle.grid.1x2.fill" : "rectangle.grid.1x2")
//                            .foregroundStyle(columnCount == 1 ? .primary : .secondary)
//                    }
//                    Spacer()
//                    Button {
//                        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { columnCount = 2 }
//                    } label: {
//                        Image(systemName: columnCount == 2 ? "square.grid.2x2.fill" : "square.grid.2x2")
//                            .foregroundStyle(columnCount == 2 ? .primary : .secondary)
//                    }
//                    Spacer()
//                    Button {
//                        withAnimation(.spring(duration: 0.4, bounce: 0.2)) { columnCount = 3 }
//                    } label: {
//                        Image(systemName: columnCount == 3 ? "square.grid.3x2.fill" : "square.grid.3x2")
//                            .foregroundStyle(columnCount == 3 ? .primary : .secondary)
//                    }
//                    Spacer()
//                }
            }
        }
        .onChange(of: store.entries.count) { oldCount, newCount in
            guard newCount > oldCount, let newest = store.entries.first else { return }
            triggerEjectionAnimation(for: newest)
        }
        .interactiveDismissDisabled(showDetail)
        .sheet(item: $editingEntry) { item in
            if let idx = store.entries.firstIndex(where: { $0.id == item.id }) {
                EditPolaroidSheet(entry: $store.entries[idx])
                    .onDisappear { store.persistMetadata() }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ActivitySheet(items: shareItems)
        }
        .confirmationDialog(
            "Delete \(selectedIDs.count) photo\(selectedIDs.count == 1 ? "" : "s")?",
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
        .overlay { detailOverlay }
    }

    @ViewBuilder
    private func gridCell(for entry: PolaroidEntry) -> some View {
        PolaroidPhotoCell(
            image: entry.image,
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
                if let idx = store.entries.firstIndex(where: { $0.id == entry.id }) {
                    store.entries[idx].developmentProgress = 1.0
                    store.persistMetadata()
                }
            },
            onSingleTap: {
                if isSelectMode {
                    toggleSelection(entry.id)
                } else if let idx = store.entries.firstIndex(where: { $0.id == entry.id }) {
                    detailIndex = idx
                    showDetail = true
                }
            }
        )
        .aspectRatio(0.75, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            if isSelectMode {
                Image(systemName: selectedIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedIDs.contains(entry.id) ? .blue : .white)
                    .padding(6)
                    .shadow(color: .black.opacity(0.4), radius: 2)
            }
        }
        .contextMenu {
            Button("Edit Caption & Notes", systemImage: "pencil.and.outline") {
                editingEntry = entry
            }
            Button("Save to Photos", systemImage: "square.and.arrow.down") {
                Task { await saveToPhotosApp([entry.image]) }
            }
            Button("Share", systemImage: "square.and.arrow.up") {
                shareItems = [entry.image]
                showShareSheet = true
            }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                deleteWithAnimation(ids: [entry.id])
            }
        }
        .scaleEffect(deletingIDs.contains(entry.id) ? 0.5 : 1.0)
        .opacity(deletingIDs.contains(entry.id) ? 0.0 : 1.0)
        .animation(.spring(duration: 0.35, bounce: 0), value: deletingIDs.contains(entry.id))
    }

    private var selectActionBar: some View {
        HStack(spacing: 0) {
            Button {
                let images = store.entries.filter { selectedIDs.contains($0.id) }.map { $0.image }
                shareItems = images
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }

            Divider().frame(height: 24)

            Button {
                let images = store.entries.filter { selectedIDs.contains($0.id) }.map { $0.image }
                Task { await saveToPhotosApp(images) }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }

            Divider().frame(height: 24)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // Inline overlay so the library content blurs through behind the detail view
    var detailOverlay: some View {
        Group {
            if showDetail, let idx = detailIndex {
                PolaroidDetailView(
                    store: store,
                    startIndex: idx,
                    onDismiss: { showDetail = false }
                )
            }
        }
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
    private func saveToPhotosApp(_ images: [UIImage]) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        try? await PHPhotoLibrary.shared().performChanges {
            for image in images {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        }
    }

    private func deleteWithAnimation(ids: Set<UUID>) {
        withAnimation(.spring(duration: 0.35, bounce: 0)) {
            deletingIDs.formUnion(ids)
        }
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            store.delete(ids: ids)
            deletingIDs.subtract(ids)
        }
    }

    // MARK: - Ejection animation

    private func triggerEjectionAnimation(for entry: PolaroidEntry) {
        ejectedEntry = entry

        ejectCenterY = -24
        ejectOffsetX = 0
        ejectScale = 0.3
        ejectOpacity = 1.0
        ejectRotation = 0.0
        ejectDevelopmentProgress = 0.0

        withAnimation(.spring(duration: 2.0)) {
            ejectCenterY = 200
            ejectScale = 1.0
        }

        Task {
            try? await Task.sleep(for: .seconds(2.0))

            withAnimation(.linear(duration: 6)) {
                ejectDevelopmentProgress = 1.0
            }

            withAnimation(.easeInOut(duration: 0.5)) {
                ejectCenterY = 600
                ejectOffsetX = -100
                ejectScale = 0.15
                ejectOpacity = 0
            }
            try? await Task.sleep(for: .seconds(0.55))
            ejectedEntry = nil
        }
    }
}

#Preview {
    LibraryView(store: PhotoStore())
}

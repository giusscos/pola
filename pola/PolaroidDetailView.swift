import SwiftUI

struct PolaroidDetailView: View {
    var store: PhotoStore
    let startIndex: Int
    var onDismiss: () -> Void

    @State private var currentIndex: Int
    @State private var dragOffset: CGFloat = 0
    @State private var dragRotation: Double = 0
    @State private var isTransitioning = false
    @State private var appeared = false
    @State private var cardSettleProgress: Double = 0
    @State private var shareItems: [Any] = []
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false

    // Natural stack positions for back cards (rotation, x offset, y offset, scale)
    private let backOffsets: [(rotation: Double, x: CGFloat, y: CGFloat, scale: Double)] = [
        (-6.0, -22, 8,  0.97),
        ( 9.0,  20, 14, 0.94),
    ]

    private let cardWidth: CGFloat = 270
    private let cardHeight: CGFloat = 360

    init(store: PhotoStore, startIndex: Int, onDismiss: @escaping () -> Void) {
        self.store = store
        self.startIndex = startIndex
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(appeared ? 1 : 0)
                    .ignoresSafeArea()

                Color.black
                    .opacity(appeared ? 0.25 : 0)
                    .ignoresSafeArea()
                    .onTapGesture { handleDismiss() }

                if !store.entries.isEmpty {
                    VStack(spacing: 24) {
                        Spacer()
                        cardStack
                        counterLabel
                        Spacer()
                    }
                    .offset(y: appeared ? 0 : 300)
                    .opacity(appeared ? 1 : 0)
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                    appeared = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { handleDismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        Button {
                            guard currentIndex < store.entries.count else { return }
                            let entry = store.entries[currentIndex]
                            Task {
                                shareItems = await prepareShareItems(for: [entry])
                                showShareSheet = true
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        .background(ActivitySheet(items: shareItems, isPresented: $showShareSheet))
        .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                deleteCurrentPhoto()
            }
        }
    }

    // MARK: - Card stack

    private var cardStack: some View {
        ZStack {
            ForEach(Array((1..<min(3, store.entries.count)).reversed()), id: \.self) { stackPos in
                let idx = (currentIndex + stackPos) % store.entries.count
                let entry = store.entries[idx]
                let off = backOffsets[stackPos - 1]
                let dragProgress = min(1.0, abs(dragOffset) / 150.0)
                let prog = max(dragProgress, cardSettleProgress)

                PolaroidPhotoCell(
                    image: entry.image,
                    videoURL: entry.videoURL,
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
                    fontScale: 1.7
                )
                .frame(width: cardWidth, height: cardHeight)
                .scaleEffect(off.scale + prog * (1.0 - off.scale))
                .rotationEffect(.degrees(off.rotation * (1.0 - prog)))
                .offset(
                    x: off.x * CGFloat(1.0 - prog),
                    y: off.y * CGFloat(1.0 - prog)
                )
                .allowsHitTesting(false)
            }

            let entry = store.entries[currentIndex]
            PolaroidPhotoCell(
                image: entry.image,
                videoURL: entry.videoURL,
                isTimelapse: entry.isTimelapse,
                playVideo: true,
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
                    guard currentIndex < store.entries.count else { return }
                    store.entries[currentIndex].developmentProgress = 1.0
                    store.persistMetadata()
                }
            )
            .id(entry.id)
            .frame(width: cardWidth, height: cardHeight)
            .offset(x: dragOffset)
            .rotationEffect(.degrees(dragRotation))
            .simultaneousGesture(swipeGesture)
        }
        .padding(32)
    }

    @ViewBuilder
    private var counterLabel: some View {
        if store.entries.count > 1 {
            Text("\(currentIndex + 1) / \(store.entries.count)")
                .font(.caption.monospaced())
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: - Swipe gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard !isTransitioning else { return }
                dragOffset = value.translation.width
                dragRotation = Double(value.translation.width) / 20.0
            }
            .onEnded { value in
                guard !isTransitioning else { return }
                let threshold: CGFloat = 80
                let predictedVelocity = abs(value.predictedEndLocation.x - value.location.x)
                if abs(value.translation.width) > threshold || predictedVelocity > 100 {
                    let direction: CGFloat = value.translation.width >= 0 ? 1 : -1
                    navigateCard(flyDirection: direction)
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        dragOffset = 0
                        dragRotation = 0
                    }
                }
            }
    }

    // MARK: - Navigation

    private func navigateCard(flyDirection: CGFloat) {
        guard store.entries.count > 1 else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                dragOffset = 0
                dragRotation = 0
            }
            return
        }

        isTransitioning = true
        withAnimation(.easeOut(duration: 0.28)) {
            dragOffset = flyDirection * 650
            dragRotation = Double(flyDirection) * 22
        }

        Task {
            try? await Task.sleep(for: .seconds(0.28))
            cardSettleProgress = 1.0
            currentIndex = (currentIndex + 1) % store.entries.count
            dragOffset = 0
            dragRotation = 0
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                cardSettleProgress = 0
            }
            try? await Task.sleep(for: .seconds(0.5))
            isTransitioning = false
        }
    }

    // MARK: - Delete

    private func deleteCurrentPhoto() {
        guard currentIndex < store.entries.count else { return }
        let id = store.entries[currentIndex].id
        store.delete(ids: [id])
        if store.entries.isEmpty {
            handleDismiss()
        } else {
            currentIndex = min(currentIndex, store.entries.count - 1)
        }
    }

    // MARK: - Dismiss

    private func handleDismiss() {
        withAnimation(.easeOut(duration: 0.25)) {
            appeared = false
        }
        Task {
            try? await Task.sleep(for: .seconds(0.25))
            onDismiss()
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

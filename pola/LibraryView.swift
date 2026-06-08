import SwiftUI

struct LibraryView: View {
    @State private var selectedCategory = "All"
    @State private var capturedPhotos: [UIImage] = []
    @State private var showCamera = false

    // Ejection animation
    @State private var ejectedPhoto: UIImage? = nil
    @State private var ejectCenterY: CGFloat = -200
    @State private var ejectOffsetX: CGFloat = 0
    @State private var ejectScale: CGFloat = 1.0
    @State private var ejectOpacity: Double = 1.0
    @State private var ejectRotation: Double = 0
    // 0.0 = black (undeveloped), 1.0 = fully developed
    @State private var developmentProgress: Double = 0.0

    private let categories: [(name: String, color: Color)] = [
        ("All",           .gray),
        ("Kodak 400",     Color(red: 0.95, green: 0.78, blue: 0.12)),
        ("Kodak Portra",  Color(red: 0.96, green: 0.72, blue: 0.54)),
        ("Cinque Plus",   Color(red: 0.78, green: 0.43, blue: 0.22)),
        ("Lomography",    Color(red: 0.68, green: 0.27, blue: 0.82)),
        ("Cross Process", Color(red: 0.18, green: 0.73, blue: 0.64)),
        ("B&W Classic",   Color(red: 0.28, green: 0.28, blue: 0.28)),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if capturedPhotos.isEmpty {
                    ContentUnavailableView {
                        Label("No Photos Yet", systemImage: "camera")
                    } description: {
                        Text("Tap the camera above to take your first photo")
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(capturedPhotos.indices, id: \.self) { index in
                                PolaroidPhotoCell(image: capturedPhotos[index])
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .overlay {
                GeometryReader { geo in
                    if let photo = ejectedPhoto {
                        PolaroidPhotoCell(image: photo, developmentProgress: developmentProgress)
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
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Library")
                            .font(.largeTitle.width(.expanded).weight(.bold))
                            .lineHeight(.normal)
                        if !capturedPhotos.isEmpty {
                            let isPlural = capturedPhotos.count == 1 ? "" : "s"
                            Text("\(capturedPhotos.count) item\(isPlural)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCamera = true } label: {
                        Image(systemName: "camera.fill")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
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
                                    print(category)
                                    selectedCategory = category.name
                                } label: {
                                    HStack {
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                        }
                                        Text(category.name)
                                    }
                                }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                    } label: {
                        Label("Filter", systemImage: "ellipsis")
                    }
                }
            }
            // Ejector slot rendered on top of the overlay so it masks
            // the polaroid as it slides out — mimics a real camera slot
//            .safeAreaInset(edge: .top) {
//                ejectorSlot
//                    .padding(.top, 8)
//            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { photo in
                triggerEjectionAnimation(for: photo)
            }
        }
    }

    // MARK: - Ejector slot

    private var ejectorSlot: some View {
        ZStack {
            // Body of the slot
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(white: 0.08))
                .frame(height: 14)

            // Dark slit opening in the center
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black)
                .frame(width: 200, height: 5)

            // Subtle top highlight for depth
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                .frame(height: 14)
        }
        .padding(.horizontal, 32)
        .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
    }

    // MARK: - Filter strip

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.name) { category in
                    let isSelected = selectedCategory == category.name
                    Text(category.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(isSelected ? .white : .primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(isSelected ? category.color : Color(.systemGray6))
                        .clipShape(.capsule)
                        .contentShape(.capsule)
                        .onTapGesture {
                            withAnimation(.snappy) {
                                selectedCategory = category.name
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.white)
    }

    // MARK: - Ejection animation

    private func triggerEjectionAnimation(for image: UIImage) {
        capturedPhotos.append(image)
        ejectedPhoto = image

        // Polaroid starts almost entirely hidden behind the ejector slot —
        // only the white bottom border peeks below the slot opening.
        // Frame is 280×340, so half-height = 170. Slot sits at ~Y=12 in
        // the overlay's coordinate space. At ejectCenterY = -155 the
        // polaroid bottom is at 12+3 = 15px — just a sliver visible.
        ejectCenterY = -24
        ejectOffsetX = 0
        ejectScale = 0.3
        ejectOpacity = 1.0
        ejectRotation = 0.0
        developmentProgress = 0.0

        Task {
            try? await Task.sleep(for: .seconds(1.0))
        }
        
        // Phase 1 — slow mechanical ejection: polaroid slides down until from the dynamic island
        withAnimation(.spring(duration: 2.0)) {
            ejectCenterY = 200
            ejectScale = 1.0
//            ejectOpacity = 1.0
        }

        Task {
            // Wait for ejection to finish
            try? await Task.sleep(for: .seconds(2.0))
            
            // Phase 2 — development: image emerges from black, slowly at
            // first then accelerating — mimics Polaroid chemistry.
            withAnimation(.linear(duration: 6)) {
                developmentProgress = 1.0
            }

            // Phase 3 — polaroid flies down into the grid
            withAnimation(.easeInOut(duration: 0.5)) {
                ejectCenterY = 600
                ejectOffsetX = -100
                ejectScale = 0.15
                ejectOpacity = 0
            }
            try? await Task.sleep(for: .seconds(0.55))
            ejectedPhoto = nil
        }
    }
}

#Preview {
    LibraryView()
}

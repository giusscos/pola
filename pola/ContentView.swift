import SwiftUI

enum CameraMode: String, CaseIterable {
    case video = "VIDEO"
    case photo = "PHOTO"
    case timeLapse = "TIME LAPSE"
}

enum ActiveStrip: Equatable {
    case filters
    case colors
    case none
}

struct ContentView: View {
    @State private var cameraManager = CameraManager()
    @AppStorage("captionPromptEnabled") private var captionPromptEnabled: Bool = true
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled: Bool = false
    @State private var store = PhotoStore()
    @State private var pendingEntryID: UUID? = nil
    @State private var pendingCaption: String = ""
    @State private var showCaptionInput = false
    @State private var showLibrary = false
    @State private var showSettings = false
    @State private var selectedFilterName: String? = nil
    @State private var selectedPackName: String? = nil
    @State private var activeStrip: ActiveStrip = .none
    @State private var cameraMode: CameraMode = .photo
    @State private var cameraBlurRadius: CGFloat = 0
    @State private var isModePickerExpanded = false
    @State private var expandedDragBaseIdx = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if cameraManager.isAuthorized {
                    let activeFilter = filmFilters.first { $0.name == selectedFilterName }
                    CameraPreviewView(session: cameraManager.session)
                        .ignoresSafeArea()
                        .blur(radius: cameraBlurRadius)
                        .saturation(activeFilter?.previewSaturation ?? 1.0)
                        .overlay {
                            if let tint = activeFilter?.previewTintColor {
                                tint.opacity(0.10).ignoresSafeArea()
                            }
                        }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.largeTitle)
                        Text("Camera access required")
                            .font(.headline)
                    }
                    .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    Spacer()
                    if showCaptionInput {
                        captionInputCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if activeStrip == .filters {
                        filterStrip
                            .padding(.bottom, 12)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                    } else if activeStrip == .colors {
                        colorStrip
                            .padding(.bottom, 12)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                    }

                    shutterRow
                        .padding(.bottom, 20)
                }
                .animation(.spring(duration: 0.45, bounce: 0.2), value: activeStrip)
                .animation(.spring(duration: 0.4, bounce: 0.1), value: showCaptionInput)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomRow
                    .ignoresSafeArea()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { cameraManager.toggleTorch() } label: {
                        Image(systemName: cameraManager.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .foregroundStyle(cameraManager.isTorchOn ? .yellow : .primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showLibrary) {
            LibraryView(store: store)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .task {
            await cameraManager.configure()
            store.configure(iCloudEnabled: iCloudSyncEnabled)
        }
        .onChange(of: iCloudSyncEnabled) { _, newValue in
            store.configure(iCloudEnabled: newValue)
        }
        .onChange(of: cameraManager.capturedImage) { _, image in
            guard let image else { return }
            cameraManager.capturedImage = nil
            let effect = filmFilters.first(where: { $0.name == selectedFilterName })?.effect
            let processed = effect?.apply(to: image) ?? image
            let entry = PolaroidEntry(
                image: processed,
                filterName: selectedFilterName,
                packName: selectedPackName,
                coordinate: cameraManager.lastCoordinate
            )
            store.add(entry)
            pendingEntryID = entry.id
            if captionPromptEnabled { showCaptionInput = true }
        }
    }

    // MARK: - Filter strip

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filmFilters) { filter in
                    let isSelected = selectedFilterName == filter.name
                    filterCard(filter: filter, isSelected: isSelected) {
                        withAnimation(.snappy) {
                            selectedFilterName = isSelected ? nil : filter.name
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Color strip

    private var colorStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(polaPackColors) { pack in
                    let isSelected = selectedPackName == pack.name
                    packCard(pack: pack, isSelected: isSelected) {
                        withAnimation(.snappy) {
                            selectedPackName = isSelected ? nil : pack.name
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func packCard(pack: PolaPackColor, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? pack.color.opacity(0.3) : Color.white.opacity(0.12))

                ModelSceneView(
                    assetName: pack.usdzName,
                    gestureEnabled: false,
                    autoRotate: true,
                    modelScale: 0.85
                )
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? pack.color : Color.clear, lineWidth: 1.5)
            )

            Text(pack.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .onTapGesture { onTap() }
    }

    @ViewBuilder
    private func filterCard(filter: FilmFilter, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? filter.color.opacity(0.3) : Color.white.opacity(0.12))

                if let usdzName = filter.usdzName {
                    ModelSceneView(
                        assetName: usdzName,
                        gestureEnabled: false,
                        autoRotate: true,
                        modelScale: 0.85
                    )
                } else {
                    Circle()
                        .fill(filter.color)
                        .frame(width: 22, height: 22)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? filter.color : Color.clear, lineWidth: 1.5)
            )

            Text(filter.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .onTapGesture { onTap() }
    }

    // MARK: - Shutter row

    private var shutterRow: some View {
        HStack {
            stripToggleButton(icon: "camera.filters", label: "FILM", strip: .filters)

            Spacer()

            Button { cameraManager.capturePhoto() } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 72, height: 72)
                    .padding(1)
            }
            .glassEffect(.regular, in: .circle)

            Spacer()

            stripToggleButton(icon: "paintpalette.fill", label: "PACK", strip: .colors)
        }
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private func stripToggleButton(icon: String, label: String, strip: ActiveStrip) -> some View {
        let isActive = activeStrip == strip
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.white.opacity(0.28) : Color.white.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.65))
                    .scaleEffect(isActive ? 1.08 : 1.0)
            }
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive ? .white : .white.opacity(0.55))
        }
        .onTapGesture {
            withAnimation(.spring(duration: 0.45, bounce: 0.2)) {
                activeStrip = activeStrip == strip ? .none : strip
            }
        }
    }

    // MARK: - Bottom row

    private var bottomRow: some View {
        HStack(spacing: 0) {
            Button { showLibrary = true } label: {
                let recent = Array(store.entries.prefix(2))
                ZStack {
                    if recent.isEmpty {
                        Circle()
                            .fill(.white.opacity(0.15))
                            .frame(width: 44, height: 44)
                            .overlay {
                                Image(systemName: "photo.on.rectangle")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white)
                            }
                    }
                    if recent.count >= 2 {
                        miniPolaroid(image: recent[1].image, packName: recent[1].packName)
                            .rotationEffect(.degrees(-9))
                            .scaleEffect(0.85)
                            .opacity(0.85)
                            .offset(x: -5, y: 4)
                            .id(recent[1].id)
                    }
                    if let front = recent.first {
                        miniPolaroid(image: front.image, packName: front.packName)
                            .rotationEffect(.degrees(5))
                            .id(front.id)
                            .transition(.asymmetric(
                                insertion: .scale(scale: 0.3).combined(with: .opacity),
                                removal: .identity
                            ))
                    }
                }
                .animation(.spring(duration: 0.5, bounce: 0.4), value: recent.first?.id)
                .frame(width: 44, height: 44)
            }
            .frame(width: isModePickerExpanded ? 0 : 72, alignment: .leading)
            .opacity(isModePickerExpanded ? 0 : 1)
            .clipped()

            modePicker
                .frame(maxWidth: .infinity)

            Button { flipCameraWithAnimation() } label: {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                    }
            }
            .frame(width: isModePickerExpanded ? 0 : 72, alignment: .trailing)
            .opacity(isModePickerExpanded ? 0 : 1)
            .clipped()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.black)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.3, bounce: 0.1), value: isModePickerExpanded)
    }

    // MARK: - Mode picker

    private let modeItemWidth: CGFloat = 90

    private var modePicker: some View {
        GeometryReader { proxy in
            let allModes = CameraMode.allCases
            let selectedIdx = CGFloat(allModes.firstIndex(of: cameraMode) ?? 0)
            let centerOffset = proxy.size.width / 2 - (selectedIdx + 0.5) * modeItemWidth

            HStack(spacing: 0) {
                ForEach(allModes, id: \.self) { mode in
                    modeLabel(for: mode)
                        .frame(width: modeItemWidth)
                        .simultaneousGesture(TapGesture().onEnded {
                            withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                                cameraMode = mode
                            }
                        })
                }
            }
            .offset(x: centerOffset)
            .animation(.spring(duration: 0.3, bounce: 0.1), value: cameraMode)
        }
        .frame(height: 34)
        .sensoryFeedback(.selection, trigger: cameraMode)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.18),
                    .init(color: .black, location: 0.82),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        .onLongPressGesture(
            minimumDuration: 0.35,
            maximumDistance: 500,
            perform: {
                withAnimation(.spring(duration: 0.3, bounce: 0.1)) { isModePickerExpanded = true }
                expandedDragBaseIdx = CameraMode.allCases.firstIndex(of: cameraMode) ?? 0
            },
            onPressingChanged: { pressing in
                if !pressing, isModePickerExpanded {
                    withAnimation(.spring(duration: 0.3, bounce: 0.1)) { isModePickerExpanded = false }
                }
            }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    guard isModePickerExpanded else { return }
                    let steps = Int(round(-value.translation.width / modeItemWidth))
                    let modes = CameraMode.allCases
                    let newIdx = max(0, min(modes.count - 1, expandedDragBaseIdx + steps))
                    guard cameraMode != modes[newIdx] else { return }
                    withAnimation(.spring(duration: 0.15, bounce: 0)) { cameraMode = modes[newIdx] }
                }
                .onEnded { value in
                    guard !isModePickerExpanded else { return }
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 15 else { return }
                    let modes = CameraMode.allCases
                    guard let idx = modes.firstIndex(of: cameraMode) else { return }
                    withAnimation(.spring(duration: 0.3)) {
                        if value.translation.width < 0, idx < modes.count - 1 {
                            cameraMode = modes[idx + 1]
                        } else if value.translation.width > 0, idx > 0 {
                            cameraMode = modes[idx - 1]
                        }
                    }
                }
        )
    }

    private func modeLabel(for mode: CameraMode) -> some View {
        let isSelected = cameraMode == mode
        return Text(mode.rawValue)
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.3)
            .lineLimit(1)
            .foregroundStyle(isSelected ? Color.yellow : Color.white.opacity(0.55))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                if isSelected {
                    Color.clear.glassEffect(.regular, in: .capsule)
                }
            }
            .scaleEffect(isSelected ? 1.0 : 0.82)
    }

    // MARK: - Mini polaroid thumbnail

    @ViewBuilder
    private func miniPolaroid(image: UIImage, packName: String?) -> some View {
        let borderColor = polaPackColors.first(where: { $0.name == packName })?.color ?? .white
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 28, height: 28)
            .clipped()
            .padding(.horizontal, 3)
            .padding(.top, 3)
            .padding(.bottom, 10)
            .background(borderColor)
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
    }

    // MARK: - Caption input

    private var captionInputCard: some View {
        VStack(spacing: 12) {
            TextField("Add a note...", text: $pendingCaption)
                .font(.custom("Bradley Hand", size: 17))
                .padding(10)
                .background(Color(.systemGray5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .submitLabel(.done)
                .onSubmit { commitCaption() }

            HStack {
                Button("Skip") { commitCaption() }
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { commitCaption() }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            .font(.callout)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }

    private func commitCaption() {
        if let id = pendingEntryID, let idx = store.entries.firstIndex(where: { $0.id == id }) {
            store.entries[idx].caption = pendingCaption
            store.persistMetadata()
        }
        pendingCaption = ""
        pendingEntryID = nil
        withAnimation { showCaptionInput = false }
    }

    // MARK: - Flip animation

    private func flipCameraWithAnimation() {
        withAnimation(.easeIn(duration: 0.15)) {
            cameraBlurRadius = 20
        } completion: {
            cameraManager.flipCamera()
            withAnimation(.easeOut(duration: 0.3)) {
                cameraBlurRadius = 0
            }
        }
    }
}

#Preview {
    ContentView()
}

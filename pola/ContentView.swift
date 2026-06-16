import AVFoundation
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
    @AppStorage("timelapseInterval") private var timelapsInterval: Double = 5
    @AppStorage("timelapseDuration") private var timelapseDuration: Double = 60
    @AppStorage("timelapseSaveAsVideo") private var timelapseSaveAsVideo: Bool = false
    @State private var showTimeLapseSettings = false
    @State private var shootingTimerDelay: Int = 0
    @State private var isCountingDown = false
    @State private var countdownValue = 0
    @State private var countdownTask: Task<Void, Never>? = nil
    @State private var shutterScaleTrigger = false
    @Namespace private var sheetZoom
    @Namespace private var zoomNamespace
    @Environment(PremiumManager.self) private var premium
    @State private var showPaywall = false

    private var activeFilter: FilmFilter? {
        filmFilters.first { $0.name == selectedFilterName }
    }

    @ViewBuilder
    private var modeToolbarButton: some View {
        if cameraMode == .video {
            let icon = cameraManager.isAudioEnabled ? "mic.fill" : "mic.slash.fill"
            let tint: Color = cameraManager.isAudioEnabled ? .primary : .red
            Button { cameraManager.toggleAudio() } label: {
                Image(systemName: icon).foregroundStyle(tint)
            }
        } else if cameraMode == .timeLapse {
            Button { showTimeLapseSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .matchedTransitionSource(id: "timelapse", in: sheetZoom)
        }
    }

    @ViewBuilder
    private var timerDelayButton: some View {
        if cameraMode != .timeLapse {
            Button {
                switch shootingTimerDelay {
                case 0: shootingTimerDelay = 3
                case 3: shootingTimerDelay = 5
                case 5: shootingTimerDelay = 10
                default: shootingTimerDelay = 0
                }
            } label: {
                if shootingTimerDelay > 0 {
                    Text("\(shootingTimerDelay)s")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.yellow)
                } else {
                    Image(systemName: "timer")
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if cameraManager.isAuthorized {
                    VStack(spacing: 0) {
                        CameraPreviewView(session: cameraManager.session)
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .blur(radius: cameraBlurRadius)
                            .saturation(activeFilter?.previewSaturation ?? 1.0)
                            .overlay {
                                if let tint = activeFilter?.previewTintColor {
                                    // Stronger tint so the filter is visible in the viewfinder
                                    tint.opacity(0.20).blendMode(.multiply)
                                }
                            }
                            .overlay {
                                // Vignette hint in preview when a filter is active
                                if activeFilter?.effect != nil {
                                    RadialGradient(
                                        colors: [.clear, .black.opacity(0.50)],
                                        center: .center,
                                        startRadius: 80,
                                        endRadius: 300
                                    )
                                    .allowsHitTesting(false)
                                }
                            }
                            .overlay {
                                if isCountingDown, countdownValue > 0 {
                                    ZStack {
                                        Color.black.opacity(0.25)
                                        Text("\(countdownValue)")
                                            .font(.system(size: 100, weight: .ultraLight))
                                            .foregroundStyle(.white)
                                            .shadow(color: .black.opacity(0.6), radius: 8)
                                            .contentTransition(.numericText(countsDown: true))
                                            .animation(.easeInOut(duration: 0.3), value: countdownValue)
                                    }
                                }
                            }
                        Spacer()
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

                    if cameraManager.availableZoomOptions.count > 1 {
                        zoomControlRow
                            .padding(.bottom, 8)
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
                    .matchedTransitionSource(id: "settings", in: sheetZoom)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { cameraManager.toggleTorch() } label: {
                        Image(systemName: cameraManager.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .foregroundStyle(cameraManager.isTorchOn ? .yellow : .primary)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    timerDelayButton
                }

                ToolbarItem(placement: .topBarTrailing) {
                    modeToolbarButton
                }
            }
        }
        .fullScreenCover(isPresented: $showLibrary) {
            LibraryView(store: store)
                .environment(PremiumManager.shared)
                .navigationTransition(.zoom(sourceID: "library", in: sheetZoom))
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(PremiumManager.shared)
                .navigationTransition(.zoom(sourceID: "settings", in: sheetZoom))
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(PremiumManager.shared)
        }
        .sheet(isPresented: $showTimeLapseSettings) {
            TimeLapseSettingsView(interval: $timelapsInterval, duration: $timelapseDuration, saveAsVideo: $timelapseSaveAsVideo)
                .navigationTransition(.zoom(sourceID: "timelapse", in: sheetZoom))
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
            let effect = activeFilter?.effect
            let processed = effect?.apply(to: image) ?? image
            let entry = PolaroidEntry(
                image: processed,
                filterName: selectedFilterName,
                packName: selectedPackName,
                coordinate: cameraManager.lastCoordinate
            )
            store.add(entry)
            pendingEntryID = entry.id
            // Suppress caption prompt for individual timelapse frames
            if captionPromptEnabled && !cameraManager.isTimelapsing { showCaptionInput = true }
        }
        .onChange(of: cameraManager.capturedVideoURL) { _, url in
            guard let url else { return }
            cameraManager.capturedVideoURL = nil
            let thumbnail = videoThumbnail(from: url) ?? UIImage()
            let effect = activeFilter?.effect
            let processed = effect?.apply(to: thumbnail) ?? thumbnail
            let entry = PolaroidEntry(
                image: processed,
                videoURL: url,
                filterName: selectedFilterName,
                packName: selectedPackName,
                coordinate: cameraManager.lastCoordinate
            )
            store.add(entry)
            pendingEntryID = entry.id
            if captionPromptEnabled { showCaptionInput = true }
        }
        .onChange(of: cameraManager.timelapseVideoFrames) { _, frames in
            guard let frames else { return }
            cameraManager.timelapseVideoFrames = nil
            let effect = activeFilter?.effect
            let processed = frames.map { effect?.apply(to: $0) ?? $0 }
            let coord = cameraManager.lastCoordinate
            Task {
                guard let videoURL = await composeVideo(from: processed) else { return }
                let thumbnail = processed.first ?? UIImage()
                let entry = PolaroidEntry(
                    image: thumbnail,
                    videoURL: videoURL,
                    isTimelapse: true,
                    filterName: selectedFilterName,
                    packName: selectedPackName,
                    coordinate: coord
                )
                await MainActor.run {
                    store.add(entry)
                    pendingEntryID = entry.id
                    if captionPromptEnabled { showCaptionInput = true }
                }
            }
        }
    }

    // MARK: - Filter strip

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(filmFilters) { filter in
                    let isSelected = selectedFilterName == filter.name
                    let locked = !premium.isPremium
                    filterCard(filter: filter, isSelected: isSelected, locked: locked) {
                        if locked {
                            showPaywall = true
                        } else {
                            withAnimation(.snappy) {
                                selectedFilterName = isSelected ? nil : filter.name
                            }
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
                    let locked = !premium.isPremium
                    packCard(pack: pack, isSelected: isSelected, locked: locked) {
                        if locked {
                            showPaywall = true
                        } else {
                            withAnimation(.snappy) {
                                selectedPackName = isSelected ? nil : pack.name
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func packCard(pack: PolaPackColor, isSelected: Bool, locked: Bool = false, onTap: @escaping () -> Void) -> some View {
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

                if locked {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.5))
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? pack.color : Color.clear, lineWidth: 1.5)
            )

            Text(pack.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(locked ? .white.opacity(0.45) : .white)
                .lineLimit(1)
        }
        .onTapGesture { onTap() }
    }

    @ViewBuilder
    private func filterCard(filter: FilmFilter, isSelected: Bool, locked: Bool = false, onTap: @escaping () -> Void) -> some View {
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

                if locked {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.5))
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
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
                .foregroundStyle(locked ? .white.opacity(0.45) : .white)
                .lineLimit(1)
        }
        .onTapGesture { onTap() }
    }

    // MARK: - Shutter row

    private var shutterRow: some View {
        HStack {
            stripToggleButton(icon: "camera.filters", label: "FILM", strip: .filters)

            Spacer()

            shutterButton

            Spacer()

            stripToggleButton(icon: "paintpalette.fill", label: "PACK", strip: .colors)
        }
        .padding(.horizontal, 40)
    }

    private var shutterButton: some View {
        Button {
            handleShutter()
        } label: {
            ZStack {
                Circle()
                    .fill(cameraMode == .video ? Color.red : Color.white)
                    .frame(width: 72, height: 72)
                    .padding(1)

                if cameraMode == .video && cameraManager.isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.white)
                        .frame(width: 22, height: 22)
                        .transition(.scale.combined(with: .opacity))
                } else if cameraMode == .timeLapse {
                    VStack(spacing: 1) {
                        Text("\(Int(timelapsInterval))s")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.black)
                        if cameraManager.isTimelapsing {
                            Text("\(cameraManager.timelapsePhotoCount)/\(cameraManager.timelapseMaxPhotos)")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.black.opacity(0.7))
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                // Timelapse progress ring — animates linearly between each shot
                if cameraMode == .timeLapse && cameraManager.isTimelapsing {
                    TimelineView(.animation(minimumInterval: 1 / 30, paused: false)) { context in
                        let elapsed = context.date.timeIntervalSince(cameraManager.timelapsePhaseStart)
                        let progress = min(1.0, max(0.0, elapsed / timelapsInterval))
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 82, height: 82)
                            .rotationEffect(.degrees(-90))
                    }
                }
            }
            .animation(.spring(duration: 0.4, bounce: 0.35), value: cameraMode)
        }
        .scaleEffect(shutterScaleTrigger ? 0.88 : 1.0)
        .animation(.spring(duration: 0.45, bounce: 0.5), value: shutterScaleTrigger)
        .onChange(of: cameraMode) {
            shutterScaleTrigger = true
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                shutterScaleTrigger = false
            }
        }
        .glassEffect(.regular, in: .circle)
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

    // MARK: - Zoom controls

    private var zoomControlRow: some View {
        HStack(spacing: 6) {
            ForEach(cameraManager.availableZoomOptions) { option in
                let isSelected = cameraManager.currentZoomFactor == option.factor
                Button {
                    cameraManager.switchZoom(to: option)
                } label: {
                    Text(option.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.yellow)
                                    .matchedGeometryEffect(id: "zoomSelector", in: zoomNamespace)
                            }
                        }
                }
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: cameraManager.currentZoomFactor)
        .sensoryFeedback(.selection, trigger: cameraManager.currentZoomFactor)
        .disabled(cameraManager.isRecording || cameraManager.isTimelapsing)
        .opacity((cameraManager.isRecording || cameraManager.isTimelapsing) ? 0.4 : 1.0)
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
            .matchedTransitionSource(id: "library", in: sheetZoom)
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
                            UISelectionFeedbackGenerator().selectionChanged()
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
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(duration: 0.15, bounce: 0)) { cameraMode = modes[newIdx] }
                }
                .onEnded { value in
                    guard !isModePickerExpanded else { return }
                    guard abs(value.translation.width) > abs(value.translation.height),
                          abs(value.translation.width) > 15 else { return }
                    let modes = CameraMode.allCases
                    guard let idx = modes.firstIndex(of: cameraMode) else { return }
                    var changed = false
                    withAnimation(.spring(duration: 0.3)) {
                        if value.translation.width < 0, idx < modes.count - 1 {
                            cameraMode = modes[idx + 1]; changed = true
                        } else if value.translation.width > 0, idx > 0 {
                            cameraMode = modes[idx - 1]; changed = true
                        }
                    }
                    if changed { UISelectionFeedbackGenerator().selectionChanged() }
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

    // MARK: - Video helpers

    private func videoThumbnail(from url: URL) -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        var time = CMTime.zero
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: &time) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func composeVideo(from frames: [UIImage]) async -> URL? {
        guard let first = frames.first else { return nil }

        // Scale to at most 1080p on the longer side, with even pixel dimensions (H.264 requirement)
        let displaySize = first.size
        let maxPx: CGFloat = 1080
        let scale = min(1.0, maxPx / max(displaySize.width, displaySize.height))
        let size = CGSize(
            width: floor((displaySize.width * scale) / 2) * 2,
            height: floor((displaySize.height * scale) / 2) * 2
        )

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else { return nil }
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
        )
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let fps: Int32 = 5
        for (i, frame) in frames.enumerated() {
            let time = CMTime(value: CMTimeValue(i), timescale: fps)
            if let buf = pixelBuffer(from: frame, size: size) {
                while !input.isReadyForMoreMediaData {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
                adaptor.append(buf, withPresentationTime: time)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        return writer.error == nil ? outputURL : nil
    }

    private func pixelBuffer(from image: UIImage, size: CGSize) -> CVPixelBuffer? {
        // Draw through UIKit so imageOrientation is applied correctly
        let renderer = UIGraphicsImageRenderer(size: size)
        let normalized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = normalized.cgImage else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                            kCVPixelFormatType_32ARGB, nil, &buffer)
        guard let buf = buffer else { return nil }
        CVPixelBufferLockBaseAddress(buf, [])
        defer { CVPixelBufferUnlockBaseAddress(buf, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buf),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buf),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
        return buf
    }

    // MARK: - Shutter actions

    private func handleShutter() {
        if cameraMode == .video && cameraManager.isRecording {
            cameraManager.stopVideoRecording()
            return
        }
        if cameraMode == .timeLapse && cameraManager.isTimelapsing {
            cameraManager.stopTimelapse()
            return
        }
        if isCountingDown {
            countdownTask?.cancel()
            countdownTask = nil
            withAnimation { isCountingDown = false }
            countdownValue = 0
            return
        }
        guard shootingTimerDelay > 0 else {
            executeCapture()
            return
        }
        isCountingDown = true
        countdownValue = shootingTimerDelay
        countdownTask = Task {
            var count = shootingTimerDelay
            while count > 0 {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                count -= 1
                await MainActor.run { countdownValue = count }
            }
            await MainActor.run {
                isCountingDown = false
                countdownValue = 0
                executeCapture()
            }
        }
    }

    private func executeCapture() {
        switch cameraMode {
        case .photo:
            cameraManager.capturePhoto()
        case .video:
            cameraManager.startVideoRecording()
        case .timeLapse:
            cameraManager.startTimelapse(interval: timelapsInterval, duration: timelapseDuration, saveAsVideo: timelapseSaveAsVideo)
        }
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

private struct TimeLapseSettingsView: View {
    @Binding var interval: Double
    @Binding var duration: Double
    @Binding var saveAsVideo: Bool
    @Environment(\.dismiss) private var dismiss

    private var totalPhotos: Int { max(1, Int(duration / interval)) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Interval") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Between photos: \(Int(interval))s")
                            .font(.subheadline)
                        Slider(value: $interval, in: 1...60, step: 1)
                    }
                    .padding(.vertical, 4)
                }
                Section("Duration") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Total duration: \(Int(duration))s")
                            .font(.subheadline)
                        Slider(value: $duration, in: 10...3600, step: 10)
                    }
                    .padding(.vertical, 4)
                }
                Section("Output") {
                    Toggle(isOn: $saveAsVideo) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save as video polaroid")
                            Text(saveAsVideo
                                 ? "All frames combined into one video"
                                 : "\(totalPhotos) separate photo polaroids")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Text("Total frames: \(totalPhotos)")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Time Lapse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

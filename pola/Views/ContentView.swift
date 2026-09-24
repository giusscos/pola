import AVFoundation
import StoreKit
import SwiftData
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
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(PhotoStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PolaroidEntry.timestamp, order: .reverse) private var allEntries: [PolaroidEntry]
    @State private var pendingEntryID: UUID? = nil
    @State private var pendingCaption: String = ""
    @State private var showCaptionInput = false
    @State private var showLibrary = false
    @State private var libraryDetailOpen = false
    @State private var librarySelectMode = false
    @State private var showSettings = false
    @State private var selectedFilterName: String? = nil
    @State private var selectedPackName: String? = nil
    @State private var activeStrip: ActiveStrip = .none
    @State private var cameraMode: CameraMode = .photo
    @State private var cameraBlurRadius: CGFloat = 0
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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("totalPhotosCount") private var totalPhotosCount: Int = 0
    @AppStorage("defaultFilter") private var defaultFilter: String = "None"
    @AppStorage("hasAnsweredLocationPrompt") private var hasAnsweredLocationPrompt = false
    @AppStorage("hasSeenMilestonePaywall") private var hasSeenMilestonePaywall = false
    @AppStorage(FilmDrops.seenKey) private var seenDropID = 0
    // Drives the paywall sheet via `.sheet(item:)` so the sheet always sees the context it was opened with.
    @State private var paywallContext: PaywallContext? = nil
    // Paywall requested from inside the Filters sheet; shown once that sheet has finished dismissing.
    @State private var pendingPaywallContext: PaywallContext? = nil
    @State private var showLocationPrompt = false
    @State private var didApplyDefaultFilter = false
    @State private var showFiltersSheet = false
    @State private var printingEntry: PolaroidEntry? = nil
    @State private var printingEntries: [PolaroidEntry] = []
    @State private var timelapsePendingEntries: [PolaroidEntry] = []
    @State private var isInTimelapse = false
    @State private var isProcessingTimelapse = false
    @AppStorage("printAnimationEnabled") private var printAnimationEnabled: Bool = true
    @AppStorage("frontCameraMirrored") private var frontCameraMirrored: Bool = true

    private var activeFilter: FilmFilter? {
        filmFilter(named: selectedFilterName)
    }

    private var isPreviewingLockedFilter: Bool {
        activeFilter?.isLocked(for: premium) == true
    }

    private func presentPaywall(_ context: PaywallContext) {
        paywallContext = context
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
                        CameraPreviewView(
                            session: cameraManager.session,
                            mirrorFrontCamera: frontCameraMirrored,
                            isFrontCamera: cameraManager.currentPosition == .front
                        )
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
                            .overlay(alignment: .top) {
                                if isPreviewingLockedFilter, let filter = activeFilter {
                                    lockedPreviewBanner(for: filter)
                                        .padding(.top, 12)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            .animation(.spring(duration: 0.4, bounce: 0.2), value: isPreviewingLockedFilter)
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
                    if showLocationPrompt && printingEntry == nil && !showCaptionInput {
                        locationPromptCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if showCaptionInput && printingEntry == nil {
                        captionInputCard
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if activeStrip == .colors {
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
                }
                .animation(.spring(duration: 0.45, bounce: 0.2), value: activeStrip)
                .animation(.spring(duration: 0.4, bounce: 0.1), value: showCaptionInput)
                .animation(.spring(duration: 0.4, bounce: 0.1), value: showLocationPrompt)
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

                ToolbarItem(placement: .topBarTrailing) {
                    Button { flipCameraWithAnimation() } label: {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showLibrary) {
            LibraryView(isDetailOpen: $libraryDetailOpen, isSelectMode: $librarySelectMode)
                .ignoresSafeArea()
                .environment(PremiumManager.shared)
                .navigationTransition(.zoom(sourceID: "library", in: sheetZoom))
                .interactiveDismissDisabled(libraryDetailOpen || librarySelectMode)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environment(PremiumManager.shared)
                .environment(LanguageManager.shared)
                .navigationTransition(.zoom(sourceID: "settings", in: sheetZoom))
        }
        .sheet(item: $paywallContext) { context in
            PaywallView(
                context: context,
                previewImage: context.highlighted == .filmStocks ? allEntries.first?.image : nil,
                onClose: { paywallContext = nil }
            )
            .environment(PremiumManager.shared)
        }
        .sheet(isPresented: $showFiltersSheet, onDismiss: {
            if let pending = pendingPaywallContext {
                pendingPaywallContext = nil
                presentPaywall(pending)
            }
        }) {
            FiltersView(selectedFilterName: $selectedFilterName, selectedPackName: $selectedPackName, onPaywallRequested: { context in
                pendingPaywallContext = context
                showFiltersSheet = false
            })
            .environment(PremiumManager.shared)
            .navigationTransition(.zoom(sourceID: "filtersSheet", in: sheetZoom))
        }
        .sheet(isPresented: $showTimeLapseSettings) {
            TimeLapseSettingsView(interval: $timelapsInterval, duration: $timelapseDuration, saveAsVideo: $timelapseSaveAsVideo)
                .navigationTransition(.zoom(sourceID: "timelapse", in: sheetZoom))
        }
        .overlay {
            if let entry = printingEntry {
                PolaroidPrintAnimationView(
                    entry: entry,
                    captionEnabled: captionPromptEnabled,
                    onComplete: {
                        printingEntry = nil
                        captureFlowFinished()
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .overlay {
            if !printingEntries.isEmpty {
                MultiPolaroidPrintAnimationView(
                    entries: printingEntries,
                    onComplete: {
                        printingEntries = []
                        captureFlowFinished()
                    }
                )
                .ignoresSafeArea()
                .transition(.opacity)
            }
        }
        .overlay {
            if isProcessingTimelapse {
                ProcessingTimeLapseOverlay()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .animation(.easeIn(duration: 0.15), value: printingEntry == nil)
        .animation(.easeIn(duration: 0.15), value: printingEntries.isEmpty)
        .animation(.easeInOut(duration: 0.25), value: isProcessingTimelapse)
        .task {
            applyDefaultFilterIfNeeded()
            if hasSeenOnboarding {
                await cameraManager.configure()
            }
            store.migrateIfNeeded(into: modelContext)
        }
        .onChange(of: premium.isPremium) { _, isPremium in
            if isPremium { applyDefaultFilterIfNeeded() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Catch renewals, expirations and refunds that happened while the app was in the background.
            if phase == .active {
                Task { await premium.refreshPurchaseStatus() }
            }
        }
        .onChange(of: cameraMode) { _, mode in
            if mode == .video {
                Task { await cameraManager.prepareMicrophone() }
            }
        }
        .onChange(of: hasSeenOnboarding) { _, newValue in
            if newValue {
                Task { await cameraManager.configure() }
            }
        }
        .onChange(of: showLibrary) { _, isShowing in
            if isShowing {
                cameraManager.stop()
            } else {
                cameraManager.resume()
            }
        }
        .onChange(of: frontCameraMirrored) { _, mirrored in
            cameraManager.setFrontCameraMirrored(mirrored)
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
            modelContext.insert(entry)
            pendingEntryID = entry.id
            if isInTimelapse {
                timelapsePendingEntries.append(entry)
            } else {
                totalPhotosCount += 1
                Analytics.track(.photoCaptured, ["filter": selectedFilterName ?? "none"])
                if printAnimationEnabled {
                    printingEntry = entry
                } else if captionPromptEnabled {
                    showCaptionInput = true
                } else {
                    captureFlowFinished()
                }
            }
        }
        .onChange(of: cameraManager.capturedVideoURL) { _, url in
            guard let url else { return }
            cameraManager.capturedVideoURL = nil
            Task {
                let thumbnail = await videoThumbnail(from: url) ?? UIImage()
                let effect = activeFilter?.effect
                let processed = effect?.apply(to: thumbnail) ?? thumbnail
                let entry = PolaroidEntry(
                    image: processed,
                    filterName: selectedFilterName,
                    packName: selectedPackName,
                    coordinate: cameraManager.lastCoordinate
                )
                entry.videoFilename = store.saveVideo(from: url, id: entry.id)
                modelContext.insert(entry)
                pendingEntryID = entry.id
                totalPhotosCount += 1
                Analytics.track(.videoCaptured, ["filter": selectedFilterName ?? "none"])
                if printAnimationEnabled {
                    printingEntry = entry
                } else if captionPromptEnabled {
                    showCaptionInput = true
                } else {
                    captureFlowFinished()
                }
            }
        }
        .onChange(of: cameraManager.timelapseVideoFrames) { _, frames in
            guard let frames else { return }
            cameraManager.timelapseVideoFrames = nil
            let effect = activeFilter?.effect
            let processed = frames.map { effect?.apply(to: $0) ?? $0 }
            let coord = cameraManager.lastCoordinate
            isProcessingTimelapse = true
            Task {
                guard let videoURL = await composeVideo(from: processed) else {
                    await MainActor.run { isProcessingTimelapse = false }
                    return
                }
                let thumbnail = processed.first ?? UIImage()
                await MainActor.run {
                    isProcessingTimelapse = false
                    let entry = PolaroidEntry(
                        image: thumbnail,
                        isTimelapse: true,
                        filterName: selectedFilterName,
                        packName: selectedPackName,
                        coordinate: coord
                    )
                    entry.videoFilename = store.saveVideo(from: videoURL, id: entry.id)
                    modelContext.insert(entry)
                    pendingEntryID = entry.id
                    Analytics.track(.timelapseCaptured, ["filter": selectedFilterName ?? "none"])
                    if printAnimationEnabled {
                        printingEntry = entry
                    } else if captionPromptEnabled {
                        showCaptionInput = true
                    } else {
                        captureFlowFinished()
                    }
                }
            }
        }
        .onChange(of: cameraManager.isTimelapsing) { _, isActive in
            if isActive {
                isInTimelapse = true
                timelapsePendingEntries = []
            } else {
                // Flip the local flag inside a Task so that the capturedImage onChange
                // for the final frame (batched in the same SwiftUI update) still sees
                // isInTimelapse = true and appends to the stack before we collect it.
                Task { @MainActor in
                    isInTimelapse = false
                    guard !timelapsePendingEntries.isEmpty else { return }
                    totalPhotosCount += timelapsePendingEntries.count
                    Analytics.track(.timelapseCaptured, ["filter": selectedFilterName ?? "none"])
                    if printAnimationEnabled {
                        printingEntries = timelapsePendingEntries
                    } else {
                        captureFlowFinished()
                    }
                    timelapsePendingEntries = []
                }
            }
        }
    }

    // MARK: - Filter strip

    private var filterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(allFilters) { filter in
                    let isSelected = selectedFilterName == filter.name
                    let locked = filter.isLocked(for: premium)
                    filterCard(filter: filter, isSelected: isSelected, locked: locked) {
                        if locked {
                            presentPaywall(.filter(filter.name))
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
                    let locked = pack.isLocked(for: premium)
                    packCard(pack: pack, isSelected: isSelected, locked: locked) {
                        if locked {
                            presentPaywall(.feature(.frameColors))
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

                Circle()
                    .fill(pack.color)
                    .frame(width: 30, height: 30)
                    .shadow(color: pack.color.opacity(0.5), radius: 4, x: 0, y: 2)

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

                if let imageName = filter.imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
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
        shutterButton
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
            .frame(width: 82, height: 82)
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
        .modifier(PolaGlassEffectModifier())
    }

    private var filmButton: some View {
        let isActive = selectedFilterName != nil
        return VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(isActive ? Color.white.opacity(0.28) : Color.white.opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: "camera.filters")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isActive ? .white : .white.opacity(0.65))
                    .scaleEffect(isActive ? 1.08 : 1.0)
            }
            .overlay(alignment: .topTrailing) {
                if seenDropID < FilmDrops.latestDropID {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.8, blue: 0.3))
                        .frame(width: 10, height: 10)
                        .overlay(Circle().strokeBorder(.black, lineWidth: 1.5))
                        .offset(x: -2, y: 2)
                }
            }
            Text("FILM")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive ? .white : .white.opacity(0.55))
        }
        .matchedTransitionSource(id: "filtersSheet", in: sheetZoom)
        .onTapGesture {
            showFiltersSheet = true
        }
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
            Text(LocalizedStringKey(label))
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
        VStack(spacing: 0) {
            shutterRow
                .padding(.top, 14)
                .padding(.bottom, 14)

            HStack(spacing: 0) {
            Button { showLibrary = true } label: {
                let excludeID = printingEntry?.id
                let recent = Array(allEntries.filter { $0.id != excludeID }.prefix(2))

                TimelineView(.periodic(from: .now, by: 1.0)) { _ in
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
                        if recent.count >= 2, let img = recent[1].image {
                            miniPolaroid(image: img, entry: recent[1])
                                .rotationEffect(.degrees(-9))
                                .scaleEffect(0.85)
                                .opacity(0.85)
                                .offset(x: -5, y: 4)
                                .id(recent[1].id)
                        }
                        if let front = recent.first, let img = front.image {
                            miniPolaroid(image: img, entry: front)
                                .rotationEffect(.degrees(5))
                                .id(front.id)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .identity
                                ))
                        }
                    }
                    .animation(.spring(duration: 0.5, bounce: 0.4), value: recent.first?.id)
                    .frame(width: 44, height: 44)
                }
            }
            .matchedTransitionSource(id: "library", in: sheetZoom)
            .frame(width: 72, alignment: .leading)

                modePicker
                    .frame(maxWidth: .infinity)

                filmButton
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .background(.black)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        CameraModeSelectorView(cameraMode: $cameraMode)
            .frame(height: 44)
    }

    // MARK: - Mini polaroid thumbnail

    @ViewBuilder
    private func miniPolaroid(image: UIImage, entry: PolaroidEntry) -> some View {
        let borderColor: Color = {
            if let hex = entry.packColorHex, let c = Color(hex: hex) { return c }
            return polaPackColors.first(where: { $0.name == entry.packName })?.color ?? .white
        }()
        let devProgress: Double = {
            guard entry.developmentProgress < 1.0 else { return 1.0 }
            let timeBased = min(1.0, Date().timeIntervalSince(entry.timestamp) / 30.0)
            return max(entry.developmentProgress, timeBased)
        }()
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 28, height: 28)
            .clipped()
            .overlay {
                if devProgress < 1.0 {
                    Color.black.opacity(max(0, 0.93 * (1.0 - devProgress)))
                }
            }
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
                .font(.headline)
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
        if let id = pendingEntryID,
           let entry = allEntries.first(where: { $0.id == id }) {
            entry.caption = pendingCaption
        }
        pendingCaption = ""
        pendingEntryID = nil
        withAnimation { showCaptionInput = false }
        captureFlowFinished()
    }

    // MARK: - Post-capture moments

    /// Runs once a capture has fully settled (print animation or caption done). At most one
    /// follow-up is shown per capture, in priority order: location opt-in, milestone paywall, review.
    private func captureFlowFinished() {
        if !hasAnsweredLocationPrompt && cameraManager.locationStatus == .notDetermined {
            withAnimation { showLocationPrompt = true }
            return
        }
        if !premium.isPremium && !hasSeenMilestonePaywall && totalPhotosCount >= 3 {
            hasSeenMilestonePaywall = true
            Task {
                try? await Task.sleep(for: .seconds(0.4))
                presentPaywall(.milestone)
            }
            return
        }
        ReviewPrompter.requestIfAppropriate()
    }

    private func applyDefaultFilterIfNeeded() {
        guard !didApplyDefaultFilter,
              let filter = filmFilter(named: defaultFilter),
              !filter.isLocked(for: premium) else { return }
        didApplyDefaultFilter = true
        selectedFilterName = filter.name
    }

    // MARK: - Locked filter preview

    private func lockedPreviewBanner(for filter: FilmFilter) -> some View {
        Button {
            presentPaywall(.filter(filter.name))
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(filter.color)
                    .frame(width: 8, height: 8)
                Text(String(format: NSLocalizedString("Previewing %@", comment: ""), filter.name))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Unlock")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(red: 1.0, green: 0.8, blue: 0.3), in: Capsule())
            }
            .padding(.leading, 14)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .background(.black.opacity(0.55), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Location opt-in

    private var locationPromptCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 0.2, green: 0.85, blue: 0.55))
                    .frame(width: 36, height: 36)
                    .background(Color(red: 0.2, green: 0.85, blue: 0.55).opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Remember where you shot it?")
                        .font(.headline)
                    Text("Double-tap a polaroid to flip it and see a map of where it was taken.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Not Now") { answerLocationPrompt(enable: false) }
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Enable Location") { answerLocationPrompt(enable: true) }
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
            }
            .font(.callout)
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 4)
    }

    private func answerLocationPrompt(enable: Bool) {
        hasAnsweredLocationPrompt = true
        withAnimation { showLocationPrompt = false }
        Analytics.track(.locationPromptAnswered, ["enabled": enable ? "yes" : "no"])
        if enable { cameraManager.requestLocationAccess() }
    }

    // MARK: - Video helpers

    private func videoThumbnail(from url: URL) async -> UIImage? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        return await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: .zero) { cgImage, _, _ in
                if let cgImage {
                    continuation.resume(returning: UIImage(cgImage: cgImage))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
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
        if let filter = activeFilter, filter.isLocked(for: premium),
           !cameraManager.isRecording, !cameraManager.isTimelapsing {
            Analytics.track(.lockedFilterCaptureBlocked, ["filter": filter.name])
            presentPaywall(.filter(filter.name))
            return
        }
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

private struct ProcessingTimeLapseOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
                Text("Processing time lapse…")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        }
    }
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
                        Text(verbatim: String(format: NSLocalizedString("Between photos: %d s", comment: ""), Int(interval)))
                            .font(.subheadline)
                        Slider(value: $interval, in: 1...60, step: 1)
                    }
                    .padding(.vertical, 4)
                }
                Section("Duration") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: String(format: NSLocalizedString("Total duration: %d s", comment: ""), Int(duration)))
                            .font(.subheadline)
                        Slider(value: $duration, in: 10...3600, step: 10)
                    }
                    .padding(.vertical, 4)
                }
                Section("Output") {
                    Toggle(isOn: $saveAsVideo) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save as video polaroid")
                            Text(verbatim: saveAsVideo
                                 ? NSLocalizedString("All frames combined into one video", comment: "")
                                 : String(format: NSLocalizedString("%d separate photo polaroids", comment: ""), totalPhotos))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section {
                    Text(verbatim: String(format: NSLocalizedString("Total frames: %d", comment: ""), totalPhotos))
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

private struct PolaGlassEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.glassEffect(.regular, in: .circle)
        } else {
            content.background(.ultraThinMaterial, in: Circle())
        }
    }
}

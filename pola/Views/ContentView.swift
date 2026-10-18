import AVFoundation
import StoreKit
import SwiftData
import SwiftUI

enum CameraMode: String, CaseIterable {
    case video = "VIDEO"
    case photo = "PHOTO"
    case timeLapse = "TIME LAPSE"
    case doubleExposure = "DOUBLE EXPOSURE"
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var controlPanes: ControlPanes? = nil
    @State private var filmStockPreviews: [String: UIImage] = [:]
    @Query(sort: \PolaroidEntry.timestamp, order: .reverse) private var allEntries: [PolaroidEntry]
    @State private var pendingEntryID: UUID? = nil
    @State private var pendingCaption: String = ""
    @State private var showCaptionInput = false
    @State private var showLibrary = false
    @State private var libraryDetailOpen = false
    @State private var librarySelectMode = false
    @State private var showSettings = false
    @State private var selectedFilterName: String? = nil
    @State private var selectedLens: Lens? = nil
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
    /// See `DoubleExposure.balanceRange`; 0 is the default look.
    @State private var doubleExposureBalance: Double = 0
    @Namespace private var sheetZoom
    @Namespace private var zoomNamespace
    @Environment(PremiumManager.self) private var premium
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("totalPhotosCount") private var totalPhotosCount: Int = 0
    @AppStorage("defaultFilter") private var defaultFilter: String = "None"
    @AppStorage("hasAnsweredLocationPrompt") private var hasAnsweredLocationPrompt = false
    @AppStorage("hasSeenMilestonePaywall") private var hasSeenMilestonePaywall = false
    @AppStorage(FilmDrops.seenKey) private var seenDropID = 0
    @AppStorage("selectedFrameFormat") private var selectedFrameFormatRaw = FrameFormat.classic.rawValue
    // Drives the paywall sheet via `.sheet(item:)` so the sheet always sees the context it was opened with.
    @State private var paywallContext: PaywallContext? = nil
    // Paywall requested from inside the Filters sheet; shown once that sheet has finished dismissing.
    @State private var pendingPaywallContext: PaywallContext? = nil
    @State private var showLocationPrompt = false
    // Set by a widget tap; the library opens this polaroid once it's on screen.
    @State private var libraryDeepLinkID: UUID? = nil
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

    // Falls back to Classic if a subscription lapses while a premium format is selected.
    private var activeFrameFormat: FrameFormat {
        let format = FrameFormat(rawValue: selectedFrameFormatRaw) ?? .classic
        return format.isFree || premium.isPremium ? format : .classic
    }

    private var isPreviewingLockedFilter: Bool {
        lockedPreview != nil
    }

    /// The locked film stock or lens currently shown in the viewfinder, if any.
    private var lockedPreview: (name: String, color: Color)? {
        if let filter = activeFilter, filter.isLocked(for: premium) {
            return (filter.name, filter.color)
        }
        if let lens = selectedLens, lens.isLocked(for: premium) {
            return (lens.name, lens.color)
        }
        return nil
    }

    private var lockedPreviewPaywallContext: PaywallContext? {
        if let filter = activeFilter, filter.isLocked(for: premium) {
            return .filter(filter.name)
        }
        if let lens = selectedLens, lens.isLocked(for: premium) {
            return .feature(.filmStocks)
        }
        return nil
    }

    private func develop(_ image: UIImage) -> UIImage {
        FilmPipeline.apply(to: image, film: activeFilter?.effect, lens: selectedLens)
    }

    private var captureAnalytics: [String: String] {
        ["filter": selectedFilterName ?? "none", "lens": selectedLens?.name ?? "none"]
    }

    private func presentPaywall(_ context: PaywallContext) {
        paywallContext = context
    }

    private var isDoubleExposureLocked: Bool {
        cameraMode == .doubleExposure && !premium.isPremium
    }

    /// Camera position and zoom stay fixed between the two halves of a double exposure.
    private var isHoldingFirstExposure: Bool {
        cameraManager.doubleExposureFirstShot != nil
    }

    @ViewBuilder
    private var modeToolbarButton: some View {
        if cameraMode == .video {
            let icon = cameraManager.isAudioEnabled ? "mic.fill" : "mic.slash.fill"
            let tint: Color = cameraManager.isAudioEnabled ? .primary : .red
            Button { cameraManager.toggleAudio() } label: {
                Image(systemName: icon).foregroundStyle(tint)
            }
            .accessibilityLabel(Text("Record audio"))
            .accessibilityValue(Text(LocalizedStringKey(cameraManager.isAudioEnabled ? "On" : "Off")))
        } else if cameraMode == .timeLapse {
            Button { showTimeLapseSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel(Text("Time Lapse"))
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
            .accessibilityLabel(Text("Self-timer"))
            .accessibilityValue(shootingTimerDelay > 0
                                ? Text(verbatim: String(format: NSLocalizedString("%d seconds", comment: ""), shootingTimerDelay))
                                : Text("Off"))
        }
    }

    /// Wide windows (iPhone Duo unfolded or half-folded) put the viewfinder on the leading edge
    /// and the controls in a pane beside it instead of below it.
    private var sidePanes: ControlPanes? {
        horizontalSizeClass == .regular ? controlPanes : nil
    }

    private var usesBottomControls: Bool {
        sidePanes == nil
    }

    private static func panes(in proxy: GeometryProxy) -> ControlPanes? {
        let size = proxy.size
        if let fold = proxy.activeVerticalFold {
            return ControlPanes(axis: .horizontal, viewfinder: fold.minX, controls: size.width - fold.maxX,
                                edgeInset: proxy.trailingOcclusionInset)
        }
        if let fold = proxy.activeHorizontalFold {
            return ControlPanes(axis: .vertical, viewfinder: fold.minY, controls: size.height - fold.maxY, edgeInset: 0)
        }
        if size.width > size.height {
            // Full-height 3:4 viewfinder, as long as the controls keep a usable width.
            let rail = proxy.trailingOcclusionInset
            let margin = ControlPanes.viewfinderMargin
            let viewfinder = min((size.height - 2 * margin) * 3 / 4 + 2 * margin,
                                 size.width - rail - ControlPanes.minimumControlWidth)
            return ControlPanes(axis: .horizontal, viewfinder: viewfinder, controls: size.width - viewfinder,
                                edgeInset: rail)
        }
        // Portrait: viewfinder over controls, split as the fold would so folding doesn't reflow.
        let half = (size.height - ControlPanes.nominalFoldGap) / 2
        return ControlPanes(axis: .vertical, viewfinder: half, controls: half, edgeInset: 0)
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
                                if cameraMode == .doubleExposure, let ghost = cameraManager.doubleExposureFirstShot {
                                    DoubleExposureGhost(image: ghost, balance: doubleExposureBalance)
                                        .transition(.opacity)
                                }
                            }
                            .animation(.easeInOut(duration: 0.3), value: isHoldingFirstExposure)
                            .overlay {
                                if let tint = activeFilter?.previewTintColor {
                                    // Stronger tint so the filter is visible in the viewfinder
                                    tint.opacity(0.20).blendMode(.multiply)
                                }
                            }
                            .overlay {
                                // Vignette hint in preview when a filter is active
                                if activeFilter?.effect != nil && selectedLens == nil {
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
                                if let lens = selectedLens {
                                    LensViewfinderHint(lens: lens)
                                        .transition(.opacity)
                                }
                            }
                            .animation(.easeInOut(duration: 0.25), value: selectedLens)
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
                            .overlay {
                                if activeFrameFormat != .classic {
                                    FrameFormatGuide(imageAspect: activeFrameFormat.imageAspect)
                                        .transition(.opacity)
                                }
                            }
                            .animation(.easeInOut(duration: 0.25), value: activeFrameFormat)
                            .overlay(alignment: .top) {
                                if let locked = lockedPreview {
                                    lockedPreviewBanner(name: locked.name, color: locked.color)
                                        .padding(.top, 12)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                } else if cameraMode == .doubleExposure {
                                    doubleExposureBanner
                                        .padding(.top, 12)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                }
                            }
                            .animation(.spring(duration: 0.4, bounce: 0.2), value: isPreviewingLockedFilter)
                            .animation(.spring(duration: 0.4, bounce: 0.2), value: cameraMode == .doubleExposure)
                            // Rounded and inset in the wide layout so it clears the display's corners.
                            .clipShape(RoundedRectangle(cornerRadius: usesBottomControls ? 0 : 24))
                        if usesBottomControls {
                            Spacer()
                        }
                    }
                    .viewfinderPane(sidePanes)
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
                    if usesBottomControls && showLocationPrompt && printingEntry == nil && !showCaptionInput {
                        locationPromptCard
                            .frame(maxWidth: 520)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if usesBottomControls && showCaptionInput && printingEntry == nil {
                        captionInputCard
                            .frame(maxWidth: 520)
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

                    if usesBottomControls && showsBalanceControl {
                        doubleExposureBalanceControl
                            .padding(.horizontal, 20)
                            .foldAvoiding()
                            .padding(.bottom, 8)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if usesBottomControls && cameraManager.availableZoomOptions.count > 1 {
                        zoomControlRow
                            .foldAvoiding()
                            .padding(.bottom, 8)
                    }
                }
                .animation(.spring(duration: 0.45, bounce: 0.2), value: activeStrip)
                .animation(.spring(duration: 0.4, bounce: 0.1), value: showCaptionInput)
                .animation(.spring(duration: 0.4, bounce: 0.1), value: showLocationPrompt)
                .animation(.spring(duration: 0.4, bounce: 0.1), value: showsBalanceControl)
                .viewfinderPane(sidePanes)

                if let panes = sidePanes {
                    let sideBySide = panes.axis == .horizontal
                    controlPane(axis: panes.axis)
                        .padding(.trailing, panes.edgeInset)
                        .frame(width: sideBySide ? panes.controls : nil, height: sideBySide ? nil : panes.controls)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: sideBySide ? .trailing : .bottom)
                }
            }
            // The side layout keeps its shape while typing a caption; the compact one still lifts with the keyboard.
            .ignoresSafeArea(.keyboard, edges: usesBottomControls ? [] : .all)
            .onGeometryChange(for: ControlPanes?.self) { proxy in
                Self.panes(in: proxy)
            } action: { panes in
                controlPanes = panes
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if usesBottomControls {
                    bottomRow
                        .ignoresSafeArea()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel(Text("Settings"))
                    .matchedTransitionSource(id: "settings", in: sheetZoom)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { cameraManager.toggleTorch() } label: {
                        Image(systemName: cameraManager.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .foregroundStyle(cameraManager.isTorchOn ? .yellow : .primary)
                    }
                    .accessibilityLabel(Text("Flashlight"))
                    .accessibilityValue(Text(LocalizedStringKey(cameraManager.isTorchOn ? "On" : "Off")))
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
                    .accessibilityLabel(Text("Flip Camera"))
                    .disabled(isHoldingFirstExposure)
                }
            }
        }
        .fullScreenCover(isPresented: $showLibrary) {
            LibraryView(isDetailOpen: $libraryDetailOpen, isSelectMode: $librarySelectMode, openEntryID: $libraryDeepLinkID)
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
            FiltersView(selectedFilterName: $selectedFilterName, selectedLens: $selectedLens, selectedPackName: $selectedPackName, selectedFrameFormatRaw: $selectedFrameFormatRaw, onPaywallRequested: { context in
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
            if usesBottomControls, isPrinting {
                printAnimation()
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
            MemoryWidgetExporter.export(entries: allEntries, isPremium: isPremium)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Catch renewals, expirations and refunds that happened while the app was in the background.
                Task { await premium.refreshPurchaseStatus() }
            case .background:
                MemoryWidgetExporter.export(entries: allEntries, isPremium: premium.isPremium)
            default:
                break
            }
        }
        .onOpenURL { handleDeepLink($0) }
        .onChange(of: cameraMode) { _, mode in
            if mode == .video {
                Task { await cameraManager.prepareMicrophone() }
            }
            if mode != .doubleExposure {
                cameraManager.discardDoubleExposure()
                doubleExposureBalance = 0
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
            let processed = develop(image)
            let entry = PolaroidEntry(
                image: processed,
                filterName: selectedFilterName,
                lensName: selectedLens?.name,
                packName: selectedPackName,
                frameFormat: activeFrameFormat,
                coordinate: cameraManager.lastCoordinate
            )
            modelContext.insert(entry)
            pendingEntryID = entry.id
            if isInTimelapse {
                timelapsePendingEntries.append(entry)
            } else {
                totalPhotosCount += 1
                Analytics.track(cameraMode == .doubleExposure ? .doubleExposureCaptured : .photoCaptured, captureAnalytics)
                if cameraMode == .doubleExposure {
                    // Each double exposure starts from the default balance; Retake keeps it.
                    doubleExposureBalance = 0
                }
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
                let processed = develop(thumbnail)
                let entry = PolaroidEntry(
                    image: processed,
                    filterName: selectedFilterName,
                    lensName: selectedLens?.name,
                    packName: selectedPackName,
                    frameFormat: activeFrameFormat,
                    coordinate: cameraManager.lastCoordinate
                )
                entry.videoFilename = store.saveVideo(from: url, id: entry.id)
                modelContext.insert(entry)
                pendingEntryID = entry.id
                totalPhotosCount += 1
                Analytics.track(.videoCaptured, captureAnalytics)
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
            let processed = frames.map { develop($0) }
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
                        lensName: selectedLens?.name,
                        packName: selectedPackName,
                        frameFormat: activeFrameFormat,
                        coordinate: coord
                    )
                    entry.videoFilename = store.saveVideo(from: videoURL, id: entry.id)
                    modelContext.insert(entry)
                    pendingEntryID = entry.id
                    Analytics.track(.timelapseCaptured, captureAnalytics)
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
                    Analytics.track(.timelapseCaptured, captureAnalytics)
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
                    filterCard(filter: filter, isSelected: isSelected, locked: locked,
                               previewImage: filmStockPreviews[filter.name]) {
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

    // MARK: - Frame format row

    /// Classic / Square / Wide / Mini, as on the Filters sheet; shown in the wide layout's control pane.
    private var frameFormatRow: some View {
        HStack(spacing: 8) {
            ForEach(FrameFormat.allCases) { format in
                frameFormatChip(format)
            }
        }
        .sensoryFeedback(.selection, trigger: selectedFrameFormatRaw)
    }

    private func frameFormatChip(_ format: FrameFormat) -> some View {
        let isSelected = activeFrameFormat == format
        let locked = !format.isFree && !premium.isPremium
        return Button {
            if locked {
                presentPaywall(.feature(.frameFormats))
            } else {
                withAnimation(.snappy) { selectedFrameFormatRaw = format.rawValue }
            }
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    // Miniature polaroid in the format's proportions
                    let height: CGFloat = 34
                    let width = min(44, height * format.frameAspect)
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.black.opacity(0.35))
                            .padding([.horizontal, .top], 2)
                        Color.clear.frame(height: 6)
                    }
                    .frame(width: width, height: width / format.frameAspect)
                    .background(.white)

                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(.black.opacity(0.55), in: Circle())
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.yellow : .clear, lineWidth: 1.5)
                )

                Text(LocalizedStringKey(format.displayName))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(locked ? .white.opacity(0.45) : .white)
            }
        }
        .buttonStyle(.plain)
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
    private func filterCard(filter: FilmFilter, isSelected: Bool, locked: Bool = false,
                            previewImage: UIImage? = nil, onTap: @escaping () -> Void) -> some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? filter.color.opacity(0.3) : Color.white.opacity(0.12))

                if let previewImage {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFill()
                } else if let imageName = filter.imageName {
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
            .foldAvoiding()
    }

    private var shutterAccessibilityLabel: LocalizedStringKey {
        switch cameraMode {
        case .photo: "Take Photo"
        case .video: cameraManager.isRecording ? "Stop Recording" : "Start Recording"
        case .timeLapse: cameraManager.isTimelapsing ? "Stop Time Lapse" : "Start Time Lapse"
        case .doubleExposure: isHoldingFirstExposure ? "Take Second Exposure" : "Take First Exposure"
        }
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
                } else if cameraMode == .doubleExposure {
                    Group {
                        if isDoubleExposureLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 18, weight: .bold))
                        } else {
                            VStack(spacing: 1) {
                                Image(systemName: "square.on.square")
                                    .font(.system(size: 13, weight: .bold))
                                Text(verbatim: isHoldingFirstExposure ? "2/2" : "1/2")
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                    .foregroundStyle(.black)
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
            .animation(.snappy, value: isHoldingFirstExposure)
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
        .accessibilityLabel(Text(shutterAccessibilityLabel))
    }

    private var filmButton: some View {
        let isActive = selectedFilterName != nil || selectedLens != nil
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Filters"))
        .accessibilityValue(Text(verbatim: selectedFilterName ?? NSLocalizedString("Original", comment: "")))
        .accessibilityAddTraits(.isButton)
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
        .disabled(cameraManager.isRecording || cameraManager.isTimelapsing || isHoldingFirstExposure)
        .opacity((cameraManager.isRecording || cameraManager.isTimelapsing || isHoldingFirstExposure) ? 0.4 : 1.0)
    }

    // MARK: - Bottom row

    private var libraryButton: some View {
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
        .accessibilityLabel(Text("Library"))
        .matchedTransitionSource(id: "library", in: sheetZoom)
    }

    /// Control pane of the wide layout. The modes and shutter row stay pinned to the bottom;
    /// above them sit the note cards, frame and film options and zoom, or the print animation.
    private func controlPane(axis: ControlPanes.Axis) -> some View {
        // Stacked under the viewfinder the pane is short, so the print takes all of it
        // and a note replaces the option rows while it's up.
        let stacked = axis == .vertical
        let showsNote = showCaptionInput || showLocationPrompt
        return VStack(spacing: 14) {
            ZStack {
                if isPrinting {
                    GeometryReader { geo in
                        printAnimation(fitting: geo.size.height)
                    }
                    .clipped()
                } else {
                    VStack(spacing: 14) {
                        // Notes sit at the top so the caption field stays above the keyboard.
                        if showLocationPrompt && !showCaptionInput {
                            locationPromptCard
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if showCaptionInput {
                            captionInputCard
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        Spacer(minLength: 0)

                        if stacked {
                            if !showsNote {
                                // The pane is wide here, so shape and color share a row.
                                HStack(spacing: 8) {
                                    frameFormatRow
                                        .frame(width: 280)
                                    colorStrip
                                        .modifier(EdgeFade())
                                }
                                filterStrip
                                    .modifier(EdgeFade())
                            }
                        } else {
                            frameFormatRow
                            colorStrip
                                .modifier(EdgeFade())
                            filterStrip
                                .modifier(EdgeFade())
                        }

                        // Zoom is locked while the first exposure is held, so the balance takes its place.
                        if showsBalanceControl {
                            doubleExposureBalanceControl
                                .foldAvoiding()
                                .transition(.opacity)
                        } else if cameraManager.availableZoomOptions.count > 1 {
                            zoomControlRow
                                .foldAvoiding()
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)

            if !(stacked && isPrinting) {
                modePicker
                    .frame(maxWidth: .infinity)
                    .foldAvoiding(coreWidth: 90, strategy: .inset)

                HStack(spacing: 0) {
                    libraryButton
                        .frame(maxWidth: .infinity)
                    shutterRow
                    filmButton
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 440)
                // The full-screen print blocks the shutter on phones; here it stays visible, so pause it.
                .disabled(isPrinting)
                .opacity(isPrinting ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity)
        .background(.black)
        .animation(.spring(duration: 0.4, bounce: 0.1), value: showCaptionInput)
        .animation(.spring(duration: 0.4, bounce: 0.1), value: showLocationPrompt)
        .animation(.easeInOut(duration: 0.2), value: isPrinting)
        .task {
            guard filmStockPreviews.isEmpty,
                  let reference = UIImage(named: "filter_reference") else { return }
            let thumbnail = reference.preparingThumbnail(of: CGSize(width: 120, height: 120)) ?? reference
            filmStockPreviews = renderFilmStockPreviews(from: thumbnail)
        }
    }

    private var isPrinting: Bool {
        printingEntry != nil || !printingEntries.isEmpty
    }

    /// The print-and-develop animation for the latest capture: full screen on phones, inside the
    /// control pane in the wide layout. `height` shrinks the polaroid so the whole sequence fits.
    @ViewBuilder
    private func printAnimation(fitting height: CGFloat? = nil) -> some View {
        if let entry = printingEntry {
            PolaroidPrintAnimationView(
                entry: entry,
                captionEnabled: captionPromptEnabled,
                polaroidWidth: height.map(Self.polaroidWidth(fitting:)) ?? 220,
                onComplete: {
                    printingEntry = nil
                    captureFlowFinished()
                }
            )
        } else if !printingEntries.isEmpty {
            MultiPolaroidPrintAnimationView(
                entries: printingEntries,
                onComplete: {
                    printingEntries = []
                    captureFlowFinished()
                }
            )
        }
    }

    /// Widest polaroid whose print sequence (polaroid, shake hint and caption bar, about 216pt
    /// besides the photo) fits `height`, assuming the tallest 3:4 frame.
    private static func polaroidWidth(fitting height: CGFloat) -> CGFloat {
        min(220, max(120, (height - 216) * 0.75 + 16))
    }

    private var bottomRow: some View {
        VStack(spacing: 0) {
            shutterRow
                .padding(.top, 14)
                .padding(.bottom, 14)

            HStack(spacing: 0) {
                libraryButton
                    .frame(width: 72, alignment: .leading)

                modePicker
                    .frame(maxWidth: .infinity)
                    // The selected mode sits in a 90pt capsule at the picker's centre.
                    .foldAvoiding(coreWidth: 90, strategy: .inset)

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

    private func handleDeepLink(_ url: URL) {
        guard url.scheme == PolyDeepLink.scheme else { return }
        switch url.host() {
        case "premium":
            if !premium.isPremium { presentPaywall(.feature(.widget)) }
        case "memory":
            libraryDeepLinkID = UUID(uuidString: url.lastPathComponent)
            showLibrary = true
        default:
            break
        }
    }

    private func applyDefaultFilterIfNeeded() {
        guard !didApplyDefaultFilter,
              let filter = filmFilter(named: defaultFilter),
              !filter.isLocked(for: premium) else { return }
        didApplyDefaultFilter = true
        selectedFilterName = filter.name
    }

    // MARK: - Locked filter preview

    private func lockedPreviewBanner(name: String, color: Color) -> some View {
        Button {
            if let context = lockedPreviewPaywallContext {
                presentPaywall(context)
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(String(format: NSLocalizedString("Previewing %@", comment: ""), name))
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

    // MARK: - Double exposure

    /// Shows which half of the double exposure is next, with a way to throw the first shot away,
    /// or the unlock pitch when the mode is locked.
    @ViewBuilder
    private var doubleExposureBanner: some View {
        if isDoubleExposureLocked {
            Button { presentPaywall(.feature(.doubleExposure)) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.on.square")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PremiumFeature.doubleExposure.color)
                    Text("Double Exposure")
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
        } else {
            HStack(spacing: 8) {
                Text(verbatim: isHoldingFirstExposure ? "2/2" : "1/2")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(PremiumFeature.doubleExposure.color, in: Capsule())
                    .contentTransition(.numericText())
                Text(isHoldingFirstExposure ? "Line up the second shot" : "Take the first shot")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if isHoldingFirstExposure {
                    Button {
                        withAnimation(.snappy) { cameraManager.discardDoubleExposure() }
                    } label: {
                        Label("Retake", systemImage: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("Discards the first shot"))
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, isHoldingFirstExposure ? 5 : 14)
            .padding(.vertical, 5)
            .background(.black.opacity(0.55), in: Capsule())
            .animation(.snappy, value: isHoldingFirstExposure)
            .sensoryFeedback(.impact(weight: .light), trigger: isHoldingFirstExposure)
        }
    }

    private var showsBalanceControl: Bool {
        cameraMode == .doubleExposure && isHoldingFirstExposure
    }

    private var balanceDescription: LocalizedStringKey {
        switch doubleExposureBalance {
        case ..<(-0.05): "More of the first shot"
        case 0.05...: "More of the second shot"
        default: "Default blend"
        }
    }

    /// Slides the double exposure's weight between the two shots. The middle is the default look,
    /// and it snaps back there so it's easy to find again.
    private var doubleExposureBalanceControl: some View {
        HStack(spacing: 10) {
            Text("1st")
            Slider(value: $doubleExposureBalance, in: DoubleExposure.balanceRange, onEditingChanged: { editing in
                if !editing && abs(doubleExposureBalance) < 0.08 {
                    doubleExposureBalance = 0
                }
            })
            .tint(PremiumFeature.doubleExposure.color)
            .accessibilityLabel(Text("Blend balance"))
            .accessibilityValue(Text(balanceDescription))
            Text("2nd")
        }
        .font(.system(size: 12, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(maxWidth: 320)
        .background(.black.opacity(0.55), in: Capsule())
        .sensoryFeedback(.selection, trigger: doubleExposureBalance == 0)
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
        if let locked = lockedPreview, let context = lockedPreviewPaywallContext,
           !cameraManager.isRecording, !cameraManager.isTimelapsing {
            Analytics.track(.lockedFilterCaptureBlocked, ["filter": locked.name])
            presentPaywall(context)
            return
        }
        if isDoubleExposureLocked {
            presentPaywall(.feature(.doubleExposure))
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
        case .doubleExposure:
            cameraManager.captureDoubleExposureShot(balance: doubleExposureBalance)
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

/// The first half of a double exposure, laid over the live preview so the second shot can be lined up.
private struct DoubleExposureGhost: View {
    let image: UIImage
    /// Tracks the blend balance: a stronger ghost when the first shot will show through more.
    let balance: Double

    var body: some View {
        // Matches the 3:4 preview inside the full-width viewfinder frame.
        Color.clear
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .overlay {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .opacity(balance < 0 ? 0.45 - 0.2 * balance : 0.45 - 0.3 * balance)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Dims the parts of the 3:4 viewfinder that the selected film format will crop away.
private struct FrameFormatGuide: View {
    let imageAspect: CGFloat

    var body: some View {
        GeometryReader { geo in
            let full = geo.size
            let window: CGSize = full.width / full.height < imageAspect
                ? CGSize(width: full.width, height: full.width / imageAspect)
                : CGSize(width: full.height * imageAspect, height: full.height)
            let rect = CGRect(x: (full.width - window.width) / 2, y: (full.height - window.height) / 2,
                              width: window.width, height: window.height)
            Path { p in
                p.addRect(CGRect(origin: .zero, size: full))
                p.addRect(rect)
            }
            .fill(.black.opacity(0.55), style: FillStyle(eoFill: true))
            Rectangle()
                .strokeBorder(.white.opacity(0.6), lineWidth: 1)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
        .allowsHitTesting(false)
    }
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

/// The viewfinder and control panes of the wide camera layout: side by side in landscape
/// (viewfinder leading), stacked in portrait (viewfinder on top).
nonisolated private struct ControlPanes: Equatable, Sendable {
    enum Axis: Equatable, Sendable {
        case horizontal
        case vertical
    }

    static let minimumControlWidth: CGFloat = 340
    /// Inset of the viewfinder from the display edges and the fold.
    static let viewfinderMargin: CGFloat = 16
    /// Roughly the iPhone Duo's fold region, used to split an unfolded portrait screen like a folded one.
    static let nominalFoldGap: CGFloat = 24

    let axis: Axis
    /// Width (side by side) or height (stacked) of each pane.
    let viewfinder: CGFloat
    let controls: CGFloat
    /// Part of the control pane covered by system UI along the trailing edge.
    let edgeInset: CGFloat
}

private extension View {
    /// Pins the view to the viewfinder pane of the wide layout. Without panes it lays out as before;
    /// the modifiers stay in place either way so the camera preview isn't rebuilt on fold changes.
    func viewfinderPane(_ panes: ControlPanes?) -> some View {
        padding(panes == nil ? 0 : ControlPanes.viewfinderMargin)
            .frame(width: panes?.axis == .horizontal ? panes?.viewfinder : nil,
                   height: panes?.axis == .vertical ? panes?.viewfinder : nil)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: panes == nil ? .center : .topLeading)
    }
}

/// Fades a horizontal scroll view's edges, like the mode picker, but only on a side with more
/// content hidden past it, so items dissolve instead of being cut off at the edge.
private struct EdgeFade: ViewModifier {
    nonisolated struct Overflow: Equatable, Sendable {
        var leading = false
        var trailing = false
    }

    /// Matches the strips' 20pt content padding, so the first and last items rest clear of it.
    var width: CGFloat = 20
    @State private var overflow = Overflow()

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: Overflow.self) { geometry in
                Overflow(leading: geometry.visibleRect.minX > 1,
                         trailing: geometry.visibleRect.maxX < geometry.contentSize.width - 1)
            } action: { _, newValue in
                withAnimation(.easeOut(duration: 0.15)) { overflow = newValue }
            }
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [overflow.leading ? .clear : .black, .black],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: width)
                    Color.black
                    LinearGradient(colors: [.black, overflow.trailing ? .clear : .black],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: width)
                }
            }
    }
}

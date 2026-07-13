import CoreMotion
import Photos
import SwiftData
import SwiftUI
import UIKit

// Shared observable video state so toolbar buttons update the SwiftUI page view.
@Observable
private final class DetailVideoState {
    var isPlaying = true
    var isLooping: Bool

    init() {
        isLooping = UserDefaults.standard.object(forKey: "videoLooping") as? Bool ?? true
    }

    func persistLooping() {
        UserDefaults.standard.set(isLooping, forKey: "videoLooping")
    }
}

private struct DetailPageView: View {
    @Bindable var entry: PolaroidEntry
    let store: PhotoStore
    let videoState: DetailVideoState

    var body: some View {
        PolaroidPhotoCell(
            image: entry.image,
            videoURL: entry.videoURL(in: store.videoDirectory),
            isTimelapse: entry.isTimelapse,
            playVideo: true,
            isVideoPlaying: videoState.isPlaying,
            isVideoLooping: videoState.isLooping,
            developmentProgress: entry.developmentProgress,
            animatedExternally: entry.developmentProgress < 1.0,
            caption: entry.caption,
            backText: entry.backText,
            showMap: entry.showMap,
            coordinate: entry.coordinate,
            timestamp: entry.timestamp,
            filterName: entry.filterName,
            packName: entry.packName,
            packColorHex: entry.packColorHex,
            fontScale: 1.7,
            onDeveloped: { entry.developmentProgress = 1.0 }
        )
        .aspectRatio(270.0 / 360.0, contentMode: .fit)
        .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 6)
        .padding(.horizontal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class PolaroidDetailViewController: UIViewController {

    var entries: [PolaroidEntry] = []
    var startIndex: Int = 0
    var store: PhotoStore!
    var modelContext: ModelContext!
    var onCurrentIndexChange: ((UUID) -> Void)?

    var currentEntryID: UUID? {
        guard currentIndex < entries.count else { return nil }
        return entries[currentIndex].id
    }

    private var currentIndex: Int = 0 {
        didSet {
            updateNavigationTitle()
            updateToolbar()
            manageDevelopment()
            if let id = currentEntryID { onCurrentIndexChange?(id) }
        }
    }

    private let videoState = DetailVideoState()
    private var pageVC: UIPageViewController!
    private var isSaving = false
    private var saveDidSucceed = false

    private var titleStackView: UIStackView?
    private var weekdayLabel: UILabel?
    private var timeLabel: UILabel?
    private var titleNeedsSettleAnimation = false
    private var contentOffsetObservation: NSKeyValueObservation?
    private let shakeManager = CMMotionManager()
    private var developmentLink: CADisplayLink?
    private var shakeBonus: TimeInterval = 0

    private var currentEntry: PolaroidEntry? {
        guard currentIndex < entries.count else { return nil }
        return entries[currentIndex]
    }

    // MARK: - Development & shake

    private func manageDevelopment() {
        developmentLink?.invalidate()
        developmentLink = nil
        shakeManager.stopAccelerometerUpdates()
        shakeBonus = 0

        guard let entry = currentEntry else { return }
        let elapsed = Date().timeIntervalSince(entry.timestamp)

        // Already fully developed — mark it and bail
        if elapsed >= 30 || entry.developmentProgress >= 1.0 {
            entry.developmentProgress = 1.0
            return
        }

        // Seed shakeBonus from stored progress so we never go backwards.
        // Stored progress may be ahead of real time (due to prior shaking).
        let storedProgress = entry.developmentProgress
        shakeBonus = max(0, storedProgress * 30.0 - elapsed)
        entry.developmentProgress = max(storedProgress, min(1.0, elapsed / 30.0))

        developmentLink = CADisplayLink(target: self, selector: #selector(tickDevelopment))
        developmentLink?.add(to: .main, forMode: .common)

        guard shakeManager.isAccelerometerAvailable else { return }
        shakeManager.accelerometerUpdateInterval = 0.1
        shakeManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let data, let self else { return }
            let a = data.acceleration
            if sqrt(a.x*a.x + a.y*a.y + a.z*a.z) > 2.5 {
                self.shakeBonus += 6          // each shake jumps 6 s of development
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
            }
        }
    }

    @objc private func tickDevelopment() {
        guard let entry = currentEntry else {
            developmentLink?.invalidate(); developmentLink = nil; return
        }
        let elapsed = Date().timeIntervalSince(entry.timestamp) + shakeBonus
        let progress = min(1.0, elapsed / 30.0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        entry.developmentProgress = max(entry.developmentProgress, progress)
        CATransaction.commit()
        if progress >= 1.0 {
            entry.developmentProgress = 1.0
            try? modelContext.save()
            developmentLink?.invalidate()
            developmentLink = nil
            shakeManager.stopAccelerometerUpdates()
        }
    }

    deinit {
        contentOffsetObservation?.invalidate()
        developmentLink?.invalidate()
        shakeManager.stopAccelerometerUpdates()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupTitleView()
        currentIndex = startIndex
        setupPageViewController()
        updateNavigationTitle()
        updateToolbar()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
        developmentLink?.invalidate()
        developmentLink = nil
        shakeManager.stopAccelerometerUpdates()
        try? modelContext.save()
    }

    // MARK: - Page view controller

    private func setupPageViewController() {
        pageVC = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        pageVC.dataSource = self
        pageVC.delegate = self

        addChild(pageVC)
        pageVC.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageVC.view)
        NSLayoutConstraint.activate([
            pageVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageVC.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        pageVC.didMove(toParent: self)

        guard !entries.isEmpty else { return }
        pageVC.setViewControllers([makePage(for: currentIndex)], direction: .forward, animated: false)
        observePageScroll()
    }

    private func observePageScroll() {
        guard let sv = pageVC.view.subviews.compactMap({ $0 as? UIScrollView }).first else { return }
        contentOffsetObservation = sv.observe(\.contentOffset, options: .new) { [weak self] scrollView, _ in
            self?.applyTitleParallax(offsetX: scrollView.contentOffset.x, width: scrollView.bounds.width)
        }
    }

    private func applyTitleParallax(offsetX: CGFloat, width: CGFloat) {
        guard width > 0, let stack = titleStackView else { return }
        let fraction = (offsetX - width) / width   // –1 (prev) … 0 (rest) … +1 (next)
        let magnitude = min(1, abs(fraction))
        guard magnitude > 0.001 else { return }    // skip when scroll view snaps back to center
        let scale = 1 - magnitude * 0.08
        stack.transform = CGAffineTransform(scaleX: scale, y: scale)
        stack.alpha = 1 - magnitude * 0.72
    }

    private func makePage(for index: Int) -> UIHostingController<AnyView> {
        let entry = entries[index]
        let vc = UIHostingController(rootView: AnyView(
            DetailPageView(entry: entry, store: store, videoState: videoState)
        ))
        vc.view.tag = index
        vc.view.backgroundColor = .clear
        return vc
    }

    // MARK: - Navigation title

    private func setupTitleView() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 1

        let weekday = UILabel()
        weekday.font = .preferredFont(forTextStyle: .headline)

        let time = UILabel()
        time.font = .preferredFont(forTextStyle: .caption1)
        time.textColor = .secondaryLabel

        stack.addArrangedSubview(weekday)
        stack.addArrangedSubview(time)
        weekdayLabel = weekday
        timeLabel = time
        titleStackView = stack
        navigationItem.titleView = stack
    }

    private func updateNavigationTitle() {
        guard let entry = currentEntry else { return }

        let df = DateFormatter()
        df.dateFormat = "EEEE"
        let weekdayText = df.string(from: entry.timestamp)

        let tf = DateFormatter()
        tf.dateStyle = .none; tf.timeStyle = .short
        let timeText = tf.string(from: entry.timestamp)

        let hadDirection = titleNeedsSettleAnimation
        titleNeedsSettleAnimation = false

        weekdayLabel?.text = weekdayText
        timeLabel?.text = timeText

        if hadDirection {
            UIView.animate(withDuration: 0.4, delay: 0,
                           usingSpringWithDamping: 0.72, initialSpringVelocity: 0.4) {
                self.titleStackView?.transform = .identity
                self.titleStackView?.alpha = 1
            }
        } else {
            titleStackView?.transform = .identity
            titleStackView?.alpha = 1
        }
    }

    // MARK: - Toolbar

    private func updateToolbar() {
        let flex = UIBarButtonItem(systemItem: .flexibleSpace)

        let shareBtn = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain,
                                       target: self, action: #selector(shareCurrent))
        let saveIcon = saveDidSucceed ? "checkmark" : "square.and.arrow.down"
        let saveBtn = UIBarButtonItem(image: UIImage(systemName: saveIcon), style: .plain,
                                      target: self, action: #selector(saveCurrent))
        saveBtn.isEnabled = !isSaving && !saveDidSucceed
        let editBtn = UIBarButtonItem(image: UIImage(systemName: "pencil"), style: .plain,
                                      target: self, action: #selector(editCurrent))
        let deleteBtn = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain,
                                        target: self, action: #selector(deleteCurrentPrompt))
        deleteBtn.tintColor = .systemRed

        toolbarItems = [shareBtn, flex, saveBtn, flex, editBtn, flex, deleteBtn]

        if currentEntry?.videoFilename != nil {
            let loopBtn = UIBarButtonItem(
                image: UIImage(systemName: videoState.isLooping ? "repeat" : "1.circle"),
                menu: makeLoopMenu()
            )
            let playIcon = videoState.isPlaying ? "pause.fill" : "play.fill"
            let playBtn = UIBarButtonItem(image: UIImage(systemName: playIcon), style: .plain,
                                          target: self, action: #selector(togglePlay))
            navigationItem.rightBarButtonItems = [playBtn, loopBtn]
        } else {
            navigationItem.rightBarButtonItems = []
        }
    }

    private func makeLoopMenu() -> UIMenu {
        UIMenu(children: [
            UIAction(title: NSLocalizedString("Loop", comment: ""),
                     image: UIImage(systemName: videoState.isLooping ? "checkmark" : "repeat")) { [weak self] _ in
                self?.videoState.isLooping = true
                self?.videoState.persistLooping()
                self?.updateToolbar()
            },
            UIAction(title: NSLocalizedString("Play Once", comment: ""),
                     image: UIImage(systemName: !videoState.isLooping ? "checkmark" : "1.circle")) { [weak self] _ in
                self?.videoState.isLooping = false
                self?.videoState.persistLooping()
                self?.updateToolbar()
            }
        ])
    }

    // MARK: - Actions

    @objc private func togglePlay() {
        videoState.isPlaying.toggle()
        updateToolbar()
    }

    @objc private func shareCurrent() {
        guard let entry = currentEntry else { return }
        Task {
            let items = await prepareShareItems(for: [entry], videoDirectory: store.videoDirectory)
            await MainActor.run {
                present(UIActivityViewController(activityItems: items, applicationActivities: nil), animated: true)
            }
        }
    }

    @objc private func saveCurrent() {
        guard !isSaving, !saveDidSucceed, let entry = currentEntry else { return }
        Task { await saveToPhotos(entry) }
    }

    @MainActor
    private func saveToPhotos(_ entry: PolaroidEntry) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        isSaving = true; updateToolbar()
        if let filename = entry.videoFilename {
            let src = store.videoDirectory.appendingPathComponent(filename)
            let url = await compositePolaroidVideo(entry, sourceURL: src) ?? src
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        } else {
            let image = renderPolaroidFrame(entry)
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        }
        isSaving = false; saveDidSucceed = true; updateToolbar()
        try? await Task.sleep(for: .seconds(2))
        saveDidSucceed = false; updateToolbar()
    }

    @objc private func editCurrent() {
        guard let entry = currentEntry else { return }
        let vc = UIHostingController(rootView: EditPolaroidSheet(entry: entry))
        vc.sheetPresentationController?.detents = [.medium(), .large()]
        vc.sheetPresentationController?.prefersGrabberVisible = true
        present(vc, animated: true)
    }

    @objc private func deleteCurrentPrompt() {
        let alert = UIAlertController(title: NSLocalizedString("Delete this photo?", comment: ""),
                                      message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive) { [weak self] _ in
            self?.deleteCurrentPhoto()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    private func deleteCurrentPhoto() {
        guard currentIndex < entries.count else { return }
        let entry = entries[currentIndex]
        if let filename = entry.videoFilename { store.deleteVideo(filename: filename) }
        let target = min(max(0, currentIndex >= entries.count - 1 ? currentIndex - 1 : currentIndex), entries.count - 2)
        modelContext.delete(entry)
        entries.remove(at: currentIndex)

        guard !entries.isEmpty else { navigationController?.popViewController(animated: true); return }
        currentIndex = target
        pageVC.setViewControllers([makePage(for: currentIndex)], direction: .forward, animated: false)
    }
}

// MARK: - UIPageViewControllerDataSource
extension PolaroidDetailViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pvc: UIPageViewController,
                             viewControllerBefore vc: UIViewController) -> UIViewController? {
        let idx = vc.view.tag
        guard idx > 0 else { return nil }
        return makePage(for: idx - 1)
    }

    func pageViewController(_ pvc: UIPageViewController,
                             viewControllerAfter vc: UIViewController) -> UIViewController? {
        let idx = vc.view.tag
        guard idx < entries.count - 1 else { return nil }
        return makePage(for: idx + 1)
    }
}

// MARK: - UIPageViewControllerDelegate
extension PolaroidDetailViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pvc: UIPageViewController, didFinishAnimating finished: Bool,
                             previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
        guard completed, let current = pvc.viewControllers?.first else { return }
        titleNeedsSettleAnimation = true
        currentIndex = current.view.tag
        videoState.isPlaying = true
    }
}

import Photos
import SwiftData
import SwiftUI
import UIKit

final class LibraryViewController: UICollectionViewController {

    // MARK: - Dependencies
    var onDetailStateChange: ((Bool) -> Void)?
    var onSelectModeChange: ((Bool) -> Void)?

    var entries: [PolaroidEntry] = [] {
        didSet {
            guard isViewLoaded else { return }
            entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
            applySnapshot(animated: !oldValue.isEmpty)
        }
    }
    var store: PhotoStore!
    var premium: PremiumManager!
    var modelContext: ModelContext!

    // MARK: - State
    private var selectedCategory = "All"
    private var sortNewest = true
    private var dragSelectInitialState: Bool?
    private var dragSelectVisited: Set<UUID> = []
    private weak var dragSelectPanGesture: UIPanGestureRecognizer?
    private var isSelectMode = false {
        didSet {
            if !isSelectMode { selectedIDs.removeAll() }
            onSelectModeChange?(isSelectMode)
            updateNavigationBar()
            updateSelectToolbar()
            reconfigureVisible()
        }
    }
    private var selectedIDs: Set<UUID> = [] {
        didSet {
            updateNavigationTitle()
            updateSelectToolbar()
        }
    }
    private var entriesByID: [UUID: PolaroidEntry] = [:]
    private var isSaving = false
    private var saveDidSucceed = false

    private var columnCount: Int {
        get { UserDefaults.standard.object(forKey: "libraryColumnCount") as? Int ?? 3 }
        set {
            UserDefaults.standard.set(newValue, forKey: "libraryColumnCount")
            updateLayout()
            applySnapshot(animated: false)
            updateNavigationBarButtons()
        }
    }

    private var cellFontScale: CGFloat {
        switch columnCount { case 1: return 1.7; case 2: return 1.3; default: return 1.0 }
    }

    private let categoryNames = ["All", "FL\u{00C4}RN", "SOLVA", "BR\u{00D6}KK", "VYLUR", "GR\u{00C5}LT"]

    private var filteredEntries: [PolaroidEntry] {
        var result = entries
        if selectedCategory != "All" {
            result = result.filter { $0.packName == selectedCategory || $0.filterName == selectedCategory }
        }
        let text = searchController.searchBar.text ?? ""
        if !text.isEmpty {
            result = result.filter {
                $0.caption.localizedCaseInsensitiveContains(text) ||
                $0.backText.localizedCaseInsensitiveContains(text)
            }
        }
        return sortNewest ? result : result.reversed()
    }

    // MARK: - UI
    private var dataSource: UICollectionViewDiffableDataSource<Int, UUID>!
    private let searchController = UISearchController(searchResultsController: nil)
    private var selectToolbar: UIToolbar?

    init() { super.init(collectionViewLayout: UICollectionViewFlowLayout()) }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCollectionView()
        setupDataSource()
        setupSearchController()
        setupGestures()
        entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        updateNavigationBar()
        applySnapshot(animated: false)
    }

    // MARK: - Collection view

    private func setupCollectionView() {
        collectionView.backgroundColor = .systemBackground
        collectionView.allowsMultipleSelection = true
        collectionView.collectionViewLayout = makeLayout()
        collectionView.keyboardDismissMode = .onDrag
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let n = CGFloat(columnCount)
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0 / n),
            heightDimension: .fractionalWidth(1.0 / n / 0.75)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        item.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .fractionalWidth(1.0 / n / 0.75)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        let side: CGFloat = columnCount == 1 ? 60 : 7
        section.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: side, bottom: 7, trailing: side)
        return UICollectionViewCompositionalLayout(section: section)
    }

    private func updateLayout() {
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.collectionView.collectionViewLayout = self.makeLayout()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Data source

    private func setupDataSource() {
        let cellReg = UICollectionView.CellRegistration<UICollectionViewCell, UUID> { [weak self] cell, _, id in
            self?.configure(cell: cell, forID: id)
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { cv, indexPath, id in
            cv.dequeueConfiguredReusableCell(using: cellReg, for: indexPath, item: id)
        }
    }

    private func configure(cell: UICollectionViewCell, forID id: UUID) {
        guard let entry = entriesByID[id] else { return }
        let isSelected = selectedIDs.contains(id)
        let selectMode = isSelectMode
        let fontScale = cellFontScale
        let store = store!

        cell.contentConfiguration = UIHostingConfiguration {
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
                packColorHex: entry.packColorHex,
                fontScale: fontScale,
                onDeveloped: { entry.developmentProgress = 1.0 },
                onSingleTap: { [weak self] in
                    guard let self else { return }
                    if self.isSelectMode {
                        self.toggleSelection(id)
                    } else if let entry = self.entriesByID[id] {
                        self.openDetail(for: entry)
                    }
                }
            )
            .aspectRatio(0.75, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                if selectMode {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .blue)
                        .padding(6)
                }
            }
        }
        .margins(.all, 0)
    }

    private func applySnapshot(animated: Bool = true) {
        updateEmptyState()
        updateNavigationTitle()
        let existingIDs = Set(dataSource.snapshot().itemIdentifiers)
        var snap = NSDiffableDataSourceSnapshot<Int, UUID>()
        snap.appendSections([0])
        let newIDs = filteredEntries.map(\.id)
        snap.appendItems(newIDs)
        // Reconfigure items already in the data source so property changes (e.g. border color) are reflected.
        let toReconfigure = newIDs.filter { existingIDs.contains($0) }
        if !toReconfigure.isEmpty { snap.reconfigureItems(toReconfigure) }
        dataSource.apply(snap, animatingDifferences: animated)
    }

    private func reconfigureVisible() {
        let ids = collectionView.indexPathsForVisibleItems.compactMap { dataSource.itemIdentifier(for: $0) }
        guard !ids.isEmpty else { return }
        var snap = dataSource.snapshot()
        snap.reconfigureItems(ids)
        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: - Empty state

    private func updateEmptyState() {
        let filtered = filteredEntries
        if entries.isEmpty {
            setBackground(title: NSLocalizedString("No Photos Yet", comment: ""),
                          subtitle: NSLocalizedString("Take your first photo to see it here", comment: ""))
        } else if filtered.isEmpty {
            let query = (searchController.searchBar.text ?? "").isEmpty ? selectedCategory : (searchController.searchBar.text ?? "")
            setBackground(title: NSLocalizedString("No Results", comment: ""),
                          subtitle: String(format: NSLocalizedString("No photos matching \"%@\"", comment: ""), query))
        } else {
            collectionView.backgroundView = nil
        }
    }

    private func setBackground(title: String, subtitle: String) {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        let attr = NSMutableAttributedString(string: title + "\n",
                                             attributes: [.font: UIFont.preferredFont(forTextStyle: .headline)])
        attr.append(NSAttributedString(string: subtitle,
                                       attributes: [.font: UIFont.preferredFont(forTextStyle: .subheadline),
                                                    .foregroundColor: UIColor.secondaryLabel]))
        label.attributedText = attr
        collectionView.backgroundView = label
    }

    // MARK: - Navigation bar

    private func updateNavigationBar() {
        navigationItem.largeTitleDisplayMode = .never
        updateNavigationTitle()
        updateNavigationBarButtons()
    }

    private func updateNavigationTitle() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = isSelectMode ? .center : .leading
        stack.spacing = 0

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("Library", comment: "")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(titleLabel)

        if !entries.isEmpty {
            let sub = UILabel()
            sub.font = .preferredFont(forTextStyle: .caption1)
            sub.textColor = .secondaryLabel
            if isSelectMode && !selectedIDs.isEmpty {
                sub.text = "\(selectedIDs.count)/\(entries.count)"
            } else {
                let count = filteredEntries.count
                sub.text = count == 1
                    ? NSLocalizedString("1 item", comment: "")
                    : String(format: NSLocalizedString("%d items", comment: ""), count)
            }
            stack.addArrangedSubview(sub)
        }
        navigationItem.titleView = stack
    }

    private func updateNavigationBarButtons() {
        if isSelectMode {
            navigationItem.rightBarButtonItems = [
                UIBarButtonItem(title: NSLocalizedString("Cancel", comment: ""), style: .plain,
                                target: self, action: #selector(toggleSelectMode))
            ]
        } else {
            var items: [UIBarButtonItem] = []
            if !entries.isEmpty {
                items.append(UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: makeOptionsMenu()))
                items.append(UIBarButtonItem(title: NSLocalizedString("Select", comment: ""), style: .plain,
                                             target: self, action: #selector(toggleSelectMode)))
            }
            navigationItem.rightBarButtonItems = items
        }
    }

    private func makeOptionsMenu() -> UIMenu {
        let filterActions = categoryNames.map { name in
            UIAction(title: name, image: UIImage(systemName: selectedCategory == name ? "checkmark" : "tag")) { [weak self] _ in
                guard let self else { return }
                self.selectedCategory = (self.selectedCategory == name && name != "All") ? "All" : name
                self.applySnapshot()
                self.updateNavigationTitle()
                self.updateNavigationBarButtons()
            }
        }
        let filterIcon = selectedCategory == "All" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
        let filterMenu = UIMenu(title: NSLocalizedString("Filter", comment: ""),
                                image: UIImage(systemName: filterIcon), children: filterActions)

        let sortActions: [UIAction] = [
            UIAction(title: NSLocalizedString("Newest First", comment: ""),
                     image: UIImage(systemName: sortNewest ? "checkmark" : "arrow.up")) { [weak self] _ in
                self?.sortNewest = true; self?.applySnapshot()
            },
            UIAction(title: NSLocalizedString("Oldest First", comment: ""),
                     image: UIImage(systemName: !sortNewest ? "checkmark" : "arrow.down")) { [weak self] _ in
                self?.sortNewest = false; self?.applySnapshot()
            }
        ]
        let sortMenu = UIMenu(title: NSLocalizedString("Sort", comment: ""),
                              image: UIImage(systemName: "arrow.up.arrow.down"), children: sortActions)

        let col = columnCount
        let gridMenu = UIMenu(title: NSLocalizedString("Grid", comment: ""),
                              image: UIImage(systemName: "square.grid.2x2"), children: [
            UIAction(title: NSLocalizedString("1 Column", comment: ""),
                     image: UIImage(systemName: col == 1 ? "checkmark" : "rectangle.grid.1x2")) { [weak self] _ in self?.columnCount = 1 },
            UIAction(title: NSLocalizedString("2 Columns", comment: ""),
                     image: UIImage(systemName: col == 2 ? "checkmark" : "square.grid.2x2")) { [weak self] _ in self?.columnCount = 2 },
            UIAction(title: NSLocalizedString("3 Columns", comment: ""),
                     image: UIImage(systemName: col == 3 ? "checkmark" : "square.grid.3x2")) { [weak self] _ in self?.columnCount = 3 }
        ])

        let fontMenuElement: UIMenuElement
        let weightMenuElement: UIMenuElement
        if premium.isPremium {
            let storedFont = UserDefaults.standard.string(forKey: "polaroidFont") ?? PolaroidFont.handwriting.rawValue
            fontMenuElement = UIMenu(title: NSLocalizedString("Caption Font", comment: ""),
                                     image: UIImage(systemName: "textformat"),
                                     children: PolaroidFont.allCases.map { font in
                UIAction(title: font.displayName,
                         image: UIImage(systemName: storedFont == font.rawValue ? "checkmark" : "textformat")) { [weak self] _ in
                    UserDefaults.standard.set(font.rawValue, forKey: "polaroidFont")
                    self?.reconfigureVisible()
                }
            })
            let storedWeight = UserDefaults.standard.string(forKey: "polaroidFontWeight") ?? PolaroidFontWeight.regular.rawValue
            weightMenuElement = UIMenu(title: NSLocalizedString("Font Weight", comment: ""),
                                       image: UIImage(systemName: "bold"),
                                       children: PolaroidFontWeight.allCases.map { w in
                UIAction(title: w.displayName,
                         image: UIImage(systemName: storedWeight == w.rawValue ? "checkmark" : "bold")) { [weak self] _ in
                    UserDefaults.standard.set(w.rawValue, forKey: "polaroidFontWeight")
                    self?.reconfigureVisible()
                }
            })
        } else {
            fontMenuElement = UIAction(title: NSLocalizedString("Caption Font", comment: ""),
                                       image: UIImage(systemName: "lock.fill")) { [weak self] _ in self?.showPaywall() }
            weightMenuElement = UIAction(title: NSLocalizedString("Font Weight", comment: ""),
                                         image: UIImage(systemName: "lock.fill")) { [weak self] _ in self?.showPaywall() }
        }

        return UIMenu(children: [filterMenu, sortMenu, gridMenu, fontMenuElement, weightMenuElement])
    }

    // MARK: - Select toolbar

    private func updateSelectToolbar() {
        guard isSelectMode else {
            selectToolbar?.removeFromSuperview()
            selectToolbar = nil
            return
        }

        if selectToolbar == nil {
            let tb = UIToolbar()
            tb.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(tb)
            NSLayoutConstraint.activate([
                tb.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                tb.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                tb.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])
            selectToolbar = tb
        }

        guard !selectedIDs.isEmpty else { selectToolbar?.items = []; return }

        let flex = UIBarButtonItem(systemItem: .flexibleSpace)
        let shareBtn = UIBarButtonItem(image: UIImage(systemName: "square.and.arrow.up"), style: .plain,
                                       target: self, action: #selector(shareSelected))
        let saveIcon = saveDidSucceed ? "checkmark" : "square.and.arrow.down"
        let saveBtn = UIBarButtonItem(image: UIImage(systemName: saveIcon), style: .plain,
                                      target: self, action: #selector(saveSelected))
        saveBtn.isEnabled = !isSaving && !saveDidSucceed
        let deleteBtn = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain,
                                        target: self, action: #selector(deleteSelectedPrompt))
        deleteBtn.tintColor = .systemRed
        selectToolbar?.items = [shareBtn, flex, saveBtn, flex, deleteBtn]
    }

    // MARK: - Search

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("Search captions\u{2026}", comment: "")
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = true
        definesPresentationContext = true
    }

    // MARK: - Pinch / drag-select

    private func setupGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        collectionView.addGestureRecognizer(pinch)

        let dragPan = UIPanGestureRecognizer(target: self, action: #selector(handleDragSelect(_:)))
        dragPan.delegate = self
        collectionView.addGestureRecognizer(dragPan)
        dragSelectPanGesture = dragPan
    }

    @objc private func handlePinch(_ gr: UIPinchGestureRecognizer) {
        guard gr.state == .ended else { return }
        if gr.scale > 1.4, columnCount > 1 { columnCount -= 1 }
        else if gr.scale < 0.75, columnCount < 3 { columnCount += 1 }
    }

    @objc private func handleDragSelect(_ gr: UIPanGestureRecognizer) {
        guard isSelectMode else { return }
        let location = gr.location(in: collectionView)

        switch gr.state {
        case .began:
            dragSelectVisited.removeAll()
            guard let indexPath = collectionView.indexPathForItem(at: location),
                  let id = dataSource.itemIdentifier(for: indexPath) else { return }
            dragSelectInitialState = !selectedIDs.contains(id)
            dragSelectVisited.insert(id)
            applyDragSelection(id: id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

        case .changed:
            guard dragSelectInitialState != nil,
                  let indexPath = collectionView.indexPathForItem(at: location),
                  let id = dataSource.itemIdentifier(for: indexPath),
                  !dragSelectVisited.contains(id) else { return }
            dragSelectVisited.insert(id)
            applyDragSelection(id: id)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

        case .ended, .cancelled, .failed:
            dragSelectInitialState = nil
            dragSelectVisited.removeAll()

        default: break
        }
    }

    private func applyDragSelection(id: UUID) {
        guard let selecting = dragSelectInitialState else { return }
        if selecting { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
        var snap = dataSource.snapshot()
        snap.reconfigureItems([id])
        dataSource.apply(snap, animatingDifferences: false)
    }

    // MARK: - Navigation

    private func openDetail(for entry: PolaroidEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let vc = PolaroidDetailViewController()
        vc.entries = entries
        vc.startIndex = idx
        vc.store = store
        vc.modelContext = modelContext

        if #available(iOS 18.0, *) {
            vc.preferredTransition = .zoom { [weak self] context in
                guard let self,
                      let detailVC = context.zoomedViewController as? PolaroidDetailViewController,
                      let entryID = detailVC.currentEntryID,
                      let indexPath = self.dataSource.indexPath(for: entryID) else { return nil }
                return self.collectionView.cellForItem(at: indexPath)
            }
        }

        vc.onCurrentIndexChange = { [weak self] entryID in
            guard let self,
                  let indexPath = self.dataSource.indexPath(for: entryID) else { return }
            self.collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        }

        navigationController?.pushViewController(vc, animated: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.delegate = self
    }

    // MARK: - Actions

    @objc private func toggleSelectMode() {
        isSelectMode.toggle()
    }

    private func toggleSelection(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
        if let idx = filteredEntries.firstIndex(where: { $0.id == id }),
           let cell = collectionView.cellForItem(at: IndexPath(item: idx, section: 0)) {
            configure(cell: cell, forID: id)
        }
    }

    @objc private func shareSelected() {
        let selected = entries.filter { selectedIDs.contains($0.id) }
        Task {
            let items = await prepareShareItems(for: selected, videoDirectory: store.videoDirectory)
            await MainActor.run {
                present(UIActivityViewController(activityItems: items, applicationActivities: nil), animated: true)
            }
        }
    }

    @objc private func saveSelected() {
        guard !isSaving, !saveDidSucceed else { return }
        let selected = entries.filter { selectedIDs.contains($0.id) }
        Task { await saveToPhotosApp(selected) }
    }

    @objc private func deleteSelectedPrompt() {
        let count = selectedIDs.count
        let title = count == 1
            ? NSLocalizedString("Delete 1 photo?", comment: "")
            : String(format: NSLocalizedString("Delete %d photos?", comment: ""), count)
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: NSLocalizedString("Delete", comment: ""), style: .destructive) { [weak self] _ in
            guard let self else { return }
            let ids = self.selectedIDs
            self.selectedIDs.removeAll()
            self.isSelectMode = false
            self.deleteEntries(ids: ids)
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel))
        present(alert, animated: true)
    }

    @MainActor
    private func saveToPhotosApp(_ entriesToSave: [PolaroidEntry]) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { return }
        isSaving = true
        updateSelectToolbar()
        var items: [(UIImage?, URL?)] = []
        for entry in entriesToSave {
            if let filename = entry.videoFilename {
                let src = store.videoDirectory.appendingPathComponent(filename)
                let composited = await compositePolaroidVideo(entry, sourceURL: src) ?? src
                items.append((nil, composited))
            } else {
                items.append((renderPolaroidFrame(entry), nil))
            }
        }
        try? await PHPhotoLibrary.shared().performChanges {
            for (image, videoURL) in items {
                if let videoURL { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL) }
                else if let image { PHAssetChangeRequest.creationRequestForAsset(from: image) }
            }
        }
        isSaving = false
        saveDidSucceed = true
        updateSelectToolbar()
        try? await Task.sleep(for: .seconds(2))
        saveDidSucceed = false
        updateSelectToolbar()
    }

    private func deleteEntries(ids: Set<UUID>) {
        var snap = dataSource.snapshot()
        snap.deleteItems(Array(ids))
        dataSource.apply(snap, animatingDifferences: true)
        Task {
            try? await Task.sleep(for: .seconds(0.35))
            for id in ids {
                if let entry = entries.first(where: { $0.id == id }) {
                    if let filename = entry.videoFilename { store.deleteVideo(filename: filename) }
                    modelContext.delete(entry)
                }
            }
        }
    }

    private func showPaywall() {
        let vc = UIHostingController(rootView: PaywallView(onClose: { [weak self] in self?.dismiss(animated: true) })
            .environment(PremiumManager.shared))
        present(vc, animated: true)
    }

    // MARK: - Context menu

    override func collectionView(_ collectionView: UICollectionView,
                                  contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
                                  point: CGPoint) -> UIContextMenuConfiguration? {
        guard let indexPath = indexPaths.first,
              let id = dataSource.itemIdentifier(for: indexPath),
              let entry = entriesByID[id] else { return nil }

        return UIContextMenuConfiguration { [weak self] _ in
            guard let self else { return UIMenu() }
            return UIMenu(children: [
                UIAction(title: NSLocalizedString("Edit Caption & Notes", comment: ""),
                         image: UIImage(systemName: "pencil.and.outline")) { [weak self] _ in
                    self?.editEntry(entry)
                },
                UIAction(title: NSLocalizedString("Save to Photos", comment: ""),
                         image: UIImage(systemName: "square.and.arrow.down")) { [weak self] _ in
                    Task { await self?.saveToPhotosApp([entry]) }
                },
                UIAction(title: NSLocalizedString("Share", comment: ""),
                         image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                    guard let self else { return }
                    Task {
                        let items = await prepareShareItems(for: [entry], videoDirectory: self.store.videoDirectory)
                        await MainActor.run {
                            self.present(UIActivityViewController(activityItems: items, applicationActivities: nil), animated: true)
                        }
                    }
                },
                UIAction(title: NSLocalizedString("Delete", comment: ""),
                         image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    self?.deleteEntries(ids: [entry.id])
                }
            ])
        }
    }

    private func editEntry(_ entry: PolaroidEntry) {
        let vc = UIHostingController(rootView: EditPolaroidSheet(entry: entry))
        vc.sheetPresentationController?.detents = [.medium(), .large()]
        vc.sheetPresentationController?.prefersGrabberVisible = true
        present(vc, animated: true)
    }
}

// MARK: - UIGestureRecognizerDelegate
extension LibraryViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
        guard gr === dragSelectPanGesture else { return true }
        guard isSelectMode else { return false }
        let location = gr.location(in: collectionView)
        return collectionView.indexPathForItem(at: location) != nil
    }

    func gestureRecognizer(_ gr: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return gr === dragSelectPanGesture || other === dragSelectPanGesture
    }
}

// MARK: - UISearchResultsUpdating
extension LibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        applySnapshot()
    }
}

// MARK: - UINavigationControllerDelegate
extension LibraryViewController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController,
                               didShow viewController: UIViewController, animated: Bool) {
        let isDeep = navigationController.viewControllers.count > 1
        // Notify SwiftUI so interactiveDismissDisabled can block the zoom-transition dismiss gesture.
        onDetailStateChange?(isDeep)
    }
}

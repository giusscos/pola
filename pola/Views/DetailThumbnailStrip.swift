import UIKit

/// The row of small thumbnails under a print in the detail view, like the one in Photos.
/// Dragging it scrubs through the library and tapping a thumbnail jumps to it. The current print
/// is shown wider with gaps around it, except while scrubbing, when every thumbnail is the same
/// width so the row doesn't shift under the finger.
final class DetailThumbnailStrip: UIView {
    static let height: CGFloat = 44

    private static let thumbnailWidth: CGFloat = 30
    private static let spacing: CGFloat = 2
    private static let expandedMargin: CGFloat = 8
    private static let expandedWidth: CGFloat = height + expandedMargin * 2
    private static let thumbnailPixelSize: CGFloat = height * 3

    var entries: [PolaroidEntry] = [] {
        didSet { collectionView.reloadData() }
    }

    /// Called with the index the person scrubbed or tapped to.
    var onSelect: ((Int) -> Void)?

    private static let edgeFadeWidth: CGFloat = 32

    private let layout = UICollectionViewFlowLayout()
    private let edgeFade = CAGradientLayer()
    private lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private var expandedIndex: Int?
    private var isScrubbing = false
    private var lastScrubbedIndex: Int?
    /// Set before the first layout, when there is no width yet to center an item in.
    private var pendingIndex: Int?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = Self.spacing
        layout.sectionInset = .zero

        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.decelerationRate = .fast
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(ThumbnailCell.self, forCellWithReuseIdentifier: ThumbnailCell.reuseID)
        collectionView.frame = bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(collectionView)

        // Thumbnails fade out toward the screen edges instead of being cut off.
        edgeFade.startPoint = CGPoint(x: 0, y: 0.5)
        edgeFade.endPoint = CGPoint(x: 1, y: 0.5)
        edgeFade.colors = [UIColor.clear, .black, .black, .clear].map(\.cgColor)
        layer.mask = edgeFade
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        edgeFade.frame = bounds
        let fade = bounds.width > 0 ? Self.edgeFadeWidth / bounds.width : 0
        edgeFade.locations = [0, fade, 1 - fade, 1].map { NSNumber(value: Double($0)) }
        CATransaction.commit()

        // Lets the first and last thumbnails reach the middle.
        let sideInset = max(0, (bounds.width - Self.thumbnailWidth) / 2)
        if collectionView.contentInset.left != sideInset {
            collectionView.contentInset = UIEdgeInsets(top: 0, left: sideInset, bottom: 0, right: sideInset)
        }
        if let pendingIndex, bounds.width > 0 {
            self.pendingIndex = nil
            expand(pendingIndex, animated: false)
        }
    }

    /// Follows the page shown above; ignored while the person is scrubbing the strip itself.
    func setCurrentIndex(_ index: Int, animated: Bool) {
        guard !isScrubbing else { return }
        guard bounds.width > 0 else {
            pendingIndex = index
            return
        }
        expand(index, animated: animated)
    }

    // MARK: - Expanding and centering

    private func expand(_ index: Int, animated: Bool) {
        guard index < entries.count else { return }
        expandedIndex = index
        let update = {
            self.layout.invalidateLayout()
            self.collectionView.layoutIfNeeded()
            self.collectionView.contentOffset.x = self.centeredOffsetX(for: index)
        }
        if animated {
            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut, .allowUserInteraction], animations: update)
        } else {
            update()
        }
        updateSelectedTraits()
    }

    private func collapse() {
        guard expandedIndex != nil else { return }
        expandedIndex = nil
        layout.invalidateLayout()
        collectionView.layoutIfNeeded()
        // The current thumbnail keeps its left edge, so its center moves left by half the width it lost.
        collectionView.contentOffset.x -= (Self.expandedWidth - Self.thumbnailWidth) / 2
    }

    private func centeredOffsetX(for index: Int) -> CGFloat {
        let indexPath = IndexPath(item: index, section: 0)
        guard let attributes = layout.layoutAttributesForItem(at: indexPath) else {
            return collectionView.contentOffset.x
        }
        return attributes.center.x - collectionView.bounds.width / 2
    }

    /// Only used while scrubbing, when every thumbnail has the same width.
    private func uniformIndex(atCenterX centerX: CGFloat) -> Int {
        let step = Self.thumbnailWidth + Self.spacing
        let raw = ((centerX - Self.thumbnailWidth / 2) / step).rounded()
        return min(max(0, Int(raw)), max(0, entries.count - 1))
    }

    private func uniformCenterX(for index: Int) -> CGFloat {
        CGFloat(index) * (Self.thumbnailWidth + Self.spacing) + Self.thumbnailWidth / 2
    }

    private func updateSelectedTraits() {
        for case let cell as ThumbnailCell in collectionView.visibleCells {
            guard let indexPath = collectionView.indexPath(for: cell) else { continue }
            cell.isCurrent = indexPath.item == expandedIndex
        }
    }

    // MARK: - Scrubbing

    private func finishScrubbing() {
        guard isScrubbing else { return }
        isScrubbing = false
        let index = uniformIndex(atCenterX: collectionView.contentOffset.x + collectionView.bounds.width / 2)
        if index != lastScrubbedIndex { onSelect?(index) }
        lastScrubbedIndex = nil
        expand(index, animated: true)
    }
}

// MARK: - UICollectionViewDataSource
extension DetailThumbnailStrip: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        entries.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ThumbnailCell.reuseID, for: indexPath)
        guard let thumbnailCell = cell as? ThumbnailCell else { return cell }
        thumbnailCell.configure(with: entries[indexPath.item], pixelSize: Self.thumbnailPixelSize)
        thumbnailCell.isCurrent = indexPath.item == expandedIndex
        return thumbnailCell
    }
}

// MARK: - UICollectionViewDelegateFlowLayout
extension DetailThumbnailStrip: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = indexPath.item == expandedIndex ? Self.expandedWidth : Self.thumbnailWidth
        return CGSize(width: width, height: Self.height)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        Self.spacing
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        Self.spacing
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !isScrubbing, indexPath.item != expandedIndex else { return }
        onSelect?(indexPath.item)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        isScrubbing = true
        lastScrubbedIndex = expandedIndex
        collapse()
        updateSelectedTraits()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard isScrubbing, !entries.isEmpty else { return }
        let index = uniformIndex(atCenterX: scrollView.contentOffset.x + scrollView.bounds.width / 2)
        guard index != lastScrubbedIndex else { return }
        lastScrubbedIndex = index
        onSelect?(index)
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard isScrubbing, !entries.isEmpty else { return }
        let halfWidth = scrollView.bounds.width / 2
        let index = uniformIndex(atCenterX: targetContentOffset.pointee.x + halfWidth)
        targetContentOffset.pointee.x = uniformCenterX(for: index) - halfWidth
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { finishScrubbing() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        finishScrubbing()
    }
}

// MARK: - Cell

private final class ThumbnailCell: UICollectionViewCell {
    static let reuseID = "DetailThumbnailCell"
    private static let expandedMargin: CGFloat = 8

    private let imageView = UIImageView()
    private var loadTask: Task<Void, Never>?
    private var entryID: UUID?

    var isCurrent = false {
        didSet {
            accessibilityTraits = isCurrent ? [.button, .selected] : .button
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = .secondarySystemFill
        contentView.addSubview(imageView)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Based on the width rather than `isCurrent`, so the gap grows and shrinks with the
        // expand animation instead of jumping.
        let isWide = bounds.width > bounds.height
        imageView.frame = isWide ? contentView.bounds.insetBy(dx: Self.expandedMargin, dy: 0) : contentView.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        loadTask?.cancel()
        loadTask = nil
        imageView.image = nil
    }

    func configure(with entry: PolaroidEntry, pixelSize: CGFloat) {
        entryID = entry.id
        accessibilityLabel = entry.caption.isEmpty
            ? entry.timestamp.formatted(date: .abbreviated, time: .shortened)
            : entry.caption
        if let cached = entry.cachedThumbnail(maxPixelSize: pixelSize) ?? entry.latestThumbnail {
            imageView.image = cached
            if entry.cachedThumbnail(maxPixelSize: pixelSize) != nil { return }
        }
        let id = entry.id
        loadTask = Task { [weak self] in
            let image = await entry.loadThumbnail(maxPixelSize: pixelSize)
            guard !Task.isCancelled, let self, self.entryID == id, let image else { return }
            self.imageView.image = image
        }
    }
}

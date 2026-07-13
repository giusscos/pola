import CoreMotion
import SwiftUI
import UIKit

// MARK: - SwiftUI wrapper

struct PolaroidPrintAnimationView: UIViewControllerRepresentable {
    let entry: PolaroidEntry
    let captionEnabled: Bool
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> PolaroidPrintAnimationVC {
        PolaroidPrintAnimationVC(entry: entry, captionEnabled: captionEnabled, onComplete: onComplete)
    }
    func updateUIViewController(_ uiViewController: PolaroidPrintAnimationVC, context: Context) {}
}

// MARK: - UIKit view controller

final class PolaroidPrintAnimationVC: UIViewController {

    // MARK: Subviews
    private let dimView          = UIView()
    private let polaroidView     = UIView()
    private let photoImageView   = UIImageView()
    private let developOverlay   = UIView()
    private let captionLabel     = UILabel()
    private let captionCard      = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let captionField     = UITextField()
    private let doneBtn          = UIButton(type: .system)
    private var shakeHint: UIVisualEffectView!

    // MARK: Data & callbacks
    private let entry: PolaroidEntry
    private let captionEnabled: Bool
    private let onComplete: () -> Void

    // MARK: Motion / timing
    private let motionManager           = CMMotionManager()
    private var displayLink: CADisplayLink?
    private var developStart: CFTimeInterval = 0
    private let developDuration: CFTimeInterval = 30
    private let impactLight  = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)

    // MARK: Geometry
    private let polaroidWidth:    CGFloat = 220
    private let imagePadding:     CGFloat = 8
    private let captionStripH:    CGFloat = 48
    private var imageAreaW:    CGFloat { polaroidWidth - imagePadding * 2 }
    private var imageAreaH:    CGFloat { imageAreaW * 4 / 3 }
    private var polaroidHeight:   CGFloat { imagePadding + imageAreaH + captionStripH }

    private var printEndCenter = CGPoint.zero
    private var screenCenter   = CGPoint.zero

    // MARK: State
    private var animationStarted  = false
    private var isDone            = false
    private var cardBottomConstraint: NSLayoutConstraint?

    // MARK: Init

    init(entry: PolaroidEntry, captionEnabled: Bool, onComplete: @escaping () -> Void) {
        self.entry = entry
        self.captionEnabled = captionEnabled
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildHierarchy()
        listenForKeyboard()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !animationStarted else { return }
        animationStarted = true
        prepareGeometry()
        impactLight.prepare()
        impactMedium.prepare()
        startPrint()
    }

    deinit {
        displayLink?.invalidate()
        motionManager.stopAccelerometerUpdates()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: Build views

    private func buildHierarchy() {
        // Dim backdrop
        dimView.backgroundColor = .black
        dimView.alpha = 0
        dimView.frame = UIScreen.main.bounds
        view.addSubview(dimView)
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(resignCaption)))

        // Polaroid outer frame
        polaroidView.backgroundColor = resolvedPackColor
        polaroidView.bounds = CGRect(origin: .zero, size: CGSize(width: polaroidWidth, height: polaroidHeight))
        polaroidView.layer.shadowColor  = UIColor.black.cgColor
        polaroidView.layer.shadowOpacity = 0.45
        polaroidView.layer.shadowRadius  = 14
        polaroidView.layer.shadowOffset  = CGSize(width: 0, height: 6)
        polaroidView.layer.shadowPath    = UIBezierPath(rect: polaroidView.bounds).cgPath
        view.addSubview(polaroidView)

        // Photo
        photoImageView.contentMode = .scaleAspectFill
        photoImageView.clipsToBounds = true
        photoImageView.image = entry.image
        photoImageView.frame = CGRect(x: imagePadding, y: imagePadding,
                                      width: imageAreaW, height: imageAreaH)
        polaroidView.addSubview(photoImageView)

        // Development veil — driven by CADisplayLink
        developOverlay.backgroundColor = .black
        developOverlay.alpha = 0.93
        developOverlay.frame = photoImageView.frame
        polaroidView.addSubview(developOverlay)

        // Caption strip label
        captionLabel.font = UIFont(name: "Bradley Hand", size: 13) ?? .systemFont(ofSize: 13)
        captionLabel.textColor = UIColor.black.withAlphaComponent(0.7)
        captionLabel.textAlignment = .center
        captionLabel.frame = CGRect(x: imagePadding,
                                    y: imagePadding + imageAreaH,
                                    width: imageAreaW,
                                    height: captionStripH)
        polaroidView.addSubview(captionLabel)

        buildShakeHint()
        buildCaptionCard()
    }

    private func buildShakeHint() {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.layer.cornerRadius = 18
        blur.clipsToBounds = true
        blur.alpha = 0
        blur.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blur)
        shakeHint = blur

        let icon = UIImageView(image: UIImage(systemName: "waveform"))
        icon.tintColor = UIColor.white.withAlphaComponent(0.82)
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let lbl = UILabel()
        lbl.text = "Shake to develop faster"
        lbl.font = .systemFont(ofSize: 12)
        lbl.textColor = UIColor.white.withAlphaComponent(0.82)

        let stack = UIStackView(arrangedSubviews: [icon, lbl])
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 9),
            stack.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -9),
            blur.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])
    }

    private func buildCaptionCard() {
        doneBtn.setTitle("Done", for: .normal)
        doneBtn.setTitleColor(.white, for: .normal)
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        doneBtn.translatesAutoresizingMaskIntoConstraints = false

        if captionEnabled {
            // Blurred card with text field + Done button
            captionCard.layer.cornerRadius = 16
            captionCard.clipsToBounds = true
            captionCard.alpha = 0
            captionCard.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(captionCard)

            let cv = captionCard.contentView

            captionField.placeholder = "Add a caption..."
            captionField.font = .systemFont(ofSize: 15)
            captionField.backgroundColor = .systemGray6
            captionField.layer.cornerRadius = 10
            captionField.clipsToBounds = true
            captionField.leftView  = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
            captionField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
            captionField.leftViewMode  = .always
            captionField.rightViewMode = .always
            captionField.returnKeyType = .done
            captionField.addTarget(self, action: #selector(returnTapped), for: .editingDidEndOnExit)
            captionField.translatesAutoresizingMaskIntoConstraints = false
            cv.addSubview(captionField)

            doneBtn.titleLabel?.font = .boldSystemFont(ofSize: 15)
            cv.addSubview(doneBtn)

            let bottom = captionCard.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
            cardBottomConstraint = bottom

            NSLayoutConstraint.activate([
                captionCard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
                captionCard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
                bottom,
                captionField.topAnchor.constraint(equalTo: cv.topAnchor, constant: 16),
                captionField.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: 16),
                captionField.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
                captionField.heightAnchor.constraint(equalToConstant: 44),
                doneBtn.topAnchor.constraint(equalTo: captionField.bottomAnchor, constant: 10),
                doneBtn.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -16),
                doneBtn.bottomAnchor.constraint(equalTo: cv.bottomAnchor, constant: -16),
                shakeHint.bottomAnchor.constraint(equalTo: captionCard.topAnchor, constant: -12),
            ])
        } else {
            // Standalone "Done" button — no card
            doneBtn.titleLabel?.font = .boldSystemFont(ofSize: 17)
            doneBtn.alpha = 0
            view.addSubview(doneBtn)

            NSLayoutConstraint.activate([
                doneBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                doneBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
                shakeHint.bottomAnchor.constraint(equalTo: doneBtn.topAnchor, constant: -20),
            ])
        }
    }

    // MARK: Geometry

    private func prepareGeometry() {
        let safeTop  = view.safeAreaInsets.top
        let diBottom = max(10, safeTop - 20)
        let w = view.bounds.width
        let h = view.bounds.height

        // Start: bottom edge of polaroid at the DI slot (rest is hidden above screen)
        polaroidView.center = CGPoint(x: w / 2, y: diBottom - polaroidHeight / 2)
        polaroidView.transform = .identity

        printEndCenter = CGPoint(x: w / 2, y: safeTop + polaroidHeight / 2 + 15)
        screenCenter   = CGPoint(x: w / 2, y: h / 2 - 60)
    }

    // MARK: Animation sequence

    private func startPrint() {
        UIView.animate(
            withDuration: 1.8,
            delay: 0,
            usingSpringWithDamping: 0.80,
            initialSpringVelocity: 0,
            options: .curveEaseOut
        ) {
            self.polaroidView.center = self.printEndCenter
        } completion: { _ in
            self.impactLight.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.expandToCenter() }
        }
    }

    private func expandToCenter() {
        UIView.animate(
            withDuration: 0.55,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.3,
            options: []
        ) {
            self.polaroidView.center = self.screenCenter
            self.dimView.alpha = 0.55
        } completion: { _ in
            self.impactMedium.impactOccurred()
            self.showCaptionCard()
            self.startDevelopment()
            self.startShakeDetection()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.revealShakeHint() }
        }
    }

    private func showCaptionCard() {
        let target: UIView = captionEnabled ? captionCard : doneBtn
        target.transform = CGAffineTransform(translationX: 0, y: 50)
        UIView.animate(
            withDuration: 0.45,
            delay: 0,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.2,
            options: []
        ) {
            target.alpha = 1
            target.transform = .identity
        }
    }

    private func revealShakeHint() {
        guard !isDone else { return }
        shakeHint.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
        UIView.animate(
            withDuration: 0.38,
            delay: 0,
            usingSpringWithDamping: 0.68,
            initialSpringVelocity: 0.2,
            options: []
        ) {
            self.shakeHint.alpha = 1
            self.shakeHint.transform = .identity
        }
    }

    // MARK: Commit & fly

    private func commit() {
        guard !isDone else { return }
        isDone = true
        captionField.resignFirstResponder()
        impactLight.impactOccurred()

        if captionEnabled {
            let text = captionField.text?.trimmingCharacters(in: .whitespaces) ?? ""
            if !text.isEmpty {
                entry.caption = text
                captionLabel.text = text
            }
        }

        let elapsed = CACurrentMediaTime() - developStart
        entry.developmentProgress = max(entry.developmentProgress, min(1.0, elapsed / developDuration))
        displayLink?.invalidate()
        displayLink = nil
        motionManager.stopAccelerometerUpdates()

        UIView.animate(withDuration: 0.18) {
            self.captionCard.alpha = 0
            self.doneBtn.alpha     = 0
            self.shakeHint.alpha   = 0
            self.dimView.alpha     = 0
        } completion: { _ in
            self.flyToBottom()
        }
    }

    private func flyToBottom() {
        let h = view.bounds.height
        let currentX = polaroidView.center.x
        UIView.animate(
            withDuration: 0.45,
            delay: 0,
            options: .curveEaseIn
        ) {
            self.polaroidView.center = CGPoint(x: currentX, y: h + self.polaroidHeight / 2)
            self.polaroidView.transform = CGAffineTransform(scaleX: 0.25, y: 0.25)
            self.polaroidView.alpha = 0
        } completion: { _ in
            self.onComplete()
        }
    }

    // MARK: Actions

    @objc private func doneTapped()   { commit() }
    @objc private func returnTapped() { commit() }
    @objc private func resignCaption() { captionField.resignFirstResponder() }

    // MARK: Development (60 fps via CADisplayLink)

    private func startDevelopment() {
        developStart = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(tickDevelopment))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func tickDevelopment() {
        let elapsed   = CACurrentMediaTime() - developStart
        let progress  = min(1.0, elapsed / developDuration)
        // Disable implicit layer animation so the alpha update is instantaneous each frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        developOverlay.alpha = CGFloat(max(0, 0.93 * (1.0 - progress)))
        entry.developmentProgress = max(entry.developmentProgress, progress)
        CATransaction.commit()
        if progress >= 1.0 {
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    // MARK: Shake detection

    private func startShakeDetection() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 0.1
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
            guard let data, let self else { return }
            let a = data.acceleration
            if sqrt(a.x*a.x + a.y*a.y + a.z*a.z) > 2.5 {
                // Wind the clock forward — each shake jumps ~6 s of development
                self.developStart -= 6
                self.impactLight.impactOccurred()
            }
        }
    }

    // MARK: Keyboard avoidance

    private func listenForKeyboard() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ n: Notification) {
        guard let info = n.userInfo,
              let frame    = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        let overlap = frame.height - view.safeAreaInsets.bottom
        cardBottomConstraint?.constant = -(overlap + 12)
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }

    @objc private func keyboardWillHide(_ n: Notification) {
        guard let duration = n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double
        else { return }
        cardBottomConstraint?.constant = -20
        UIView.animate(withDuration: duration) { self.view.layoutIfNeeded() }
    }

    // MARK: Helpers

    private var resolvedPackColor: UIColor {
        if let hex = entry.packColorHex, let c = Color(hex: hex) { return UIColor(c) }
        if let pack = polaPackColors.first(where: { $0.name == entry.packName }) { return UIColor(pack.color) }
        return .white
    }
}

// MARK: - Multi-polaroid print animation (time-lapse burst)

struct MultiPolaroidPrintAnimationView: UIViewControllerRepresentable {
    let entries: [PolaroidEntry]
    let onComplete: () -> Void

    func makeUIViewController(context: Context) -> MultiPolaroidPrintAnimationVC {
        MultiPolaroidPrintAnimationVC(entries: entries, onComplete: onComplete)
    }
    func updateUIViewController(_ vc: MultiPolaroidPrintAnimationVC, context: Context) {}
}

final class MultiPolaroidPrintAnimationVC: UIViewController {

    // MARK: Data
    private let entries: [PolaroidEntry]
    private let onComplete: () -> Void

    // MARK: Subviews
    private let dimView     = UIView()
    private var cardViews   = [UIView]()
    private let doneBtn     = UIButton(type: .system)
    private var countBadge: UIVisualEffectView?

    // MARK: Geometry
    private let maxVisible      = 5
    private let polaroidWidth:  CGFloat = 196
    private let imagePadding:   CGFloat = 7
    private let captionStripH:  CGFloat = 38
    private var imageAreaW:     CGFloat { polaroidWidth - imagePadding * 2 }
    private var imageAreaH:     CGFloat { imageAreaW * 4 / 3 }
    private var polaroidHeight: CGFloat { imagePadding + imageAreaH + captionStripH }

    // Rotations / offsets for each card in the stack (index 0 = printed first = back)
    private let stackRotations: [CGFloat] = [-7, 5, -3, 9, -2]
    private let stackOffsets: [(CGFloat, CGFloat)] = [(2, 4), (-3, 7), (4, 10), (-5, 3), (1, 8)]

    // MARK: Haptics / state
    private let impactLight  = UIImpactFeedbackGenerator(style: .light)
    private let impactMedium = UIImpactFeedbackGenerator(style: .medium)
    private var animationStarted = false
    private var isDone = false

    // MARK: Init
    init(entries: [PolaroidEntry], onComplete: @escaping () -> Void) {
        self.entries = entries
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        buildHierarchy()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !animationStarted else { return }
        animationStarted = true
        impactLight.prepare()
        impactMedium.prepare()
        startPrinting()
    }

    // MARK: Build views
    private func buildHierarchy() {
        dimView.backgroundColor = .black
        dimView.alpha = 0
        dimView.frame = UIScreen.main.bounds
        view.addSubview(dimView)

        // Cards added in order so card[0] = back, card[last] = front
        let visible = Array(entries.prefix(maxVisible))
        for entry in visible {
            let card = buildCard(for: entry)
            view.addSubview(card)
            cardViews.append(card)
        }

        // Done button
        doneBtn.setTitle("Done", for: .normal)
        doneBtn.titleLabel?.font = .boldSystemFont(ofSize: 17)
        doneBtn.alpha = 0
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(doneBtn)
        doneBtn.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        // Count badge
        if entries.count > 1 {
            buildCountBadge(count: entries.count)
        }

        NSLayoutConstraint.activate([
            doneBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            doneBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
    }

    private func buildCard(for entry: PolaroidEntry) -> UIView {
        let card = UIView()
        let packColor: UIColor = {
            if let hex = entry.packColorHex, let c = Color(hex: hex) { return UIColor(c) }
            if let pack = polaPackColors.first(where: { $0.name == entry.packName }) { return UIColor(pack.color) }
            return .white
        }()
        card.backgroundColor = packColor
        card.bounds = CGRect(origin: .zero, size: CGSize(width: polaroidWidth, height: polaroidHeight))
        card.layer.shadowColor   = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.40
        card.layer.shadowRadius  = 9
        card.layer.shadowOffset  = CGSize(width: 0, height: 5)
        card.layer.shadowPath    = UIBezierPath(rect: card.bounds).cgPath

        let imgView = UIImageView(image: entry.image)
        imgView.contentMode = .scaleAspectFill
        imgView.clipsToBounds = true
        imgView.frame = CGRect(x: imagePadding, y: imagePadding, width: imageAreaW, height: imageAreaH)
        card.addSubview(imgView)

        if !entry.caption.isEmpty {
            let lbl = UILabel()
            lbl.text  = entry.caption
            lbl.font  = UIFont(name: "Bradley Hand", size: 11) ?? .systemFont(ofSize: 11)
            lbl.textColor = UIColor.black.withAlphaComponent(0.7)
            lbl.textAlignment = .center
            lbl.frame = CGRect(x: imagePadding, y: imagePadding + imageAreaH,
                               width: imageAreaW, height: captionStripH)
            card.addSubview(lbl)
        }
        return card
    }

    private func buildCountBadge(count: Int) {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
        blur.layer.cornerRadius = 14
        blur.clipsToBounds = true
        blur.alpha = 0
        blur.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(blur)
        countBadge = blur

        let lbl = UILabel()
        lbl.text  = "\(count) polaroids"
        lbl.font  = .systemFont(ofSize: 13, weight: .semibold)
        lbl.textColor = .white
        lbl.translatesAutoresizingMaskIntoConstraints = false
        blur.contentView.addSubview(lbl)

        NSLayoutConstraint.activate([
            lbl.leadingAnchor.constraint(equalTo: blur.contentView.leadingAnchor, constant: 14),
            lbl.trailingAnchor.constraint(equalTo: blur.contentView.trailingAnchor, constant: -14),
            lbl.topAnchor.constraint(equalTo: blur.contentView.topAnchor, constant: 8),
            lbl.bottomAnchor.constraint(equalTo: blur.contentView.bottomAnchor, constant: -8),
            blur.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            blur.bottomAnchor.constraint(equalTo: doneBtn.topAnchor, constant: -16),
        ])
    }

    // MARK: Animation

    private func startPrinting() {
        let w        = view.bounds.width
        let h        = view.bounds.height
        let safeTop  = view.safeAreaInsets.top
        let diY      = max(10, safeTop - 20)
        let startY   = diY - polaroidHeight / 2
        let printEnd = CGPoint(x: w / 2, y: safeTop + polaroidHeight / 2 + 10)
        let stackCenter = CGPoint(x: w / 2, y: h / 2 - 50)

        for card in cardViews {
            card.center    = CGPoint(x: w / 2, y: startY)
            card.transform = .identity
            card.alpha     = 1
        }

        let count = cardViews.count
        for (i, card) in cardViews.enumerated() {
            let delay    = Double(i) * 0.25
            let rotation = stackRotations[i % stackRotations.count]
            let offset   = stackOffsets[i % stackOffsets.count]

            UIView.animate(
                withDuration: 0.60,
                delay: delay,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0,
                options: .curveEaseOut
            ) {
                card.center = printEnd
            } completion: { [weak self] _ in
                guard let self else { return }
                self.impactLight.impactOccurred()
                UIView.animate(
                    withDuration: 0.42,
                    delay: 0.04,
                    usingSpringWithDamping: 0.72,
                    initialSpringVelocity: 0.2,
                    options: []
                ) {
                    card.center    = CGPoint(x: stackCenter.x + offset.0, y: stackCenter.y + offset.1)
                    card.transform = CGAffineTransform(rotationAngle: rotation * .pi / 180)
                    if i == 0 { self.dimView.alpha = 0.50 }
                } completion: { [weak self] _ in
                    guard let self else { return }
                    if i == count - 1 {
                        self.impactMedium.impactOccurred()
                        self.showControls()
                    } else {
                        self.impactLight.impactOccurred()
                    }
                }
            }
        }
    }

    private func showControls() {
        let targets: [UIView?] = [countBadge, doneBtn]
        for target in targets.compactMap({ $0 }) {
            target.transform = CGAffineTransform(translationX: 0, y: 40)
            UIView.animate(
                withDuration: 0.42,
                delay: 0,
                usingSpringWithDamping: 0.76,
                initialSpringVelocity: 0.2,
                options: []
            ) {
                target.alpha     = 1
                target.transform = .identity
            }
        }
    }

    // MARK: Actions

    @objc private func doneTapped() {
        guard !isDone else { return }
        isDone = true
        impactLight.impactOccurred()
        let h = view.bounds.height

        UIView.animate(withDuration: 0.15) {
            self.doneBtn.alpha    = 0
            self.countBadge?.alpha = 0
            self.dimView.alpha    = 0
        } completion: { _ in
            UIView.animate(
                withDuration: 0.38,
                delay: 0,
                options: .curveEaseIn
            ) {
                for card in self.cardViews {
                    card.center    = CGPoint(x: 44, y: h)
                    card.transform = CGAffineTransform(scaleX: 0.12, y: 0.12)
                    card.alpha     = 0
                }
            } completion: { _ in
                self.onComplete()
            }
        }
    }
}

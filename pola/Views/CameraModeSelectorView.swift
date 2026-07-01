import UIKit
import SwiftUI

// MARK: - UIKit Core

final class CameraModeSelectorUIView: UIView {

    var onModeChanged: ((CameraMode) -> Void)?
    private(set) var currentMode: CameraMode = .photo
    private(set) var isExpanded = false

    private let modes = CameraMode.allCases
    private var buttons: [UIButton] = []
    // Strip slides left/right so the selected item stays visually centred
    private let contentStrip = UIView()
    private var capsule: UIVisualEffectView!
    // Gradient mask fades the edges — removed in expanded mode
    private let fadeMask = CAGradientLayer()

    private let itemWidth: CGFloat = 90

    // Drag tracking for the long-press expand gesture
    private var dragStartX: CGFloat = 0
    private var dragStartModeIdx: Int = 0

    // Reusable haptic generators
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let impactFeedback    = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = .clear
        clipsToBounds = true

        contentStrip.backgroundColor = .clear
        addSubview(contentStrip)

        // Liquid Glass capsule — inside the strip, behind the labels
        let effect = UIGlassEffect(style: .regular)
        capsule = UIVisualEffectView(effect: effect)
        capsule.clipsToBounds = true
        contentStrip.addSubview(capsule)

        for (i, mode) in modes.enumerated() {
            let btn = UIButton(type: .custom)
            btn.setTitle(NSLocalizedString(mode.rawValue, comment: ""), for: .normal)
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
            btn.titleLabel?.adjustsFontSizeToFitWidth = true
            btn.titleLabel?.minimumScaleFactor = 0.75
            btn.titleLabel?.lineBreakMode = .byClipping
            btn.setTitleColor(.white.withAlphaComponent(0.5), for: .normal)
            btn.setTitleColor(.systemYellow, for: .selected)
            btn.tag = i
            btn.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            contentStrip.addSubview(btn)
            buttons.append(btn)
        }

        // Edge-fade mask: clear → black → black → clear
        fadeMask.startPoint = CGPoint(x: 0, y: 0.5)
        fadeMask.endPoint   = CGPoint(x: 1, y: 0.5)
        fadeMask.colors     = fadedColors
        fadeMask.locations  = [0, 0.18, 0.82, 1.0]
        layer.mask = fadeMask

        let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        lp.minimumPressDuration = 0.35
        addGestureRecognizer(lp)

        for dir: UISwipeGestureRecognizer.Direction in [.left, .right] {
            let s = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
            s.direction = dir
            addGestureRecognizer(s)
        }

        updateButtonStyles(animated: false)
    }

    // MARK: - Haptics

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        selectionFeedback.prepare()
    }

    // MARK: - Gradient mask

    private var fadedColors: [CGColor] {
        [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
    }
    private var fullColors: [CGColor] { Array(repeating: UIColor.black.cgColor, count: 4) }

    private func animateMask(to colors: [CGColor], duration: TimeInterval) {
        fadeMask.removeAllAnimations()
        let anim = CABasicAnimation(keyPath: "colors")
        anim.fromValue = (fadeMask.presentation() ?? fadeMask).colors
        anim.toValue   = colors
        anim.duration  = duration
        fadeMask.colors = colors
        fadeMask.add(anim, forKey: "colorsAnim")
    }

    // MARK: - Geometry
    // Both normal and expanded modes use the same formula:
    // the strip always slides so that the selected item is visually centred.
    // In expanded mode the view is wider (side buttons hidden), so more of the
    // adjacent items become naturally visible without changing any item widths.

    private func stripOffset(forMode mode: CameraMode) -> CGFloat {
        guard let idx = modes.firstIndex(of: mode), bounds.width > 0 else { return 0 }
        return bounds.width / 2 - (CGFloat(idx) + 0.5) * itemWidth
    }

    private func capsuleRect(forIndex idx: Int) -> CGRect {
        let pad: CGFloat = 4
        let h: CGFloat   = min(bounds.height, 32)
        return CGRect(x: CGFloat(idx) * itemWidth + pad,
                      y: (bounds.height - h) / 2,
                      width: itemWidth - pad * 2,
                      height: h)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = bounds
        CATransaction.commit()

        let totalW  = itemWidth * CGFloat(modes.count)
        let offsetX = stripOffset(forMode: currentMode)

        contentStrip.frame = CGRect(x: offsetX, y: 0, width: totalW, height: bounds.height)
        for (i, btn) in buttons.enumerated() {
            btn.frame = CGRect(x: CGFloat(i) * itemWidth, y: 0, width: itemWidth, height: bounds.height)
        }
        if let idx = modes.firstIndex(of: currentMode) {
            let cr = capsuleRect(forIndex: idx)
            capsule.frame = cr
            capsule.layer.cornerRadius = cr.height / 2
        }
    }

    // MARK: - Public API

    func setMode(_ mode: CameraMode, animated: Bool) {
        guard mode != currentMode else { return }
        currentMode = mode
        updateButtonStyles(animated: animated)
        slideStrip(toMode: mode, animated: animated)
    }

    // MARK: - Expand / Collapse
    // Only the gradient mask changes — the strip layout is identical in both states.

    private func expandPicker() {
        guard !isExpanded else { return }
        isExpanded = true
        animateMask(to: fullColors, duration: 0.25)
        impactFeedback.impactOccurred()
    }

    private func collapsePicker() {
        guard isExpanded else { return }
        isExpanded = false
        animateMask(to: fadedColors, duration: 0.35)
    }

    // MARK: - Strip animation (shared by normal mode, expanded drag, and tap)

    private func slideStrip(toMode mode: CameraMode, animated: Bool) {
        guard let idx = modes.firstIndex(of: mode), bounds.width > 0 else { return }
        let totalW  = itemWidth * CGFloat(modes.count)
        let offsetX = stripOffset(forMode: mode)
        let cr      = capsuleRect(forIndex: idx)

        let apply: () -> Void = {
            self.contentStrip.frame = CGRect(x: offsetX, y: 0, width: totalW, height: self.bounds.height)
            // The capsule moves +itemWidth inside the strip while the strip moves
            // -itemWidth, so the capsule stays visually fixed at the centre.
            self.capsule.frame = cr
            self.capsule.layer.cornerRadius = cr.height / 2
        }

        if animated {
            UIView.animate(withDuration: 0.42, delay: 0,
                           usingSpringWithDamping: 0.72, initialSpringVelocity: 0.3,
                           options: [.allowUserInteraction, .beginFromCurrentState],
                           animations: apply)
        } else {
            apply()
        }
    }

    // MARK: - Button visual state

    private func updateButtonStyles(animated: Bool) {
        for (i, btn) in buttons.enumerated() {
            let sel   = modes[i] == currentMode
            let scale = CGFloat(sel ? 1.0 : 0.82)
            btn.isSelected = sel
            if animated {
                UIView.animate(withDuration: 0.22, delay: 0,
                               options: [.allowUserInteraction, .beginFromCurrentState]) {
                    btn.transform = CGAffineTransform(scaleX: scale, y: scale)
                }
            } else {
                btn.transform = CGAffineTransform(scaleX: scale, y: scale)
            }
        }
    }

    // MARK: - Gesture handlers

    @objc private func tapped(_ sender: UIButton) {
        let mode = modes[sender.tag]
        guard mode != currentMode else { return }
        currentMode = mode
        updateButtonStyles(animated: true)
        slideStrip(toMode: mode, animated: true)
        selectionFeedback.selectionChanged()
        onModeChanged?(mode)
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            dragStartX       = gesture.location(in: self).x
            dragStartModeIdx = modes.firstIndex(of: currentMode) ?? 0
            selectionFeedback.prepare()
            expandPicker()

        case .changed:
            guard isExpanded else { return }
            // Compute how many items the finger has moved from the start position,
            // then snap to the nearest mode — identical to the original SwiftUI approach.
            let delta  = dragStartX - gesture.location(in: self).x
            let steps  = Int(round(delta / itemWidth))
            let newIdx = max(0, min(modes.count - 1, dragStartModeIdx + steps))
            let mode   = modes[newIdx]
            guard mode != currentMode else { return }
            currentMode = mode
            updateButtonStyles(animated: true)
            // The strip slides to keep the new selection centred,
            // so the other modes appear to move around it.
            slideStrip(toMode: mode, animated: true)
            selectionFeedback.selectionChanged()
            onModeChanged?(mode)

        case .ended, .cancelled, .failed:
            collapsePicker()

        default:
            break
        }
    }

    @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
        guard !isExpanded, let idx = modes.firstIndex(of: currentMode) else { return }
        let delta  = gesture.direction == .left ? 1 : -1
        let newIdx = max(0, min(modes.count - 1, idx + delta))
        guard newIdx != idx else { return }
        currentMode = modes[newIdx]
        updateButtonStyles(animated: true)
        slideStrip(toMode: currentMode, animated: true)
        selectionFeedback.selectionChanged()
        onModeChanged?(currentMode)
    }
}

// MARK: - SwiftUI representable

struct CameraModeSelectorView: UIViewRepresentable {
    @Binding var cameraMode: CameraMode

    func makeUIView(context: Context) -> CameraModeSelectorUIView {
        let v = CameraModeSelectorUIView()
        v.onModeChanged = { mode in cameraMode = mode }
        return v
    }

    func updateUIView(_ uiView: CameraModeSelectorUIView, context: Context) {
        uiView.setMode(cameraMode, animated: true)
    }
}

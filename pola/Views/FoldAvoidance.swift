import SwiftUI

/// Moves centered controls off the iPhone Duo fold while it's partially folded.
/// System controls do this on their own; custom ones like the shutter have to ask for the
/// fold's reserved region. No-op before iOS 27.1 and on devices without a fold.
struct FoldAvoidance: ViewModifier {
    enum Strategy {
        /// Shifts the view without affecting layout. For small, self-sized controls.
        case offset
        /// Pads one side so a view that fills its container re-centres its content away from the fold.
        case inset
    }

    /// Width of the interactive part, centred in the view. `nil` means the whole view.
    var coreWidth: CGFloat?
    var strategy: Strategy

    @State private var shift: CGFloat = 0

    func body(content: Content) -> some View {
        Group {
            switch strategy {
            case .offset:
                content.offset(x: shift)
            case .inset:
                // Padding by twice the shift moves the centre by exactly the shift.
                content
                    .padding(.leading, max(shift, 0) * 2)
                    .padding(.trailing, max(-shift, 0) * 2)
            }
        }
        // Measured outside the padding/offset so the shift never feeds back into its own input.
        .onGeometryChange(for: CGFloat.self) { proxy in
            requiredShift(in: proxy)
        } action: { newShift in
            withAnimation(.spring(duration: 0.35, bounce: 0.1)) { shift = newShift }
        }
    }

    private func requiredShift(in proxy: GeometryProxy) -> CGFloat {
        guard #available(iOS 27.1, *) else { return 0 }
        let bounds = CGRect(origin: .zero, size: proxy.size)
        let core = coreWidth.map {
            CGRect(x: bounds.midX - $0 / 2, y: bounds.minY, width: $0, height: bounds.height)
        } ?? bounds

        // Only a vertical fold can be avoided by sliding sideways.
        let folds = proxy.reservedRegions(kind: .division)
            .filter { $0.isActive && $0.frame.height > $0.frame.width && $0.frame.intersects(core) }
        guard let fold = folds.first else { return 0 }

        let toTrailing = fold.frame.maxX - core.minX
        let toLeading = core.maxX - fold.frame.minX
        return toTrailing <= toLeading ? toTrailing : -toLeading
    }
}

extension View {
    func foldAvoiding(coreWidth: CGFloat? = nil, strategy: FoldAvoidance.Strategy = .offset) -> some View {
        modifier(FoldAvoidance(coreWidth: coreWidth, strategy: strategy))
    }
}

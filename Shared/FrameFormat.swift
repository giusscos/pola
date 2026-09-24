import CoreGraphics

/// Instant-film sizes. Shared by the app and the widget.
enum FrameFormat: String, CaseIterable, Codable, Identifiable {
    case classic
    case square
    case wide
    case mini

    var id: String { rawValue }

    /// Width / height of the whole polaroid, border and caption strip included.
    /// Tuned so the photo area roughly matches the real film at the caption size used for exports.
    var frameAspect: CGFloat {
        switch self {
        case .classic: 0.75
        case .square:  0.854
        case .wide:    1.22
        case .mini:    0.667
        }
    }

    /// Width / height of the photo window, used for viewfinder guides and UIKit print animations.
    var imageAspect: CGFloat {
        switch self {
        case .classic: 0.75
        case .square:  1.0
        case .wide:    1.6
        case .mini:    0.74
        }
    }

    var displayName: String {
        switch self {
        case .classic: "Classic"
        case .square:  "Square"
        case .wide:    "Wide"
        case .mini:    "Mini"
        }
    }

    var isFree: Bool { self == .classic }
}

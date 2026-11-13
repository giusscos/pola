import SwiftUI

/// A fixed design size that still follows Dynamic Type: the default text size looks exactly as
/// designed, larger accessibility sizes scale it up along with `relativeTo`.
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let width: Font.Width

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, width: Font.Width, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
        self.width = width
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design).width(width))
    }
}

extension View {
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default,
                    width: Font.Width = .standard, relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, width: width, relativeTo: style))
    }
}

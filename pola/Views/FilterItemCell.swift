import SwiftUI

struct FilterItemCell: View {
    let filter: FilmFilter
    var isSelected: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if let usdzName = filter.usdzName {
                    ModelSceneView(assetName: usdzName, gestureEnabled: false, autoRotate: true)
                } else {
                    Circle()
                        .fill(filter.color)
                        .frame(width: 40, height: 40)
                }
                if isSelected {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(filter.color)
                                .background(.white, in: .circle)
                                .padding(6)
                        }
                        Spacer()
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? filter.color : .clear, lineWidth: 3)
            )

            HStack(spacing: 4) {
                Circle()
                    .fill(filter.color)
                    .frame(width: 7, height: 7)

                Text(filter.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }
}

import SwiftUI

struct FilterItemCell: View {
    let filter: FilmFilter

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Color(.systemGray6)
                if let usdzName = filter.usdzName {
                    ModelSceneView(assetName: usdzName, gestureEnabled: false, padding: 10)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

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

import SwiftUI

struct FilterItemCell: View {
    let filter: FilmFilter
    var isSelected: Bool = false
    var locked: Bool = false
    var previewImage: UIImage? = nil

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                if let preview = previewImage {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else if let imageName = filter.imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(filter.color.opacity(0.25))
                    Circle()
                        .fill(filter.color)
                        .frame(width: 30, height: 30)
                }

                if locked {
                    Color.black.opacity(0.45)
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
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
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? filter.color : .clear, lineWidth: 3)
            )

            HStack(spacing: 4) {
                Circle()
                    .fill(filter.color)
                    .frame(width: 7, height: 7)

                Text(filter.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(locked ? .secondary : .primary)
                    .lineLimit(1)
            }
        }
    }
}

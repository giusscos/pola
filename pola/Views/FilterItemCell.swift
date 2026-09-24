import SwiftUI

struct FilterItemCell: View {
    let filter: FilmFilter
    var isSelected: Bool = false
    var locked: Bool = false
    var showNewBadge: Bool = false
    var showFreeBadge: Bool = false
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

                // Keep the look visible on locked stocks; a small badge is enough to signal premium.
                VStack {
                    HStack(alignment: .top) {
                        if showNewBadge {
                            NewBadge()
                        } else if showFreeBadge {
                            Text("FREE")
                                .font(.system(size: 9, weight: .heavy).width(.expanded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.2, green: 0.85, blue: 0.6), in: Capsule())
                        }
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(filter.color)
                                .background(.white, in: .circle)
                        } else if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(.black.opacity(0.55), in: Circle())
                        }
                    }
                    Spacer()
                }
                .padding(6)
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
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }
}

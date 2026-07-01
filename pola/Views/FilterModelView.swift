import SwiftUI

struct FilterModelView: View {
    let filter: FilmFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let imageName = filter.imageName {
                Image(imageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            overlayUI
        }
    }

    private var overlayUI: some View {
        VStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.white.opacity(0.15), in: .circle)
                }
                .padding(.leading, 20)
                .padding(.top, 16)
                Spacer()
            }

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(filter.color)
                    .frame(width: 10, height: 10)
                Text(filter.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 50)
        }
    }
}

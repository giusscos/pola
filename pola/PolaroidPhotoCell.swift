import SwiftUI

struct PolaroidPhotoCell: View {
    var image: UIImage? = nil
    // 0.0 = undeveloped (black), 1.0 = fully developed
    var developmentProgress: Double = 1.0

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .overlay(alignment: .center) {
                        // Development overlay — fades from solid black to transparent
                        if developmentProgress < 1.0 {
                            Color.black
                                .opacity(1.0 - developmentProgress)
                        }
                    }
            } else {
                Color.black
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 32)
        .background(.white)
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 4)
    }
}

#Preview {
    HStack {
        PolaroidPhotoCell()
        PolaroidPhotoCell()
        PolaroidPhotoCell()
    }
    .padding()
}

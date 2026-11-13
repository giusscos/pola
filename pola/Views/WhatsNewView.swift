import SwiftUI

/// Release highlights shown once to people updating from an earlier version.
/// Bump `version` and `items` together for the next release that has something to show.
enum WhatsNew {
    static let version = "1.0.9"
    static let seenKey = "lastSeenWhatsNewVersion"

    struct Item: Identifiable {
        let id = UUID()
        let systemImage: String
        let color: Color
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        var isPremium = false
    }

    static let items: [Item] = [
        Item(systemImage: "camera.filters", color: Color(red: 0.95, green: 0.36, blue: 0.16),
             title: "4 new film stocks",
             detail: "GLÖD night film with a red glow, faded FÖRN, TINN tintype and PRIKK newsprint dots.",
             isPremium: true),
        Item(systemImage: "photo.badge.plus", color: Color(red: 0.35, green: 0.85, blue: 0.6),
             title: "Import from Photos",
             detail: "Give the photos you already have a film stock and a frame, and watch them develop."),
        Item(systemImage: "camera.aperture", color: Color(red: 1.0, green: 0.8, blue: 0.3),
             title: "A faster camera",
             detail: "Tap to focus, pinch to zoom, flash, and the volume buttons take the shot."),
        Item(systemImage: "heart.fill", color: Color(red: 1.0, green: 0.4, blue: 0.5),
             title: "A tidier library",
             detail: "Favorites, months, a filter for videos and time lapses, and Undo after deleting."),
        Item(systemImage: "square.and.arrow.up", color: Color(red: 0.55, green: 0.6, blue: 1.0),
             title: "Sharper shared prints",
             detail: "Prints you save or share are three times the resolution."),
    ]
}

struct WhatsNewView: View {
    var onDismiss: () -> Void

    private let accent = Color(red: 1.0, green: 0.8, blue: 0.3)

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.1).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What's New")
                            .scaledFont(40, weight: .bold, width: .expanded, relativeTo: .largeTitle)
                            .foregroundStyle(.white)
                        Text(verbatim: String(format: NSLocalizedString("Poly %@", comment: "Version label in What's New"), WhatsNew.version))
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.top, 40)

                    ForEach(WhatsNew.items) { item in
                        row(item)
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button(action: onDismiss) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: 520, minHeight: 54)
                        .background(accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ item: WhatsNew.Item) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: item.systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(item.color)
                .frame(width: 48, height: 48)
                .background(item.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if item.isPremium {
                        Text("PREMIUM")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent, in: Capsule())
                    }
                }
                Text(item.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WhatsNewView(onDismiss: {})
}

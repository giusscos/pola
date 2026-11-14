import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Binding var hasSeenOnboarding: Bool
    @Environment(PremiumManager.self) private var premium
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0
    @State private var appeared = false
    @State private var filterPreviews: [String: UIImage] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// VoiceOver moves to each page's title when the page changes.
    @AccessibilityFocusState private var focusedTitle: Int?

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                featurePage(
                    pageIndex: 1,
                    color: Color(red: 1.0, green: 0.78, blue: 0.2),
                    badge: String(format: NSLocalizedString("%d FILM STOCKS", comment: ""), allFilters.count),
                    title: "Shoot on\nreal film looks",
                    description: "From warm golden tones to infrared and VHS horror. Pick a stock, press the shutter and watch your print develop.",
                    visual: AnyView(filterVisual)
                ).tag(1)
                permissionPage(
                    color: Color(red: 0.2, green: 0.6, blue: 1.0),
                    systemIcon: "camera.fill",
                    title: "Camera\nAccess",
                    description: "Poly needs your camera to shoot photos, videos and time lapses that develop like instant film."
                ).tag(2)
                paywallPage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: page)

            if page < Self.paywallPage {
                navOverlay
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.6).delay(0.1)) { appeared = true }
            }
        }
        .task {
            await generateFilterPreviews()
        }
        .onChange(of: page) { _, newPage in
            if newPage == Self.paywallPage { Analytics.track(.onboardingCompleted) }
            if newPage < Self.paywallPage {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focusedTitle = newPage }
            }
        }
    }

    // MARK: - Navigation Overlay

    private var navOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.1)) { page = Self.paywallPage }
                } label: {
                    Text("Skip")
                        .scaledFont(15, weight: .medium, relativeTo: .subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 4)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .padding(.top, 8)
                .padding(.trailing, 24)
            }

            Spacer()

            VStack(spacing: 20) {
                pageIndicator

                Button {
                    handleContinue()
                } label: {
                    HStack(spacing: 6) {
                        // Wrapped explicitly: a ternary of literals would pick Text(String) and skip localization.
                        Text(LocalizedStringKey(page == 0 ? "Get Started" : "Continue"))
                            .scaledFont(17, weight: .semibold, relativeTo: .body)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 44)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.paywallPage, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Color.white : Color.white.opacity(0.3))
                    .frame(width: i == page ? 22 : 6, height: 6)
                    .animation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.25), value: page)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String(format: NSLocalizedString("Page %d of %d", comment: ""),
                                                  page + 1, Self.paywallPage)))
    }

    // MARK: - Welcome

    private var welcomePage: some View {
        ZStack {
            background(topColor: Color(red: 0.08, green: 0.06, blue: 0.14), bottomColor: Color(red: 0.06, green: 0.06, blue: 0.1))

            // Radial glow behind icon
            Circle()
                .fill(Color(red: 0.5, green: 0.3, blue: 0.9).opacity(0.18))
                .frame(width: 260, height: 260)
                .blur(radius: 70)
                .offset(y: -60)

            VStack(spacing: 0) {
                Spacer()

                // App icon
                ZStack {
                    RoundedRectangle(cornerRadius: 30)
                        .fill(.white.opacity(0.1))
                        .frame(width: 110, height: 110)
                        .overlay {
                            RoundedRectangle(cornerRadius: 30)
                                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                        }

                    if let icon = UIImage(named: "AppIcon") {
                        Image(uiImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 22))
                            .accessibilityHidden(true)
                    } else {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 48, weight: .thin))
                            .foregroundStyle(.white)
                    }
                }
                .scaleEffect(appeared ? 1 : 0.7)
                .opacity(appeared ? 1 : 0)
                .padding(.bottom, 36)

                VStack(spacing: 14) {
                    Text("Poly.")
                        .font(.system(size: 60, weight: .bold).width(.expanded))
                        .foregroundStyle(.white)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focusedTitle, equals: 0)
                        .offset(y: appeared ? 0 : 20)
                        .opacity(appeared ? 1 : 0)

                    Text("Authentic instant photos,\ndirect from your camera.")
                        .scaledFont(18, weight: .regular, relativeTo: .body)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .offset(y: appeared ? 0 : 16)
                        .opacity(appeared ? 1 : 0)
                        .animation(.easeOut(duration: 0.6).delay(0.15), value: appeared)
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Feature page

    private func featurePage(pageIndex: Int, color: Color, badge: String, title: String, description: String, visual: AnyView) -> some View {
        ZStack {
            background(topColor: Color(red: 0.07, green: 0.07, blue: 0.12), bottomColor: Color(red: 0.06, green: 0.06, blue: 0.1))

            // Colored glow
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(y: -100)

            VStack(spacing: 0) {
                Spacer()

                // Visual illustration
                visual
                    .padding(.bottom, 44)

                VStack(spacing: 14) {
                    // Premium badge
                    Text(verbatim: badge)
                        .font(.system(size: 11, weight: .bold).width(.expanded))
                        .foregroundStyle(color)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(color.opacity(0.15), in: Capsule())

                    // Title
                    Text(LocalizedStringKey(title))
                        .scaledFont(38, weight: .bold, relativeTo: .largeTitle)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focusedTitle, equals: pageIndex)
                        .lineSpacing(2)

                    // Description
                    Text(LocalizedStringKey(description))
                        .scaledFont(16, relativeTo: .subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 36)
                }

                Spacer()
                Spacer()
            }
        }
    }

    // MARK: - Paywall page

    // Onboarding is kept short (welcome, film, camera) so people reach the camera quickly;
    // microphone and location are requested later, when they are first needed.
    private static let paywallPage = 3

    private var paywallPage: some View {
        PaywallView(context: .onboarding, onClose: { dismiss() })
    }

    // MARK: - Feature Visuals

    /// Every film stock and lens on the reference photo, in two rows drifting in opposite directions.
    private var filterVisual: some View {
        VStack(spacing: -14) {
            FilmMarqueeRow(tiles: marqueeTiles(filmFilters + instantFilters), reversed: false)
            FilmMarqueeRow(tiles: marqueeTiles(weirdFilters) + lensTiles, reversed: true)
        }
        .accessibilityHidden(true)
    }

    private func marqueeTiles(_ filters: [FilmFilter]) -> [FilmMarqueeRow.Tile] {
        filters.map { FilmMarqueeRow.Tile(name: $0.name, color: $0.color, imageName: $0.imageName,
                                          preview: filterPreviews[$0.name]) }
    }

    private var lensTiles: [FilmMarqueeRow.Tile] {
        Lens.allCases.map { FilmMarqueeRow.Tile(name: $0.name, color: $0.color, imageName: nil,
                                                preview: filterPreviews[Self.lensPreviewKey($0)]) }
    }

    /// Lens previews share the dictionary with the stocks, so their keys can't clash with a stock name.
    private static func lensPreviewKey(_ lens: Lens) -> String { "lens:\(lens.name)" }

    // MARK: - Helpers

    private func generateFilterPreviews() async {
        guard let ref = UIImage(named: "filter_reference") else { return }
        let size = CGSize(width: 120, height: 120)
        let small = ref.preparingThumbnail(of: size) ?? ref
        var previews = await renderFilmStockPreviews(from: small)
        for (name, image) in await FilmStockPreviews.renderLenses(film: nil, from: small) {
            if let lens = Lens(rawValue: name) { previews[Self.lensPreviewKey(lens)] = image }
        }
        filterPreviews = previews
    }

    private func background(topColor: Color, bottomColor: Color) -> some View {
        LinearGradient(colors: [topColor, bottomColor], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    // MARK: - Permission page

    private func permissionPage(color: Color, systemIcon: String, title: String, description: String) -> some View {
        ZStack {
            background(topColor: Color(red: 0.07, green: 0.07, blue: 0.12), bottomColor: Color(red: 0.06, green: 0.06, blue: 0.1))

            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(y: -100)

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 130, height: 130)
                    Circle()
                        .strokeBorder(color.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 130, height: 130)
                    Image(systemName: systemIcon)
                        .font(.system(size: 52, weight: .thin))
                        .foregroundStyle(color)
                }
                .padding(.bottom, 44)

                VStack(spacing: 14) {
                    Text(LocalizedStringKey(title))
                        .scaledFont(38, weight: .bold, relativeTo: .largeTitle)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focusedTitle, equals: 2)
                        .lineSpacing(2)

                    Text(LocalizedStringKey(description))
                        .scaledFont(16, relativeTo: .subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 36)
                }

                Spacer()
                Spacer()
            }
        }
    }

    // MARK: - Permission handling

    private func handleContinue() {
        if page == 2 {
            Task {
                await AVCaptureDevice.requestAccess(for: .video)
                await MainActor.run { withAnimation(.spring(duration: 0.4, bounce: 0.1)) { page = Self.paywallPage } }
            }
        } else {
            withAnimation(.spring(duration: 0.4, bounce: 0.1)) { page = min(page + 1, Self.paywallPage) }
        }
    }
}

#Preview {
    OnboardingView(hasSeenOnboarding: .constant(false))
        .environment(PremiumManager.shared)
}

/// An endless row of film tiles. Stills under Reduce Motion.
private struct FilmMarqueeRow: View {
    struct Tile {
        let name: String
        let color: Color
        let imageName: String?
        let preview: UIImage?
    }

    let tiles: [Tile]
    /// The bottom row drifts the other way.
    let reversed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let tileSize: CGFloat = 58
    private let spacing: CGFloat = 12
    private let speed: Double = 18

    var body: some View {
        let cycle = (tileSize + spacing) * CGFloat(tiles.count)
        // The row takes only the space it's given: the tiles live in an overlay, so their full
        // width never reaches the page's layout, and anything past the edges is clipped and faded.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: rowHeight)
            .overlay(alignment: .leading) {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let phase = CGFloat((context.date.timeIntervalSinceReferenceDate * speed)
                        .truncatingRemainder(dividingBy: Double(max(cycle, 1))))
                    HStack(spacing: spacing) {
                        // Three copies cover any screen width while one wraps around.
                        ForEach(0..<(tiles.count * 3), id: \.self) { index in
                            tile(tiles[index % tiles.count])
                        }
                    }
                    .fixedSize()
                    .offset(x: reversed ? phase - cycle : -phase)
                }
            }
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.15),
                                       .init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
    }

    /// Tall enough for the tile, its label and the coloured glow, so the clip never cuts the glow.
    private var rowHeight: CGFloat { tileSize + 48 }

    private func tile(_ tile: Tile) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if let preview = tile.preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                } else if let imageName = tile.imageName {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                } else {
                    tile.color.opacity(0.2)
                }
            }
            .frame(width: tileSize, height: tileSize)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: tile.color.opacity(0.4), radius: 8)

            Text(verbatim: tile.name)
                .font(.system(size: 8, weight: .bold).width(.expanded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
                .frame(width: tileSize + spacing)
        }
        .frame(width: tileSize)
    }
}

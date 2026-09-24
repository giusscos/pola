import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Binding var hasSeenOnboarding: Bool
    @Environment(PremiumManager.self) private var premium
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0
    @State private var appeared = false
    @State private var filterPreviews: [String: UIImage] = [:]

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                featurePage(
                    pageIndex: 1,
                    color: Color(red: 1.0, green: 0.78, blue: 0.2),
                    badge: "10 FILM STOCKS",
                    title: "Shoot on\nreal film looks",
                    description: "From warm golden tones to infrared and VHS horror. Pick a stock, press the shutter and watch your polaroid develop.",
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
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) { appeared = true }
        }
        .task {
            await generateFilterPreviews()
        }
        .onChange(of: page) { _, newPage in
            if newPage == Self.paywallPage { Analytics.track(.onboardingCompleted) }
        }
    }

    // MARK: - Navigation Overlay

    private var navOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.1)) { page = Self.paywallPage }
                } label: {
                    Text("Skip")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
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
                            .font(.system(size: 17, weight: .semibold))
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
                    .animation(.spring(duration: 0.35, bounce: 0.25), value: page)
            }
        }
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
                        .offset(y: appeared ? 0 : 20)
                        .opacity(appeared ? 1 : 0)

                    Text("Authentic polaroids,\ndirect from your camera.")
                        .font(.system(size: 18, weight: .regular))
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
                    Text(LocalizedStringKey(badge))
                        .font(.system(size: 11, weight: .bold).width(.expanded))
                        .foregroundStyle(color)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(color.opacity(0.15), in: Capsule())

                    // Title
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)

                    // Description
                    Text(LocalizedStringKey(description))
                        .font(.system(size: 16))
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

    private var filterVisual: some View {
        let arcOffsets: [CGFloat] = [-18, -6, 4, -6, -18]

        return VStack(spacing: 16) {
            // Film filter row — shows reference photo with each effect applied
            HStack(spacing: 10) {
                ForEach(Array(filmFilters.enumerated()), id: \.offset) { i, filter in
                    VStack(spacing: 6) {
                        ZStack {
                            if let preview = filterPreviews[filter.name] {
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
                                    .fill(filter.color.opacity(0.15))
                                Circle()
                                    .fill(filter.color)
                                    .frame(width: 26, height: 26)
                            }
                        }
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: filter.color.opacity(0.45), radius: 10)
                        .offset(y: arcOffsets[i])

                        Text(filter.name)
                            .font(.system(size: 8, weight: .bold).width(.expanded))
                            .foregroundStyle(.white.opacity(0.6))
                            .offset(y: arcOffsets[i])
                    }
                }
            }

            // Weird Film row
            HStack(spacing: 10) {
                // Five fixed-size tiles is all that fits on the smallest iPhones.
                ForEach(weirdFilters.prefix(5)) { filter in
                    ZStack {
                        if let preview = filterPreviews[filter.name] {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(filter.color.opacity(0.15))
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: filter.color.opacity(0.4), radius: 8)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Helpers

    private func generateFilterPreviews() async {
        guard let ref = UIImage(named: "filter_reference") else { return }
        let size = CGSize(width: 120, height: 120)
        let small = ref.preparingThumbnail(of: size) ?? ref
        var previews: [String: UIImage] = [:]
        for filter in allFilters {
            guard let effect = filter.effect else { continue }
            previews[filter.name] = effect.apply(to: small)
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
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)

                    Text(LocalizedStringKey(description))
                        .font(.system(size: 16))
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

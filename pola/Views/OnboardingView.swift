import SwiftUI
import AVFoundation
import CoreLocation

private final class LocationAuthorizationHelper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func request() async {
        guard manager.authorizationStatus == .notDetermined else { return }
        await withCheckedContinuation { c in
            continuation = c
            manager.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        continuation?.resume()
        continuation = nil
    }
}

struct OnboardingView: View {
    @Binding var hasSeenOnboarding: Bool
    @Environment(PremiumManager.self) private var premium
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0
    @State private var appeared = false
    @State private var locationHelper = LocationAuthorizationHelper()
    @State private var filterPreviews: [String: UIImage] = [:]

    var body: some View {
        ZStack(alignment: .top) {
            TabView(selection: $page) {
                welcomePage.tag(0)
                featurePage(
                    pageIndex: 1,
                    color: Color(red: 1.0, green: 0.78, blue: 0.2),
                    badge: "PREMIUM",
                    title: "Film Filters\n& Packs",
                    description: "Choose from 5 authentic film emulations and colorful Polaroid frames that make every shot uniquely yours.",
                    visual: AnyView(filterVisual)
                ).tag(1)
                featurePage(
                    pageIndex: 2,
                    color: Color(red: 0.7, green: 0.4, blue: 1.0),
                    badge: "PREMIUM",
                    title: "Your Caption\nStyle",
                    description: "Personalize every polaroid with 6 fonts and 4 weight options — a signature that's uniquely yours.",
                    visual: AnyView(fontVisual)
                ).tag(2)
                featurePage(
                    pageIndex: 3,
                    color: Color(red: 0.2, green: 0.85, blue: 0.6),
                    badge: "PREMIUM",
                    title: "Watermark-\nFree",
                    description: "Share and save your memories without any branding. Pure, clean polaroids every time.",
                    visual: AnyView(watermarkVisual)
                ).tag(3)
                permissionPage(
                    color: Color(red: 0.2, green: 0.6, blue: 1.0),
                    systemIcon: "camera.fill",
                    title: "Camera\nAccess",
                    description: "Pola needs access to your camera to capture authentic polaroid-style photos and videos."
                ).tag(4)
                permissionPage(
                    color: Color(red: 1.0, green: 0.55, blue: 0.2),
                    systemIcon: "mic.fill",
                    title: "Microphone\nAccess",
                    description: "Allow microphone access so Pola can record audio when capturing videos and time-lapses."
                ).tag(5)
                permissionPage(
                    color: Color(red: 0.2, green: 0.85, blue: 0.55),
                    systemIcon: "location.fill",
                    title: "Location\nAccess",
                    description: "Optionally tag your memories with a location to remember exactly where each shot was taken."
                ).tag(6)
                paywallPage.tag(7)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.35), value: page)

            if page < 7 {
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
        .onChange(of: premium.isPremium) { _, newValue in
            if newValue { dismiss() }
        }
    }

    // MARK: - Navigation Overlay

    private var navOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(duration: 0.4, bounce: 0.1)) { page = 7 }
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
                        Text(page == 0 ? "Get Started" : (4...6).contains(page) ? "Allow Access" : "Continue")
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
            ForEach(0..<7, id: \.self) { i in
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

    private var paywallPage: some View {
        PaywallView {
            dismiss()
        }
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

            // Instant pack row
            HStack(spacing: 10) {
                ForEach(polaPackColors) { pack in
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(pack.color.opacity(0.15))
                        Circle()
                            .fill(pack.color)
                            .frame(width: 22, height: 22)
                            .shadow(color: pack.color.opacity(0.5), radius: 4, x: 0, y: 2)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: pack.color.opacity(0.4), radius: 8)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var fontVisual: some View {
        let samples: [(text: String, rotation: Double, yOffset: CGFloat, xOffset: CGFloat, opacity: Double)] = [
            ("Summer Vibes", -5, -32, -10, 0.9),
            ("golden hour",   2,   0,  12, 1.0),
            ("NYC / 2026",   -3,  30,  -6, 0.85),
        ]

        return ZStack {
            ForEach(Array(samples.enumerated()), id: \.offset) { i, s in
                ZStack {
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 210, height: 42)
                        .shadow(color: .black.opacity(0.35), radius: 10, y: 5)

                    Text(s.text)
                        .font(fontForSample(i))
                        .foregroundStyle(.black.opacity(0.65))
                }
                .rotationEffect(.degrees(s.rotation))
                .offset(x: s.xOffset, y: s.yOffset)
                .opacity(s.opacity)
            }
        }
        .frame(height: 140)
    }

    private func fontForSample(_ index: Int) -> Font {
        switch index {
        case 0:  return .custom("Bradley Hand", size: 20)
        case 1:  return .system(size: 17, weight: .semibold, design: .serif)
        default: return .system(size: 16, weight: .bold).width(.expanded)
        }
    }

    private var watermarkVisual: some View {
        ZStack {
            // Polaroid card
            VStack(spacing: 0) {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.25, green: 0.55, blue: 0.75), Color(red: 0.15, green: 0.35, blue: 0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
                .frame(width: 160, height: 140)
                .padding(.horizontal, 8)
                .padding(.top, 8)

                ZStack {
                    Color.white
                    Text("clean export")
                        .font(.custom("Bradley Hand", size: 14))
                        .foregroundStyle(.black.opacity(0.55))
                }
                .frame(width: 176, height: 38)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
            .rotationEffect(.degrees(-4))

            // Crossed-out watermark pill (showing "Pola" text with strikethrough)
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 64, height: 28)
                Text("Poly")
                    .font(.system(size: 11, weight: .semibold))
                    .kerning(1.5)
                    .foregroundStyle(.white.opacity(0.7))
                    .strikethrough(true, color: .red)
            }
            .offset(x: -46, y: -50)

            // Clean badge
            ZStack {
                Circle()
                    .fill(Color(red: 0.2, green: 0.85, blue: 0.6))
                    .frame(width: 44, height: 44)
                    .shadow(color: Color(red: 0.2, green: 0.85, blue: 0.6).opacity(0.5), radius: 12)
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black)
            }
            .offset(x: 72, y: -62)
        }
    }

    // MARK: - Helpers

    private func generateFilterPreviews() async {
        guard let ref = UIImage(named: "filter_reference") else { return }
        let size = CGSize(width: 120, height: 120)
        let small = ref.preparingThumbnail(of: size) ?? ref
        var previews: [String: UIImage] = [:]
        for filter in filmFilters {
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
        switch page {
        case 4:
            Task {
                await AVCaptureDevice.requestAccess(for: .video)
                await MainActor.run { withAnimation(.spring(duration: 0.4, bounce: 0.1)) { page = 5 } }
            }
        case 5:
            Task {
                await AVCaptureDevice.requestAccess(for: .audio)
                await MainActor.run { withAnimation(.spring(duration: 0.4, bounce: 0.1)) { page = 6 } }
            }
        case 6:
            Task {
                await locationHelper.request()
                await MainActor.run { withAnimation(.spring(duration: 0.4, bounce: 0.1)) { page = 7 } }
            }
        default:
            withAnimation(.spring(duration: 0.4, bounce: 0.1)) { page = min(page + 1, 7) }
        }
    }
}

#Preview {
    OnboardingView(hasSeenOnboarding: .constant(false))
        .environment(PremiumManager.shared)
}

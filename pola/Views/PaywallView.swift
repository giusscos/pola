import StoreKit
import SwiftUI

// MARK: - Premium catalogue

enum PremiumFeature: CaseIterable {
    case filmStocks
    case frameColors
    case captionStyle
    case dateStamp
    case printSheets
    case cleanExports

    var icon: String {
        switch self {
        case .filmStocks:   "camera.filters"
        case .frameColors:  "paintpalette.fill"
        case .captionStyle: "textformat"
        case .dateStamp:    "calendar.badge.clock"
        case .printSheets:  "printer.fill"
        case .cleanExports: "checkmark.shield.fill"
        }
    }

    var color: Color {
        switch self {
        case .filmStocks:   Color(red: 1.0, green: 0.78, blue: 0.2)
        case .frameColors:  Color(red: 1.0, green: 0.45, blue: 0.55)
        case .captionStyle: Color(red: 0.7, green: 0.4, blue: 1.0)
        case .dateStamp:    Color(red: 1.0, green: 0.55, blue: 0.15)
        case .printSheets:  Color(red: 0.3, green: 0.65, blue: 1.0)
        case .cleanExports: Color(red: 0.2, green: 0.85, blue: 0.6)
        }
    }

    var title: String {
        switch self {
        case .filmStocks:   "10 Film Stocks"
        case .frameColors:  "Colored Frames"
        case .captionStyle: "Caption Style"
        case .dateStamp:    "Date Stamp"
        case .printSheets:  "Print Sheets"
        case .cleanExports: "Clean Exports"
        }
    }

    var subtitle: String {
        switch self {
        case .filmStocks:   "Classic and Weird Film packs"
        case .frameColors:  "Any border color, on any polaroid"
        case .captionStyle: "6 fonts × 4 weights"
        case .dateStamp:    "Retro date imprint on your shots"
        case .printSheets:  "A4 layouts ready to print at home"
        case .cleanExports: "No logo on shares and saves"
        }
    }

    /// Paywall subtitle when the paywall was opened by tapping this feature.
    var pitch: String {
        switch self {
        case .filmStocks:   "Every film stock, every look."
        case .frameColors:  "Give every polaroid its own color."
        case .captionStyle: "Make every caption yours."
        case .dateStamp:    "Stamp the date like a real film camera."
        case .printSheets:  "Print your polaroids at home."
        case .cleanExports: "Share your polaroids without the logo."
        }
    }
}

enum PaywallContext: Equatable, Identifiable {
    case general
    case onboarding
    case milestone
    case filter(String)
    case feature(PremiumFeature)

    var highlighted: PremiumFeature? {
        switch self {
        case .filter: .filmStocks
        case .feature(let f): f
        default: nil
        }
    }

    var id: String { analyticsName }

    var analyticsName: String {
        switch self {
        case .general: "general"
        case .onboarding: "onboarding"
        case .milestone: "milestone"
        case .filter(let name): "filter:\(name)"
        case .feature(let f): "feature:\(f)"
        }
    }
}

// MARK: - Paywall

struct PaywallView: View {
    @Environment(PremiumManager.self) private var premium
    var context: PaywallContext = .general
    /// The user's own photo, used to preview a locked filter on something they shot.
    var previewImage: UIImage? = nil
    var onClose: (() -> Void)? = nil

    @State private var selectedProductID = PremiumManager.yearlyID
    @State private var didUnlock = false
    @State private var filterPreview: UIImage? = nil

    private let accent = Color(red: 1.0, green: 0.8, blue: 0.3)

    private var orderedFeatures: [PremiumFeature] {
        guard let first = context.highlighted else { return PremiumFeature.allCases }
        return [first] + PremiumFeature.allCases.filter { $0 != first }
    }

    private var contextFilter: FilmFilter? {
        if case .filter(let name) = context { return filmFilter(named: name) }
        return nil
    }

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.1).ignoresSafeArea()

            if didUnlock {
                PremiumWelcomeView {
                    onClose?()
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                paywallContent
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if premium.isPremium {
                onClose?()
                return
            }
            Analytics.track(.paywallShown, ["context": context.analyticsName])
        }
        .onDisappear {
            if !didUnlock && !premium.isPremium {
                Analytics.track(.paywallDismissed, ["context": context.analyticsName])
            }
        }
        .onChange(of: premium.isPremium) { _, newValue in
            guard newValue else { return }
            withAnimation(.spring(duration: 0.5, bounce: 0.2)) { didUnlock = true }
        }
        .task { renderFilterPreview() }
    }

    private var paywallContent: some View {
        ZStack {
            Circle()
                .fill((contextFilter?.color ?? accent).opacity(0.14))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(y: -200)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if contextFilter != nil {
                        filterHeader
                    } else {
                        header
                    }
                    featureList
                    pricingSection
                    footerButtons
                }
            }
            // Pinned so the purchase button is always visible without scrolling.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ctaButton
                    .padding(.top, 20)
                    .padding(.bottom, 8)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.06, green: 0.06, blue: 0.1).opacity(0), Color(red: 0.06, green: 0.06, blue: 0.1)],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        }
    }

    // MARK: - Header

    private var headerTitle: String {
        context == .milestone ? "You're on a roll" : "poly Premium"
    }

    private var headerSubtitle: String {
        switch context {
        case .milestone: "Take your polaroids further with every film stock, frame and font."
        case .feature(let f): f.pitch
        default: "Unlock the full experience"
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: context == .milestone ? "sparkles" : "crown.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.9, blue: 0.4), Color(red: 1.0, green: 0.6, blue: 0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, 36)
            .padding(.bottom, 4)

            Text(LocalizedStringKey(headerTitle))
                .font(.system(size: 30, weight: .bold).width(.expanded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(LocalizedStringKey(headerSubtitle))
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.bottom, 22)
    }

    private var filterHeader: some View {
        VStack(spacing: 14) {
            if let filter = contextFilter {
                VStack(spacing: 0) {
                    ZStack {
                        filter.color.opacity(0.2)
                        if let filterPreview {
                            Image(uiImage: filterPreview)
                                .resizable()
                                .scaledToFill()
                                .transition(.opacity)
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                    .frame(width: 168, height: 168 * 4 / 3)
                    .clipped()
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                    Text(filter.name)
                        .font(.custom("Bradley Hand", size: 18))
                        .foregroundStyle(.black.opacity(0.65))
                        .frame(height: 40)
                }
                .background(.white)
                .shadow(color: filter.color.opacity(0.45), radius: 24, y: 8)
                .rotationEffect(.degrees(-3))
                .padding(.top, 44)
                .padding(.bottom, 10)
                .animation(.easeOut(duration: 0.3), value: filterPreview != nil)

                Text(String(format: NSLocalizedString("Shoot with %@", comment: ""), filter.name))
                    .font(.system(size: 28, weight: .bold).width(.expanded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(verbatim: previewImage == nil
                     ? NSLocalizedString("Unlock all 10 film stocks and keep every look.", comment: "")
                     : String(format: NSLocalizedString("This is your last photo on %@. Unlock all 10 film stocks and keep every look.", comment: ""), filter.name))
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .padding(.bottom, 24)
    }

    private func renderFilterPreview() {
        guard let effect = contextFilter?.effect,
              let base = previewImage ?? UIImage(named: "filter_reference") else { return }
        let small = base.preparingThumbnail(of: CGSize(width: 600, height: 800)) ?? base
        filterPreview = effect.apply(to: small)
    }

    // MARK: - Features

    // Two-column grid keeps all six features and the plans above the fold on most phones.
    private var featureList: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(orderedFeatures, id: \.self) { f in
                let isHighlighted = f == context.highlighted
                VStack(alignment: .leading, spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(f.color.opacity(0.15))
                            .frame(width: 34, height: 34)
                        Image(systemName: f.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(f.color)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(f.title))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(LocalizedStringKey(f.subtitle))
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2, reservesSpace: true)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.white.opacity(isHighlighted ? 0.09 : 0.05), in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(f.color.opacity(0.6), lineWidth: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
    }

    // MARK: - Pricing

    @ViewBuilder
    private var pricingSection: some View {
        if premium.products.isEmpty {
            placeholderPricing
        } else {
            VStack(spacing: 10) {
                ForEach(premium.products) { product in
                    productCard(product)
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private func productCard(_ product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        let isYearly   = product.id == PremiumManager.yearlyID

        return Button {
            withAnimation(.spring(duration: 0.2, bounce: 0.1)) {
                selectedProductID = product.id
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(product.displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        if isYearly {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .bold).width(.expanded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(accent, in: Capsule())
                        }
                    }
                    Text(product.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? accent : .white.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(accent)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? .white.opacity(0.1) : .white.opacity(0.04))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(accent.opacity(0.45), lineWidth: 1)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selectedProductID)
    }

    private var placeholderPricing: some View {
        VStack(spacing: 10) {
            ForEach(["Monthly", "Yearly", "Lifetime"], id: \.self) { name in
                HStack {
                    Text(LocalizedStringKey(name))
                        .font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text("–")
                }
                .padding(14)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .redacted(reason: .placeholder)
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button {
            let product = premium.products.first(where: { $0.id == selectedProductID })
                       ?? premium.products.first
            guard let product else { return }
            Task { await premium.purchase(product) }
        } label: {
            ZStack {
                if premium.isPurchasing {
                    ProgressView().tint(.black)
                } else {
                    Text("Unlock Premium")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                LinearGradient(
                    colors: [Color(red: 1.0, green: 0.88, blue: 0.35), Color(red: 1.0, green: 0.58, blue: 0.18)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .disabled(premium.isPurchasing || premium.products.isEmpty)
        .padding(.horizontal, 24)
    }

    // MARK: - Footer

    private var footerButtons: some View {
        VStack(spacing: 12) {
            if let error = premium.purchaseError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button {
                Task { await premium.restorePurchases() }
            } label: {
                Text("Restore Purchases")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
            }

            if let onClose {
                Button(action: onClose) {
                    Text("Continue for Free")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.3))
                        .underline()
                }
            }

            Text("Subscriptions auto-renew unless cancelled. Manage in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.2))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            HStack(spacing: 16) {
                if let privacy = URL(string: "https://poly-vintage.com/privacy") {
                    Link("Privacy Policy", destination: privacy)
                }
                Text("·")
                if let terms = URL(string: "https://poly-vintage.com/terms") {
                    Link("Terms of Use", destination: terms)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
    }
}

// MARK: - Welcome to Premium

private struct PremiumWelcomeView: View {
    let onContinue: () -> Void

    @State private var appeared = false
    @State private var burst = false

    private let gold = Color(red: 1.0, green: 0.8, blue: 0.3)
    private let confettiColors: [Color] = [
        Color(red: 1.0, green: 0.8, blue: 0.3),
        Color(red: 0.96, green: 0.72, blue: 0.54),
        Color(red: 0.68, green: 0.27, blue: 0.82),
        Color(red: 0.2, green: 0.85, blue: 0.6),
        Color(red: 1.0, green: 0.45, blue: 0.55),
        .white,
    ]

    var body: some View {
        ZStack {
            Circle()
                .fill(gold.opacity(0.18))
                .frame(width: 360, height: 360)
                .blur(radius: 90)
                .offset(y: -120)

            confetti

            VStack(spacing: 0) {
                Spacer()

                // A golden polaroid "prints" in, echoing the camera's print animation
                VStack(spacing: 0) {
                    ZStack {
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.9, blue: 0.45), Color(red: 1.0, green: 0.6, blue: 0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: "crown.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(.white.opacity(0.95))
                            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    }
                    .frame(width: 150, height: 150)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                    Text("premium")
                        .font(.custom("Bradley Hand", size: 18))
                        .foregroundStyle(.black.opacity(0.6))
                        .frame(height: 40)
                }
                .background(.white)
                .shadow(color: gold.opacity(0.5), radius: 30, y: 10)
                .rotationEffect(.degrees(appeared ? -4 : 8))
                .offset(y: appeared ? 0 : -60)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)
                .padding(.bottom, 40)

                Text("Welcome to Premium")
                    .font(.system(size: 30, weight: .bold).width(.expanded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)

                Text("Every film stock, frame and font is now yours. Thank you for supporting poly.")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 12)
                    .opacity(appeared ? 1 : 0)

                Spacer()

                Button(action: onContinue) {
                    Text("Start Shooting")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [Color(red: 1.0, green: 0.88, blue: 0.35), Color(red: 1.0, green: 0.58, blue: 0.18)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 44)
                .opacity(appeared ? 1 : 0)
            }
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(.spring(duration: 0.8, bounce: 0.35)) { appeared = true }
            withAnimation(.easeOut(duration: 1.6)) { burst = true }
        }
    }

    private var confetti: some View {
        ZStack {
            ForEach(0..<28, id: \.self) { i in
                let angle = Double(i) / 28.0 * 2 * .pi
                let distance: CGFloat = 150 + CGFloat((i * 37) % 90)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(confettiColors[i % confettiColors.count])
                    .frame(width: 6, height: 11)
                    .rotationEffect(.degrees(burst ? Double(i * 47) : 0))
                    .offset(
                        x: burst ? cos(angle) * distance : 0,
                        y: burst ? sin(angle) * distance + 80 : 0
                    )
                    .opacity(burst ? 0 : 1)
            }
        }
        .offset(y: -120)
        .allowsHitTesting(false)
    }
}

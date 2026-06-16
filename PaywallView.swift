import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(PremiumManager.self) private var premium
    var onClose: (() -> Void)? = nil

    @State private var selectedProductID = PremiumManager.yearlyID

    private let features: [(icon: String, color: Color, title: String, subtitle: String)] = [
        ("camera.filters",      Color(red: 1.0, green: 0.78, blue: 0.2),  "Film Filters & Packs",  "5 film emulations + colored frames"),
        ("textformat",          Color(red: 0.7, green: 0.4,  blue: 1.0),  "Caption Style",         "6 fonts × 4 weights"),
        ("checkmark.shield.fill", Color(red: 0.2, green: 0.85, blue: 0.6), "Watermark-Free",       "Pure, clean exports"),
    ]

    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.1).ignoresSafeArea()

            Circle()
                .fill(Color(red: 1.0, green: 0.8, blue: 0.3).opacity(0.12))
                .frame(width: 320, height: 320)
                .blur(radius: 80)
                .offset(y: -200)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    featureList
                    pricingSection
                    ctaButton
                    footerButtons
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if premium.isPremium { onClose?() }
        }
        .onChange(of: premium.isPremium) { _, newValue in
            if newValue { onClose?() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 1.0, green: 0.8, blue: 0.3).opacity(0.15))
                    .frame(width: 80, height: 80)
                Image(systemName: "crown.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 1.0, green: 0.9, blue: 0.4), Color(red: 1.0, green: 0.6, blue: 0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .padding(.top, 52)
            .padding(.bottom, 4)

            Text("pola. Premium")
                .font(.system(size: 30, weight: .bold).width(.expanded))
                .foregroundStyle(.white)

            Text("Unlock the full experience")
                .font(.system(size: 16))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.bottom, 32)
    }

    // MARK: - Features

    private var featureList: some View {
        VStack(spacing: 10) {
            ForEach(features, id: \.title) { f in
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(f.color.opacity(0.15))
                            .frame(width: 46, height: 46)
                        Image(systemName: f.icon)
                            .font(.system(size: 19))
                            .foregroundStyle(f.color)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(f.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.45))
                    }

                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(f.color.opacity(0.6))
                }
                .padding(14)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
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
        let isLifetime = product.id == PremiumManager.lifetimeID
        let accentColor = Color(red: 1.0, green: 0.8, blue: 0.3)

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
                                .background(accentColor, in: Capsule())
                        }
                    }
                    Text(isLifetime ? "One-time purchase" : periodLabel(product))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                }

                Spacer()

                Text(product.displayPrice)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)

                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? accentColor : .white.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(accentColor)
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
                                .strokeBorder(accentColor.opacity(0.45), lineWidth: 1)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
    }

    private func periodLabel(_ product: Product) -> String {
        switch product.subscription?.subscriptionPeriod.unit {
        case .month: return "per month"
        case .year:  return "per year"
        case .week:  return "per week"
        case .day:   return "per day"
        default:     return ""
        }
    }

    private var placeholderPricing: some View {
        VStack(spacing: 10) {
            ForEach(["Monthly", "Yearly", "Lifetime"], id: \.self) { name in
                HStack {
                    Text(name)
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
        .padding(.top, 24)
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
        }
        .padding(.top, 16)
        .padding(.bottom, 52)
    }
}

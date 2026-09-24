import StoreKit
import SwiftUI

struct SettingsView: View {
    @Environment(PremiumManager.self) private var premium
    @Environment(LanguageManager.self) private var languageManager
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @State private var paywallContext: PaywallContext? = nil
    @State private var showManageSubscription = false
    @State private var showOnboarding = false
    @State private var pendingLanguage: String? = nil
    @State private var showLanguageAlert = false

    @AppStorage("defaultFilter") private var defaultFilter: String = "None"
    @AppStorage("captionPromptEnabled") private var captionPromptEnabled: Bool = true
    @AppStorage("polaroidFont") private var polaroidFontRaw: String = PolaroidFont.handwriting.rawValue
    @AppStorage("polaroidFontWeight") private var polaroidFontWeightRaw: String = PolaroidFontWeight.regular.rawValue
    @AppStorage("libraryColumnCount") private var libraryColumnCount: Int = 3
    @AppStorage("videoAudioEnabled") private var videoAudioEnabled: Bool = true
    @AppStorage("frontCameraMirrored") private var frontCameraMirrored: Bool = true
    @AppStorage("printAnimationEnabled") private var printAnimationEnabled: Bool = true
    @AppStorage("timelapseInterval") private var timelapseInterval: Double = 5
    @AppStorage("timelapseDuration") private var timelapseDuration: Double = 60
    @AppStorage("timelapseSaveAsVideo") private var timelapseSaveAsVideo: Bool = false
    @AppStorage("dateStampEnabled") private var dateStampEnabled = false

    private var totalTimelapsePhotos: Int { max(1, Int(timelapseDuration / timelapseInterval)) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if premium.isPremium {
                        HStack(spacing: 12) {
                            Image(systemName: "crown.fill")
                                .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.3))
                                .font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Premium Active")
                                    .font(.headline)
                                Text(verbatim: planDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title3)
                        }

                        Toggle(isOn: Binding(
                            get: { premium.showLogoOnExports },
                            set: { premium.showLogoOnExports = $0 }
                        )) {
                            Label("Show app logo on exports", systemImage: "photo")
                        }

                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Memories widget")
                                Text("Touch and hold your Home Screen, tap Edit, then Add Widget and search for Poly.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "apps.iphone")
                        }

                        if premium.isSubscriber {
                            Button { showManageSubscription = true } label: {
                                Label("Manage Subscription", systemImage: "creditcard")
                                    .foregroundStyle(.primary)
                            }
                            if let lifetime = premium.lifetimeProduct {
                                Button {
                                    Task { await premium.purchase(lifetime) }
                                } label: {
                                    HStack {
                                        Label("Upgrade to Lifetime", systemImage: "infinity")
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if premium.isPurchasing {
                                            ProgressView()
                                        } else {
                                            Text(lifetime.displayPrice)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .disabled(premium.isPurchasing)
                            }
                        }
                    } else {
                        Button { presentPaywall(.general) } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(red: 1.0, green: 0.8, blue: 0.3).opacity(0.15))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "crown.fill")
                                        .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.3))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Unlock poly Premium")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Filters, fonts & clean exports")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        lockedRow("Memories widget", systemImage: "apps.iphone", feature: .widget)
                    }
                } header: {
                    Text("Premium")
                } footer: {
                    if premium.isSubscriber && premium.lifetimeProduct != nil {
                        Text("After upgrading to Lifetime, cancel your subscription in Manage Subscription so you aren't charged again.")
                    }
                }

                Section {
                    Picker(selection: $defaultFilter) {
                        Text("None").tag("None")
                        ForEach(allFilters.filter { !$0.isLocked(for: premium) }) { filter in
                            Text(filter.name).tag(filter.name)
                        }
                    } label: {
                        Label("Default Filter", systemImage: "camera.filters")
                    }
                    Toggle(isOn: $frontCameraMirrored) {
                        Label("Mirror front camera", systemImage: "person.fill.viewfinder")
                    }
                } header: {
                    Text("Camera")
                } footer: {
                    Text("When enabled, the selfie camera preview and captures appear like a mirror.")
                }

                Section("Video") {
                    Toggle(isOn: $videoAudioEnabled) {
                        Label("Record audio", systemImage: videoAudioEnabled ? "mic.fill" : "mic.slash.fill")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: String(format: NSLocalizedString("Interval: %d s between shots", comment: ""), Int(timelapseInterval)))
                            .font(.subheadline)
                        Slider(value: $timelapseInterval, in: 1...60, step: 1)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: String(format: NSLocalizedString("Duration: %@", comment: ""), formatDuration(timelapseDuration)))
                            .font(.subheadline)
                        Slider(value: $timelapseDuration, in: 10...3600, step: 10)
                    }
                    .padding(.vertical, 4)

                    Toggle(isOn: $timelapseSaveAsVideo) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save as video polaroid")
                            Text(verbatim: timelapseSaveAsVideo
                                 ? NSLocalizedString("All frames combined into one video", comment: "")
                                 : String(format: NSLocalizedString("%d separate photo polaroids", comment: ""), totalTimelapsePhotos))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Time Lapse")
                } footer: {
                    Text(verbatim: String(format: NSLocalizedString("Total frames: %d", comment: ""), totalTimelapsePhotos))
                }

                Section("Library") {
                    Picker(selection: $libraryColumnCount) {
                        Label("1 Column", systemImage: "rectangle.grid.1x2").tag(1)
                        Label("2 Columns", systemImage: "square.grid.2x2").tag(2)
                        Label("3 Columns", systemImage: "square.grid.3x2").tag(3)
                    } label: {
                        Label("Grid Columns", systemImage: "square.grid.3x2")
                    }
                    .pickerStyle(.menu)
                }

                Section("Polaroid") {
                    if premium.isPremium {
                        Picker(selection: $polaroidFontRaw) {
                            ForEach(PolaroidFont.allCases, id: \.rawValue) { font in
                                Text(font.displayName).tag(font.rawValue)
                            }
                        } label: {
                            Label("Caption Font", systemImage: "textformat")
                        }
                        Picker(selection: $polaroidFontWeightRaw) {
                            ForEach(PolaroidFontWeight.allCases, id: \.rawValue) { w in
                                Text(w.displayName).tag(w.rawValue)
                            }
                        } label: {
                            Label("Font Weight", systemImage: "bold")
                        }
                        Toggle(isOn: $dateStampEnabled) {
                            Label("Date stamp", systemImage: "calendar.badge.clock")
                        }
                    } else {
                        lockedRow("Caption Font", systemImage: "textformat", feature: .captionStyle)
                        lockedRow("Font Weight", systemImage: "bold", feature: .captionStyle)
                        lockedRow("Date stamp", systemImage: "calendar.badge.clock", feature: .dateStamp)
                    }
                    Toggle(isOn: $printAnimationEnabled) {
                        Label("Print animation", systemImage: "sparkles")
                    }
                    Toggle(isOn: $captionPromptEnabled) {
                        Label("Caption prompt after photo", systemImage: "text.bubble")
                    }
                }

                Section {
                    Label("Sync with iCloud", systemImage: "icloud")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("Your polaroids sync automatically via iCloud. You can manage iCloud access in Settings > Apple Account > iCloud.")
                }

                Section("Privacy") {
                    Button {
                        openURL(URL(string: "https://poly-vintage.com/privacy")!)
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                            .foregroundStyle(.primary)
                    }
                    Button {
                        openURL(URL(string: "https://poly-vintage.com/terms")!)
                    } label: {
                        Label("Terms of Use", systemImage: "doc.text.fill")
                            .foregroundStyle(.primary)
                    }
                }

                Section("App") {
                    Button {
                        openURL(URL(string: "mailto:hello@giusscos.com")!)
                    } label: {
                        Label("Feedback", systemImage: "envelope")
                            .foregroundStyle(.primary)
                    }
                    Button { requestReview() } label: {
                        Label("Rate the App", systemImage: "star.fill")
                            .foregroundStyle(.primary)
                    }
                    Button { showOnboarding = true } label: {
                        Label("Show Onboarding", systemImage: "sparkles")
                            .foregroundStyle(.primary)
                    }
                }

                Section("Language") {
                    Picker(selection: Binding(
                        get: { languageManager.selectedCode },
                        set: {
                            pendingLanguage = $0
                            showLanguageAlert = true
                        }
                    )) {
                        ForEach(languageManager.supportedLanguages, id: \.code) { lang in
                            Text(lang.localName).tag(lang.code)
                        }
                    } label: {
                        Label("Language", systemImage: "globe")
                    }
                    .pickerStyle(.menu)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(.largeTitle.width(.expanded).weight(.bold))
                }
            }
        }
        .sheet(item: $paywallContext) { context in
            PaywallView(context: context, onClose: { paywallContext = nil })
                .environment(PremiumManager.shared)
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubscription)
        .onChange(of: showManageSubscription) { _, isShowing in
            if !isShowing {
                Task { await premium.refreshPurchaseStatus() }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(hasSeenOnboarding: .constant(true))
                .environment(PremiumManager.shared)
        }
        .alert(Text("Apply Language?"), isPresented: $showLanguageAlert, presenting: pendingLanguage) { lang in
            Button(role: .cancel) {} label: { Text("Cancel") }
            Button {
                languageManager.setLanguage(lang)
            } label: {
                Text("Apply")
            }
        } message: { _ in
            Text("Close and reopen the app to fully apply the language changes.")
        }
    }
}

extension SettingsView {
    private var planDescription: String {
        guard let plan = premium.activePlanName else {
            return NSLocalizedString("All features unlocked", comment: "")
        }
        if premium.activeProductID == PremiumManager.lifetimeID {
            return NSLocalizedString("Lifetime — yours forever", comment: "")
        }
        guard let date = premium.expirationDate else { return plan }
        let dateText = date.formatted(date: .abbreviated, time: .omitted)
        let format = premium.willAutoRenew
            ? NSLocalizedString("%@ · renews %@", comment: "")
            : NSLocalizedString("%@ · ends %@", comment: "")
        return String(format: format, plan, dateText)
    }

    private func presentPaywall(_ context: PaywallContext) {
        paywallContext = context
    }

    private func lockedRow(_ title: LocalizedStringKey, systemImage: String, feature: PremiumFeature) -> some View {
        Button { presentPaywall(.feature(feature)) } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}

private func formatDuration(_ seconds: Double) -> String {
    let s = Int(seconds)
    if s < 60 { return "\(s)s" }
    let m = s / 60
    let rem = s % 60
    return rem == 0 ? "\(m)m" : "\(m)m \(rem)s"
}

#Preview {
    SettingsView()
        .environment(PremiumManager.shared)
        .environment(LanguageManager.shared)
}

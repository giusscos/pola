import SwiftUI

struct SettingsView: View {
    @Environment(PremiumManager.self) private var premium
    @State private var showPaywall = false
    @State private var showOnboarding = false

    @AppStorage("defaultFilter") private var defaultFilter: String = "None"
    @AppStorage("captionPromptEnabled") private var captionPromptEnabled: Bool = true
    @AppStorage("polaroidFont") private var polaroidFontRaw: String = PolaroidFont.handwriting.rawValue
    @AppStorage("polaroidFontWeight") private var polaroidFontWeightRaw: String = PolaroidFontWeight.regular.rawValue
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled: Bool = false
    @AppStorage("libraryColumnCount") private var libraryColumnCount: Int = 3
    @AppStorage("videoAudioEnabled") private var videoAudioEnabled: Bool = true
    @AppStorage("timelapseInterval") private var timelapseInterval: Double = 5
    @AppStorage("timelapseDuration") private var timelapseDuration: Double = 60
    @AppStorage("timelapseSaveAsVideo") private var timelapseSaveAsVideo: Bool = false

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
                                Text("All features unlocked")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.title3)
                        }

                        Toggle(isOn: Binding(
                            get: { premium.watermarkDisabled },
                            set: { premium.watermarkDisabled = $0 }
                        )) {
                            Label("Hide watermark on exports", systemImage: "photo")
                        }
                    } else {
                        Button { showPaywall = true } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color(red: 1.0, green: 0.8, blue: 0.3).opacity(0.15))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "crown.fill")
                                        .foregroundStyle(Color(red: 1.0, green: 0.8, blue: 0.3))
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Unlock pola. Premium")
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("Filters, fonts & watermark-free exports")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                } header: {
                    Text("Premium")
                }

                Section("Camera") {
                    Picker(selection: $defaultFilter) {
                        Text("None").tag("None")
                        ForEach(filmFilters) { filter in
                            Text(filter.name).tag(filter.name)
                        }
                    } label: {
                        Label("Default Filter", systemImage: "camera.filters")
                    }
                }

                Section("Video") {
                    Toggle(isOn: $videoAudioEnabled) {
                        Label("Record audio", systemImage: videoAudioEnabled ? "mic.fill" : "mic.slash.fill")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Interval: \(Int(timelapseInterval))s between shots")
                            .font(.subheadline)
                        Slider(value: $timelapseInterval, in: 1...60, step: 1)
                    }
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Duration: \(formatDuration(timelapseDuration))")
                            .font(.subheadline)
                        Slider(value: $timelapseDuration, in: 10...3600, step: 10)
                    }
                    .padding(.vertical, 4)

                    Toggle(isOn: $timelapseSaveAsVideo) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Save as video polaroid")
                            Text(timelapseSaveAsVideo
                                 ? "All frames combined into one video"
                                 : "\(totalTimelapsePhotos) separate photo polaroids")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Time Lapse")
                } footer: {
                    Text("Total frames: \(totalTimelapsePhotos)")
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
                    } else {
                        Button { showPaywall = true } label: {
                            HStack {
                                Label("Caption Font", systemImage: "textformat")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        Button { showPaywall = true } label: {
                            HStack {
                                Label("Font Weight", systemImage: "bold")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                    Toggle(isOn: $captionPromptEnabled) {
                        Label("Caption prompt after photo", systemImage: "text.bubble")
                    }
                }

                Section {
                    Toggle(isOn: $iCloudSyncEnabled) {
                        Label("Sync with iCloud", systemImage: "icloud")
                    }
                } header: {
                    Text("iCloud")
                } footer: {
                    Text("Store your polaroids in iCloud so they're available across your devices. Changes take effect immediately.")
                }

                Section("Privacy") {
                    Button {
                        // TODO: open privacy policy URL
                    } label: {
                        Label("Privacy Policy", systemImage: "hand.raised.fill")
                            .foregroundStyle(.primary)
                    }
                    Button {
                        // TODO: open terms of use URL
                    } label: {
                        Label("Terms of Use", systemImage: "doc.text.fill")
                            .foregroundStyle(.primary)
                    }
                }

                Section("App") {
                    Label("About", systemImage: "info.circle")
                    Button {
                        // TODO: open mail composer
                    } label: {
                        Label("Feedback", systemImage: "envelope")
                            .foregroundStyle(.primary)
                    }
                    Button { showOnboarding = true } label: {
                        Label("Show Onboarding", systemImage: "sparkles")
                            .foregroundStyle(.primary)
                    }
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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environment(PremiumManager.shared)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(hasSeenOnboarding: .constant(true))
                .environment(PremiumManager.shared)
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
}

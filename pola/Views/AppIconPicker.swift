import SwiftUI
import UIKit

/// The default icon plus the premium film-stock colorways registered as alternate icons
/// (ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES).
enum AppIconOption: String, CaseIterable, Identifiable {
    case standard
    case flarn, roda, skift, vylur, frosinn, skrim, gralt

    var id: String { rawValue }

    /// Name passed to `setAlternateIconName`; `nil` restores the primary icon.
    var iconName: String? {
        self == .standard ? nil : "AppIcon-\(assetSuffix)"
    }

    var previewImageName: String { "AppIconPreview-\(assetSuffix)" }

    var displayName: String {
        switch self {
        case .standard: NSLocalizedString("Original", comment: "Default app icon name")
        case .flarn:    "FLÄRN"
        case .roda:     "RÖDA"
        case .skift:    "SKIFT"
        case .vylur:    "VYLUR"
        case .frosinn:  "FROSINN"
        case .skrim:    "SKRÍM"
        case .gralt:    "GRÅLT"
        }
    }

    var isPremium: Bool { self != .standard }

    private var assetSuffix: String {
        self == .standard ? "Default" : rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    static var current: AppIconOption {
        let name = UIApplication.shared.alternateIconName
        return allCases.first { $0.iconName == name } ?? .standard
    }
}

struct AppIconPicker: View {
    @Environment(PremiumManager.self) private var premium
    @Binding var selected: AppIconOption
    var onLocked: () -> Void

    @State private var errorMessage: String? = nil

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(AppIconOption.allCases) { option in
                    iconCell(option)
                }
            }
            .padding(20)

            if !premium.isPremium {
                Text("Colorful icons are part of Poly Premium.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't change the icon", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    private func iconCell(_ option: AppIconOption) -> some View {
        let locked = option.isPremium && !premium.isPremium
        let isSelected = option == selected

        return Button { choose(option, locked: locked) } label: {
            VStack(spacing: 8) {
                Image(option.previewImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                            .padding(-5)
                    }
                    .overlay(alignment: .topTrailing) {
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(6)
                                .background(.black.opacity(0.6), in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                Text(verbatim: option.displayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: option.displayName))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ option: AppIconOption, locked: Bool) {
        guard !locked else {
            onLocked()
            return
        }
        guard option != selected, UIApplication.shared.supportsAlternateIcons else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(option.iconName)
                selected = option
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

import SwiftUI

struct EditPolaroidSheet: View {
    @Bindable var entry: PolaroidEntry
    @Environment(\.dismiss) private var dismiss
    @State private var paywallContext: PaywallContext? = nil

    // Presented from UIKit without the SwiftUI environment, so read the shared instance directly.
    private var premium: PremiumManager { PremiumManager.shared }

    private var colorPickerBinding: Binding<Color> {
        Binding(
            get: {
                if let hex = entry.packColorHex, let c = Color(hex: hex) { return c }
                if let preset = polaPackColors.first(where: { $0.name == entry.packName }) { return preset.color }
                return .white
            },
            set: { entry.packColorHex = $0.hexString }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            swatch(name: nil, color: .white, locked: false)
                            ForEach(polaPackColors) { pack in
                                swatch(name: pack.name, color: pack.color, locked: pack.isLocked(for: premium))
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 4)
                    }
                    if premium.isPremium {
                        ColorPicker("Custom color", selection: colorPickerBinding, supportsOpacity: false)
                    } else {
                        Button { paywallContext = .feature(.frameColors) } label: {
                            HStack {
                                Text("Custom color")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                } header: {
                    Text("Color")
                }

                Section {
                    TextField("Short note...", text: $entry.caption)
                } header: {
                    Text("Caption (front strip)")
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        if entry.backText.isEmpty {
                            Text("Write something on the back...")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $entry.backText)
                            .frame(minHeight: 90)
                            .scrollContentBackground(.hidden)
                    }
                } header: {
                    Text("Back of polaroid")
                }

                if entry.coordinate != nil {
                    Section {
                        Toggle("Show map on back", isOn: $entry.showMap)
                    } header: {
                        Text("Map")
                    } footer: {
                        Text("Disable to show your note instead of the map.")
                    }
                }
            }
            .navigationTitle("Edit Polaroid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $paywallContext) { context in
            PaywallView(context: context, onClose: { paywallContext = nil })
                .environment(PremiumManager.shared)
        }
    }

    private func swatch(name: String?, color: Color, locked: Bool) -> some View {
        let isSelected = entry.packColorHex == nil && entry.packName == name
        return Button {
            if locked {
                paywallContext = .feature(.frameColors)
            } else {
                entry.packName = name
                entry.packColorHex = nil
            }
        } label: {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 34, height: 34)
                    .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1))
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
                    .padding(-4)
            )
        }
        .buttonStyle(.plain)
    }
}

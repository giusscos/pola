import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultFilter") private var defaultFilter: String = "None"
    @AppStorage("captionPromptEnabled") private var captionPromptEnabled: Bool = true
    @AppStorage("iCloudSyncEnabled") private var iCloudSyncEnabled: Bool = false
    @AppStorage("libraryColumnCount") private var libraryColumnCount: Int = 3

    var body: some View {
        NavigationStack {
            List {
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

                Section {
                    Toggle(isOn: $captionPromptEnabled) {
                        Label("Caption prompt after photo", systemImage: "text.bubble")
                    }
                } footer: {
                    Text("Show a note field after each shot so you can caption the photo on the spot.")
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
    }
}

#Preview {
    SettingsView()
}

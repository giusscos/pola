import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("App") {
                    Label("About", systemImage: "info.circle")
                    Label("Feedback", systemImage: "envelope")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack (alignment: .center, spacing: 0) {
                        Text("Settings")
                            .font(.largeTitle.width(.expanded).weight(.bold))
                            .lineHeight(.normal)
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}

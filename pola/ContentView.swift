import SwiftUI

enum AppTab: Hashable {
    case library, filters, settings, search
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .library

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Library", systemImage: "photo.on.rectangle", value: AppTab.library) {
                LibraryView()
            }
            Tab("Filters", systemImage: "wand.and.sparkles", value: AppTab.filters) {
                FiltersView()
            }
            Tab("Settings", systemImage: "gearshape", value: AppTab.settings) {
                SettingsView()
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }
        }
    }
}

#Preview {
    ContentView()
}

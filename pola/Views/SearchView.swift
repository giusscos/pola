import SwiftUI

struct SearchView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                // Search results
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack (alignment: .leading, spacing: 0) {
                        Text("Search")
                            .font(.largeTitle.width(.expanded).weight(.bold))
                            .lineHeight(.normal)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Photos, filters...")
        }
    }
}

#Preview {
    SearchView()
}

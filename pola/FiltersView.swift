import SwiftUI

struct FilmFilter: Identifiable {
    let id = UUID()
    let name: String
    let imageName: String
    let color: Color
    let usdzName: String?
}

struct FiltersView: View {
    private let filters: [FilmFilter] = [
        FilmFilter(name: "Kodak 400", imageName: "kodak400", color: Color(red: 0.95, green: 0.78, blue: 0.12), usdzName: "Kodak_400_Color_Film"),
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 20), count: 2)

    @State private var selectedFilter: FilmFilter? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 24) {
                    ForEach(filters) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            FilterItemCell(filter: filter)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack (alignment: .center, spacing: 0) {
                        Text("Filters")
                            .font(.largeTitle.width(.expanded).weight(.bold))
                        if !filters.isEmpty {
                            let isPlural = filters.count == 1 ? "" : "s"
                            
                            Text("\(filters.count) item\(isPlural)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedFilter) { filter in
            FilterModelView(filter: filter)
        }
    }
}

#Preview {
    FiltersView()
}

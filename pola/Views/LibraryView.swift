import SwiftData
import SwiftUI

struct LibraryView: UIViewControllerRepresentable {
    @Environment(PhotoStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(PremiumManager.self) private var premium
    @Query(sort: \PolaroidEntry.timestamp, order: .reverse) private var entries: [PolaroidEntry]
    @Binding var isDetailOpen: Bool
    @Binding var isSelectMode: Bool

    func makeUIViewController(context: Context) -> UINavigationController {
        let vc = LibraryViewController()
        vc.store = store
        vc.premium = premium
        vc.modelContext = modelContext
        let coordinator = context.coordinator
        vc.onDetailStateChange = { [weak coordinator] isOpen in
            coordinator?.isDetailOpen = isOpen
        }
        vc.onSelectModeChange = { [weak coordinator] isSelect in
            coordinator?.isSelectMode = isSelect
        }
        let nav = UINavigationController(rootViewController: vc)
        coordinator.libraryVC = vc
        return nav
    }

    func updateUIViewController(_ nav: UINavigationController, context: Context) {
        guard let vc = context.coordinator.libraryVC else { return }
        vc.store = store
        vc.premium = premium
        vc.modelContext = modelContext
        vc.entries = entries
    }

    func makeCoordinator() -> Coordinator { Coordinator(isDetailOpen: $isDetailOpen, isSelectMode: $isSelectMode) }

    final class Coordinator {
        weak var libraryVC: LibraryViewController?
        private var detailBinding: Binding<Bool>
        private var selectBinding: Binding<Bool>

        var isDetailOpen: Bool = false {
            didSet { detailBinding.wrappedValue = isDetailOpen }
        }

        var isSelectMode: Bool = false {
            didSet { selectBinding.wrappedValue = isSelectMode }
        }

        init(isDetailOpen: Binding<Bool>, isSelectMode: Binding<Bool>) {
            self.detailBinding = isDetailOpen
            self.selectBinding = isSelectMode
        }
    }
}

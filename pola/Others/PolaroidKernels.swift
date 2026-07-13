import Foundation

enum PolaroidKernels {
    static let data: Data? = {
        guard let url = Bundle.main.url(forResource: "default", withExtension: "metallib"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return data
    }()
}

import Foundation

/// The App Group shared by the app and the Memories widget.
enum AppGroup {
    static let identifier = "group.com.giusscos.pola"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// A lightweight copy of the library that the widget can read without touching SwiftData/CloudKit.
/// The app writes it (thumbnails + this JSON) into the App Group container; the widget only reads it.
struct MemorySnapshot: Codable {
    struct Memory: Codable, Identifiable {
        let id: UUID
        let caption: String
        let timestamp: Date
        let frameColorHex: String
        let frameFormat: FrameFormat
        let imageFilename: String
    }

    var isPremium: Bool
    var memories: [Memory]

    static var directory: URL? {
        AppGroup.containerURL?.appendingPathComponent("Memories", isDirectory: true)
    }

    static var fileURL: URL? {
        directory?.appendingPathComponent("snapshot.json")
    }

    static func load() -> MemorySnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MemorySnapshot.self, from: data)
    }

    static func imageURL(for memory: Memory) -> URL? {
        directory?.appendingPathComponent(memory.imageFilename)
    }
}

/// URLs the widget opens in the app.
enum PolyDeepLink {
    static let scheme = "poly"

    static let premium = URL(string: "\(scheme)://premium")

    static func memory(_ id: UUID) -> URL? {
        URL(string: "\(scheme)://memory/\(id.uuidString)")
    }
}

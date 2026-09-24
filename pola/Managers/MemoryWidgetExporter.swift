import SwiftUI
import UIKit
import WidgetKit

/// Keeps the Memories widget's snapshot in sync with the library.
/// Only thumbnails that don't exist yet are rendered, so repeated exports are cheap.
enum MemoryWidgetExporter {
    private static let maxMemories = 60
    private static let newestCount = 20
    private static let thumbnailSize = CGSize(width: 500, height: 500)

    static func export(entries: [PolaroidEntry], isPremium: Bool) {
        guard let directory = MemorySnapshot.directory else { return }

        let chosen = pickMemories(from: entries)
        var pendingThumbnails: [(filename: String, data: Data)] = []
        let fileManager = FileManager.default

        let memories: [MemorySnapshot.Memory] = chosen.map { entry in
            let filename = "\(entry.id.uuidString).jpg"
            if !fileManager.fileExists(atPath: directory.appendingPathComponent(filename).path) {
                pendingThumbnails.append((filename, entry.imageData))
            }
            return MemorySnapshot.Memory(
                id: entry.id,
                caption: entry.caption,
                timestamp: entry.timestamp,
                frameColorHex: frameColorHex(for: entry),
                frameFormat: entry.frameFormat,
                imageFilename: filename
            )
        }
        let snapshot = MemorySnapshot(isPremium: isPremium, memories: memories)
        guard let snapshotURL = MemorySnapshot.fileURL,
              let json = try? JSONEncoder().encode(snapshot) else { return }
        let keep = Set(memories.map(\.imageFilename) + [snapshotURL.lastPathComponent])
        let maxSize = thumbnailSize

        // Decoding full-size photos is slow, so the file work happens off the main actor.
        Task.detached(priority: .utility) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            for (filename, data) in pendingThumbnails {
                guard let image = UIImage(data: data),
                      let thumb = image.preparingThumbnail(of: fitting(image.size, in: maxSize)),
                      let jpeg = thumb.jpegData(compressionQuality: 0.8) else { continue }
                try? jpeg.write(to: directory.appendingPathComponent(filename), options: .atomic)
            }
            if let existing = try? fileManager.contentsOfDirectory(atPath: directory.path) {
                for name in existing where !keep.contains(name) {
                    try? fileManager.removeItem(at: directory.appendingPathComponent(name))
                }
            }
            try? json.write(to: snapshotURL, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Newest shots, every photo taken around today's date in earlier years (for "On this day"),
    /// and an even spread of the rest of the library.
    private static func pickMemories(from entries: [PolaroidEntry]) -> [PolaroidEntry] {
        let developed = entries
            .filter { $0.developmentProgress >= 1 || Date().timeIntervalSince($0.timestamp) > 30 }
            .sorted { $0.timestamp > $1.timestamp }
        guard developed.count > maxMemories else { return developed }

        var picked = Array(developed.prefix(newestCount))
        var pickedIDs = Set(picked.map(\.id))

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let anniversaries = developed.filter { entry in
            guard !pickedIDs.contains(entry.id) else { return false }
            // Within the next two weeks of the calendar, so the widget has anniversaries even if the app isn't opened daily.
            for offset in 0..<14 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
                if calendar.component(.month, from: day) == calendar.component(.month, from: entry.timestamp),
                   calendar.component(.day, from: day) == calendar.component(.day, from: entry.timestamp) {
                    return true
                }
            }
            return false
        }
        for entry in anniversaries.prefix(maxMemories / 3) {
            picked.append(entry)
            pickedIDs.insert(entry.id)
        }

        let rest = developed.filter { !pickedIDs.contains($0.id) }
        let remaining = maxMemories - picked.count
        if remaining > 0, !rest.isEmpty {
            let step = max(1, rest.count / remaining)
            picked.append(contentsOf: stride(from: 0, to: rest.count, by: step).prefix(remaining).map { rest[$0] })
        }
        return picked
    }

    private static func frameColorHex(for entry: PolaroidEntry) -> String {
        if let hex = entry.packColorHex { return hex }
        if let pack = polaPackColors.first(where: { $0.name == entry.packName }) { return pack.color.hexString }
        return "FFFFFF"
    }
}

nonisolated private func fitting(_ size: CGSize, in bounds: CGSize) -> CGSize {
    let scale = min(1, bounds.width / size.width, bounds.height / size.height)
    return CGSize(width: size.width * scale, height: size.height * scale)
}

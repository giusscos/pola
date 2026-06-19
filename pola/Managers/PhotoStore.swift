import CoreLocation
import Foundation
import SwiftData
import UIKit

@Observable
final class PhotoStore {

    // MARK: - Video directory (iCloud Drive or local fallback)

    private(set) var videoDirectory: URL

    init() {
        videoDirectory = Self.resolveVideoDirectory()
        try? FileManager.default.createDirectory(at: videoDirectory, withIntermediateDirectories: true)
    }

    private static func resolveVideoDirectory() -> URL {
        if let ubiquity = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            return ubiquity.appendingPathComponent("Documents/Videos", isDirectory: true)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Videos", isDirectory: true)
    }

    // MARK: - Video file operations

    func saveVideo(from srcURL: URL, id: UUID) -> String? {
        let filename = "\(id.uuidString).mov"
        let destURL = videoDirectory.appendingPathComponent(filename)
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var succeeded = false
        coordinator.coordinate(writingItemAt: destURL, options: [], error: &coordinatorError) { url in
            do {
                try FileManager.default.moveItem(at: srcURL, to: url)
                succeeded = true
            } catch {
                succeeded = (try? FileManager.default.copyItem(at: srcURL, to: url)) != nil
            }
        }
        return succeeded ? filename : nil
    }

    func deleteVideo(filename: String) {
        let url = videoDirectory.appendingPathComponent(filename)
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        coordinator.coordinate(writingItemAt: url, options: .forDeleting, error: &coordinatorError) { u in
            try? FileManager.default.removeItem(at: u)
        }
    }

    // MARK: - Migration from old flat-file format

    private static let migrationKey = "photoStoreMigrationDone_v2"

    func migrateIfNeeded(into context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: Self.migrationKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.migrationKey)

        let oldDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Photos", isDirectory: true)
        let metaURL = oldDir.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metaURL),
              let metas = try? JSONDecoder().decode([LegacyMetadata].self, from: data) else { return }

        for meta in metas {
            let imgURL = oldDir.appendingPathComponent("\(meta.id.uuidString).jpg")
            guard let imgData = try? Data(contentsOf: imgURL),
                  let image = UIImage(data: imgData) else { continue }

            let coord: CLLocationCoordinate2D? = meta.latitude.flatMap { lat in
                meta.longitude.map { CLLocationCoordinate2D(latitude: lat, longitude: $0) }
            }
            let entry = PolaroidEntry(
                image: image,
                filterName: meta.filterName,
                packName: meta.packName,
                coordinate: coord
            )
            entry.id = meta.id
            entry.caption = meta.caption
            entry.backText = meta.backText
            entry.showMap = meta.showMap
            entry.developmentProgress = meta.developmentProgress
            entry.timestamp = meta.timestamp
            entry.isTimelapse = meta.isTimelapse == true

            if meta.isVideo == true {
                let oldVideoURL = oldDir.appendingPathComponent("\(meta.id.uuidString).mov")
                if FileManager.default.fileExists(atPath: oldVideoURL.path) {
                    entry.videoFilename = saveVideo(from: oldVideoURL, id: meta.id)
                }
            }

            context.insert(entry)
        }

        try? FileManager.default.removeItem(at: metaURL)
        for meta in metas {
            try? FileManager.default.removeItem(at: oldDir.appendingPathComponent("\(meta.id.uuidString).jpg"))
        }
    }

    // MARK: - Legacy Codable model (used only during migration)

    private struct LegacyMetadata: Codable {
        let id: UUID
        var caption: String
        var backText: String
        var showMap: Bool
        var latitude: Double?
        var longitude: Double?
        var developmentProgress: Double
        let timestamp: Date
        let filterName: String?
        let packName: String?
        var isVideo: Bool?
        var isTimelapse: Bool?
    }
}

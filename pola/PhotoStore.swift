import Foundation
import UIKit
import CoreLocation

@Observable
final class PhotoStore {
    var entries: [PolaroidEntry] = []

    private struct Metadata: Codable {
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
        var isVideo: Bool?      // nil treated as false for backward compatibility
        var isTimelapse: Bool?  // nil treated as false for backward compatibility
    }

    private var storageDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Photos", isDirectory: true)
    }()

    private static var localDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Photos", isDirectory: true)
    }

    func configure(iCloudEnabled: Bool) {
        if iCloudEnabled,
           let ubiquity = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            storageDirectory = ubiquity.appendingPathComponent("Documents/Photos", isDirectory: true)
        } else {
            storageDirectory = Self.localDirectory
        }
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        load()
    }

    private func load() {
        let metaURL = storageDirectory.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metaURL),
              let metas = try? JSONDecoder().decode([Metadata].self, from: data) else { return }

        entries = metas.compactMap { meta in
            let imgURL = storageDirectory.appendingPathComponent("\(meta.id.uuidString).jpg")
            guard let imgData = try? Data(contentsOf: imgURL),
                  let image = UIImage(data: imgData) else { return nil }
            let coord: CLLocationCoordinate2D? = meta.latitude.flatMap { lat in
                meta.longitude.map { lon in CLLocationCoordinate2D(latitude: lat, longitude: lon) }
            }
            var videoURL: URL? = nil
            if meta.isVideo == true {
                let vURL = storageDirectory.appendingPathComponent("\(meta.id.uuidString).mov")
                if FileManager.default.fileExists(atPath: vURL.path) {
                    videoURL = vURL
                }
            }
            return PolaroidEntry(
                id: meta.id,
                image: image,
                videoURL: videoURL,
                isTimelapse: meta.isTimelapse == true,
                caption: meta.caption,
                backText: meta.backText,
                showMap: meta.showMap,
                coordinate: coord,
                developmentProgress: meta.developmentProgress,
                timestamp: meta.timestamp,
                filterName: meta.filterName,
                packName: meta.packName
            )
        }
    }

    func persistMetadata() {
        let metas = entries.map { e in
            Metadata(
                id: e.id,
                caption: e.caption,
                backText: e.backText,
                showMap: e.showMap,
                latitude: e.coordinate?.latitude,
                longitude: e.coordinate?.longitude,
                developmentProgress: e.developmentProgress,
                timestamp: e.timestamp,
                filterName: e.filterName,
                packName: e.packName,
                isVideo: e.videoURL != nil ? true : nil,
                isTimelapse: e.isTimelapse ? true : nil
            )
        }
        guard let data = try? JSONEncoder().encode(metas) else { return }
        try? data.write(to: storageDirectory.appendingPathComponent("metadata.json"))
    }

    func add(_ entry: PolaroidEntry) {
        var stored = entry
        let imgURL = storageDirectory.appendingPathComponent("\(entry.id.uuidString).jpg")
        if let data = entry.image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: imgURL)
        }
        if let srcVideoURL = entry.videoURL {
            let destVideoURL = storageDirectory.appendingPathComponent("\(entry.id.uuidString).mov")
            try? FileManager.default.moveItem(at: srcVideoURL, to: destVideoURL)
            stored.videoURL = destVideoURL
        }
        entries.insert(stored, at: 0)
        persistMetadata()
    }

    func delete(ids: Set<UUID>) {
        for id in ids {
            let imgURL = storageDirectory.appendingPathComponent("\(id.uuidString).jpg")
            try? FileManager.default.removeItem(at: imgURL)
            let vidURL = storageDirectory.appendingPathComponent("\(id.uuidString).mov")
            try? FileManager.default.removeItem(at: vidURL)
        }
        entries.removeAll { ids.contains($0.id) }
        persistMetadata()
    }
}

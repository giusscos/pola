import CoreLocation
import SwiftData
import UIKit

@Model
final class PolaroidEntry: Identifiable {
    var id: UUID = UUID()
    // Stored as an external file by SwiftData; CloudKit syncs it as a CKAsset.
    @Attribute(.externalStorage) var imageData: Data = Data()
    var videoFilename: String? = nil
    var isTimelapse: Bool = false
    var caption: String = ""
    var backText: String = ""
    var showMap: Bool = true
    var latitude: Double? = nil
    var longitude: Double? = nil
    var developmentProgress: Double = 0.0
    var timestamp: Date = Date()
    var filterName: String? = nil
    var packName: String? = nil
    var packColorHex: String? = nil

    init(
        image: UIImage,
        videoFilename: String? = nil,
        isTimelapse: Bool = false,
        filterName: String? = nil,
        packName: String? = nil,
        coordinate: CLLocationCoordinate2D? = nil
    ) {
        self.id = UUID()
        self.imageData = image.jpegData(compressionQuality: 0.9) ?? Data()
        self.videoFilename = videoFilename
        self.isTimelapse = isTimelapse
        self.filterName = filterName
        self.packName = packName
        self.latitude = coordinate?.latitude
        self.longitude = coordinate?.longitude
        self.timestamp = Date()
        self.developmentProgress = 0.0
    }

    var image: UIImage? {
        UIImage(data: imageData)
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func videoURL(in directory: URL) -> URL? {
        guard let filename = videoFilename else { return nil }
        return directory.appendingPathComponent(filename)
    }
}

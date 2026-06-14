import UIKit
import CoreLocation

struct PolaroidEntry: Identifiable {
    let id: UUID
    let image: UIImage
    var caption: String = ""
    var backText: String = ""
    var showMap: Bool = true
    var coordinate: CLLocationCoordinate2D? = nil
    var developmentProgress: Double = 0.0
    let timestamp: Date
    let filterName: String?
    let packName: String?

    init(image: UIImage, filterName: String? = nil, packName: String? = nil, coordinate: CLLocationCoordinate2D? = nil) {
        self.id = UUID()
        self.image = image
        self.filterName = filterName
        self.packName = packName
        self.coordinate = coordinate
        self.timestamp = Date()
    }

    init(id: UUID, image: UIImage, caption: String, backText: String, showMap: Bool,
         coordinate: CLLocationCoordinate2D?, developmentProgress: Double,
         timestamp: Date, filterName: String?, packName: String?) {
        self.id = id
        self.image = image
        self.caption = caption
        self.backText = backText
        self.showMap = showMap
        self.coordinate = coordinate
        self.developmentProgress = developmentProgress
        self.timestamp = timestamp
        self.filterName = filterName
        self.packName = packName
    }
}

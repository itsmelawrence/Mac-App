import Foundation
import SwiftData

@Model
final class SavedLocation {
    var name: String
    var latitude: Double
    var longitude: Double
    var isPrimary: Bool

    init(name: String, latitude: Double, longitude: Double, isPrimary: Bool = false) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.isPrimary = isPrimary
    }
}

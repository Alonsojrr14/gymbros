import CoreLocation
import SwiftData

/// Um lugar onde a pessoa treina (academia, box de CrossFit, condomínio…)
@Model
final class Gym {
    var uuid: UUID = UUID()
    var name: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var radius: Double = 100
    var createdAt: Date = Date.now

    init(name: String, coordinate: CLLocationCoordinate2D, radius: Double = 100) {
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.radius = radius
    }

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

/// Uma ida a um lugar de treino: da entrada à saída do raio
@Model
final class GymVisit {
    var uuid: UUID = UUID()
    var gymUUID: UUID?
    var gymName: String = ""
    var start: Date = Date.now
    var end: Date?

    init(gym: Gym) {
        self.gymUUID = gym.uuid
        self.gymName = gym.name
    }

    var minutes: Int? { end.map { max(Int($0.timeIntervalSince(start) / 60), 0) } }
}

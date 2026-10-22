import CoreLocation
import SwiftData

@Model
final class RouteRecord {
    var uuid: UUID = UUID()
    var activityUUID: UUID?
    var kindRaw: String = ActivityKind.corrida.rawValue
    var start: Date = Date.now
    var seconds: Int = 0
    var meters: Double = 0
    /// Pontos do percurso: latitude, longitude, latitude, longitude…
    @Attribute(.externalStorage) var points: Data = Data()

    init(kind: ActivityKind, start: Date) {
        self.kindRaw = kind.rawValue
        self.start = start
    }

    var kind: ActivityKind { ActivityKind(rawValue: kindRaw) ?? .corrida }

    var coordinates: [CLLocationCoordinate2D] {
        let values = points.withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
        return stride(from: 0, to: values.count - 1, by: 2).map { CLLocationCoordinate2D(latitude: values[$0], longitude: values[$0 + 1]) }
    }

    static func encode(_ coords: [CLLocationCoordinate2D]) -> Data {
        var values: [Double] = []
        for c in coords { values.append(c.latitude); values.append(c.longitude) }
        return values.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

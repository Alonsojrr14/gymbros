import HealthKit

/// Como cada tipo do catálogo é gravado no relógio
extension WorkoutType {
    private static let outdoorTypes: Set<HKWorkoutActivityType> = [
        .running, .walking, .hiking, .trackAndField, .wheelchairWalkPace, .wheelchairRunPace, .cycling, .handCycling,
        .swimBikeRun, .surfingSports, .paddleSports, .sailing, .waterSports, .soccer, .volleyball, .americanFootball,
        .australianFootball, .rugby, .baseball, .softball, .cricket, .lacrosse, .discSports, .golf, .tennis, .pickleball,
        .snowSports, .downhillSkiing, .crossCountrySkiing, .snowboarding, .skatingSports, .climbing, .equestrianSports,
        .archery, .fishing, .hunting, .play,
    ]

    var outdoor: Bool { Self.outdoorTypes.contains(type) }

    var distanceType: HKQuantityType? {
        switch type {
        case .running, .walking, .hiking, .trackAndField, .wheelchairWalkPace, .wheelchairRunPace: HKQuantityType(.distanceWalkingRunning)
        case .cycling, .handCycling: HKQuantityType(.distanceCycling)
        case .swimming: HKQuantityType(.distanceSwimming)
        case .downhillSkiing, .snowboarding: HKQuantityType(.distanceDownhillSnowSports)
        default:
            if #available(watchOS 11.0, *) {
                switch type {
                case .crossCountrySkiing: HKQuantityType(.distanceCrossCountrySkiing)
                case .paddleSports: HKQuantityType(.distancePaddleSports)
                case .rowing: HKQuantityType(.distanceRowing)
                default: nil
                }
            } else {
                nil
            }
        }
    }

    static let distanceTypes: Set<HKSampleType> = Set(all.compactMap(\.distanceType))
}

func effortLabel(_ e: Int) -> String {
    switch e {
    case ...3: "Leve"
    case 4...6: "Moderado"
    case 7...8: "Intenso"
    default: "Máximo"
    }
}

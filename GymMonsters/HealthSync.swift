import Foundation
import HealthKit
import SwiftData

/// Importa treinos do app Saúde (iPhone/Apple Watch) como atividades.
/// Só leitura; nada é escrito no Saúde.
@MainActor
enum HealthSync {
    static let store = HKHealthStore()
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Janela da primeira importação
    static let firstImportDays = 14

    private static let enabledKey = "healthEnabled"
    private static let lastSyncKey = "healthLastSync"
    private static let ignoredKey = "healthIgnored"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var lastSync: Date? {
        get { UserDefaults.standard.object(forKey: lastSyncKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastSyncKey) }
    }

    /// Treinos do Saúde que o usuário apagou aqui: não voltam na próxima sincronização
    static var ignored: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: ignoredKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: ignoredKey) }
    }

    static func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType(), HKQuantityType(.bodyMass)])
    }

    struct Result {
        var imported: [Activity] = []
        var skippedOverlap = 0
    }

    /// Busca treinos novos e cria as atividades. Pula os que já existem ou que se sobrepõem
    /// a uma atividade já registrada (ex.: treino guiado de musculação gravado também no Watch).
    static func sync(context: ModelContext) async throws -> Result {
        guard available, enabled else { return Result() }
        let since = lastSync.map { $0.addingTimeInterval(-2 * 86400) }
            ?? Calendar.current.date(byAdding: .day, value: -firstImportDays, to: .now)!

        let query = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: since, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let workouts = try await query.result(for: store)
        let weight = await bodyMass() ?? 70

        let existing = try context.fetch(FetchDescriptor<Activity>())
        let known = Set(existing.compactMap(\.healthUUID)).union(ignored)
        var ranges = existing.map { ($0.date, $0.date.addingTimeInterval(Double($0.minutes) * 60)) }

        var result = Result()
        for w in workouts {
            let id = w.uuid.uuidString
            guard !known.contains(id), w.duration >= 5 * 60 else { continue }
            let start = w.startDate, end = w.endDate
            // Sobreposição de mais da metade do treino com algo já registrado → mesmo treino
            let overlaps = ranges.contains { r in
                let shared = min(end, r.1).timeIntervalSince(max(start, r.0))
                return shared > 0.5 * min(end.timeIntervalSince(start), r.1.timeIntervalSince(r.0))
            }
            if overlaps {
                result.skippedOverlap += 1
                continue
            }

            let kind = kind(for: w.workoutActivityType)
            let minutes = Int((w.duration / 60).rounded())
            let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let activity = Activity(kind: kind, date: start, minutes: minutes,
                                    effort: effort(kind: kind, minutes: minutes, kcal: kcal, weight: weight),
                                    note: kcal.map { "\(Int($0)) kcal" } ?? "")
            activity.healthUUID = id
            activity.source = w.sourceRevision.source.name
            context.insert(activity)
            ranges.append((start, end))
            result.imported.append(activity)
        }
        try context.save()
        lastSync = .now
        return result
    }

    /// Esforço 1–10 a partir do gasto real comparado ao esperado para a atividade em ritmo moderado
    static func effort(kind: ActivityKind, minutes: Int, kcal: Double?, weight: Double) -> Int {
        guard let kcal, kcal > 0, minutes > 0 else { return 5 }
        // kcal/min esperado = MET × 3,5 × peso / 200
        let expected = kind.met * 3.5 * weight / 200 * Double(minutes)
        // Calorias ativas não incluem o metabolismo basal (~1 MET)
        let ratio = kcal / max(expected - 3.5 * weight / 200 * Double(minutes), 1)
        return min(max(Int((5 * ratio).rounded()), 1), 10)
    }

    private static func bodyMass() async -> Double? {
        let q = HKSampleQueryDescriptor(predicates: [.quantitySample(type: HKQuantityType(.bodyMass))],
                                        sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)], limit: 1)
        return try? await q.result(for: store).first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    static func kind(for type: HKWorkoutActivityType) -> ActivityKind {
        switch type {
        case .running: .corrida
        case .walking, .hiking: .caminhada
        case .cycling, .handCycling: .bike
        case .swimming, .waterFitness, .waterPolo: .natacao
        case .volleyball: .volei
        case .soccer, .americanFootball, .australianFootball, .rugby, .handball, .basketball, .hockey: .futebol
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: .musculacao
        case .crossTraining, .highIntensityIntervalTraining, .mixedCardio, .jumpRope: .crossfit
        case .martialArts, .boxing, .kickboxing, .wrestling, .fencing: .lutas
        case .cardioDance, .socialDance, .barre: .danca
        case .yoga, .pilates, .flexibility, .mindAndBody, .taiChi: .yoga
        default: .outro
        }
    }
}

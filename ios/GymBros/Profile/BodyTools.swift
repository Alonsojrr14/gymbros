import Foundation
import HealthKit
import SwiftData

// Calculadora de anilhas e importação do peso do app Saúde

enum Plates {
    /// Anilhas comuns em kg, da maior para a menor
    static let available: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]
    static let bars: [Double] = [20, 15, 10, 0]

    /// Anilhas de cada lado para chegar no total; `rest` é o que não deu para montar
    static func perSide(total: Double, bar: Double) -> (plates: [Double], rest: Double) {
        var side = max((total - bar) / 2, 0)
        var out: [Double] = []
        for p in available {
            while side + 0.0001 >= p {
                out.append(p)
                side -= p
            }
        }
        return (out, side * 2)
    }
}

extension HealthSync {
    /// Peso dos últimos 2 anos no app Saúde, para o gráfico de peso
    @MainActor
    static func importBodyMass(context: ModelContext) async throws -> Int {
        try await store.requestAuthorization(toShare: [], read: [HKQuantityType(.bodyMass)])
        let since = Calendar.current.date(byAdding: .year, value: -2, to: .now)!
        let q = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.bodyMass), predicate: HKQuery.predicateForSamples(withStart: since, end: nil))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        let samples = try await q.result(for: store)
        let existing = try context.fetch(FetchDescriptor<BodyEntry>())
        let known = Set(existing.compactMap(\.healthUUID))
        var days = Set(existing.filter { $0.weight != nil }.map { Calendar.current.startOfDay(for: $0.date) })
        var added = 0
        for s in samples where !known.contains(s.uuid.uuidString) && !days.contains(Calendar.current.startOfDay(for: s.startDate)) {
            let e = BodyEntry(date: s.startDate, weight: (s.quantity.doubleValue(for: .gramUnit(with: .kilo)) * 10).rounded() / 10)
            e.healthUUID = s.uuid.uuidString
            context.insert(e)
            days.insert(Calendar.current.startOfDay(for: s.startDate))
            added += 1
        }
        try context.save()
        return added
    }
}

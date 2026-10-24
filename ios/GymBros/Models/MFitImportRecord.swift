import Foundation
import SwiftData

/// Registro de uma importação do MFIT. Guarda o plano prescrito completo (fiel: carga, faixa de
/// reps, obs, vídeo) em JSON, além das `Routine`s que foram criadas a partir dele.
/// As `Routine`/`RoutineItem` são a forma nativa (treinável, sincronizada); este registro é a fonte
/// rica de origem, para mostrar carga/vídeo prescritos e permitir reimportar.
@Model
final class MFitImportRecord {
    var uuid: UUID = UUID()
    var sourceID: String = ""          // id do plano no MFIT (idempotência)
    var planName: String = ""
    var importedAt: Date = Date.now
    /// Plano normalizado (MFitPlan) codificado em JSON
    var planJSON: String = ""
    /// UUIDs das rotinas criadas, separados por vírgula
    var routineUUIDsRaw: String = ""

    init(plan: MFitPlan, routineUUIDs: [UUID]) {
        self.sourceID = plan.sourceID
        self.planName = plan.name
        self.planJSON = (try? JSONEncoder().encode(plan)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        self.routineUUIDsRaw = routineUUIDs.map(\.uuidString).joined(separator: ",")
    }

    var plan: MFitPlan? {
        guard let data = planJSON.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MFitPlan.self, from: data)
    }

    var routineUUIDs: [UUID] {
        routineUUIDsRaw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }
}

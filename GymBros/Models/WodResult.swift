import Foundation
import SwiftData

@Model
final class WodResult {
    var uuid: UUID = UUID()
    var wodID: String = ""
    var wodName: String = ""
    var formatName: String = ""
    var date: Date = Date.now
    /// For Time: tempo em segundos
    var seconds: Int?
    /// AMRAP: rodadas completas + repetições extras
    var rounds: Int?
    var reps: Int?
    var rx: Bool = true
    var note: String = ""
    var activityUUID: UUID?
    /// For Time que estourou o limite (time cap): não terminou; `seconds` é o limite e `reps` o que deu para fazer
    var capped: Bool = false

    init(wodID: String, wodName: String, formatName: String) {
        self.wodID = wodID
        self.wodName = wodName
        self.formatName = formatName
    }

    var text: String {
        if capped { return "CAP" + ((reps ?? 0) > 0 ? " · \(reps!) reps" : "") }
        if let seconds { return clock(seconds) }
        if let rounds { return "\(rounds) rodadas" + ((reps ?? 0) > 0 ? " + \(reps!)" : "") }
        return "Concluído"
    }

    /// Para comparar resultados (maior = melhor)
    var score: Double {
        // Estourar o limite fica abaixo de qualquer tempo terminado; entre os CAPs, mais reps é melhor
        if capped { return -10_000_000 + Double(reps ?? 0) }
        if let seconds { return -Double(seconds) }
        return Double(rounds ?? 0) * 1000 + Double(reps ?? 0)
    }
}

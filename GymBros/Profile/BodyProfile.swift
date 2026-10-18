import Foundation
import MuscleMap
import SwiftData
import SwiftUI

// Perfil físico (opcional): altura, idade, objetivo e experiência, mais o peso de Peso e medidas.
// Fica só no aparelho, nunca aparece no perfil público. Serve para estimar calorias com o seu peso
// e dar uma referência de energia, proteína e água para o objetivo.

enum FitnessGoal: String, CaseIterable, Identifiable {
    case massa, forca, emagrecer, condicionamento, saude

    var id: String { rawValue }

    var name: String {
        switch self {
        case .massa: "Ganhar massa"
        case .forca: "Ganhar força"
        case .emagrecer: "Emagrecer"
        case .condicionamento: "Condicionamento"
        case .saude: "Saúde"
        }
    }

    /// Ajuste sobre o gasto do dia: superávit pequeno para ganhar, déficit moderado para perder
    var energyShift: Double {
        switch self {
        case .massa: 300
        case .emagrecer: -400
        default: 0
        }
    }

    /// Proteína em g/kg/dia (faixas usuais da literatura de treino de força)
    var protein: ClosedRange<Double> {
        switch self {
        case .massa, .forca: 1.6...2.2
        case .emagrecer: 1.8...2.4
        case .condicionamento, .saude: 1.2...1.6
        }
    }
}

enum Experience: String, CaseIterable, Identifiable {
    case iniciante, intermediario, avancado

    var id: String { rawValue }

    var name: String {
        switch self {
        case .iniciante: "Iniciante"
        case .intermediario: "Intermediário"
        case .avancado: "Avançado"
        }
    }

    var detail: String {
        switch self {
        case .iniciante: "Menos de 1 ano treinando com regularidade"
        case .intermediario: "1 a 3 anos"
        case .avancado: "Mais de 3 anos"
        }
    }
}

enum BodyProfile {
    static let heightKey = "profileHeight", birthYearKey = "profileBirthYear", goalKey = "profileGoal",
               experienceKey = "profileExperience", weightKey = "profileLastWeight"
    /// Entram no backup junto com os outros ajustes
    static let keys = [heightKey, birthYearKey, goalKey, experienceKey, weightKey, "goalWeight", "goalWeekly", "goalMinutes"]

    private static var d: UserDefaults { .standard }

    /// Altura em cm (0 = não informada)
    static var height: Double { d.double(forKey: heightKey) }
    static var birthYear: Int { d.integer(forKey: birthYearKey) }
    static var age: Int? {
        birthYear > 0 ? Calendar.current.component(.year, from: .now) - birthYear : nil
    }
    static var goal: FitnessGoal? { d.string(forKey: goalKey).flatMap(FitnessGoal.init(rawValue:)) }
    static var experience: Experience? { d.string(forKey: experienceKey).flatMap(Experience.init(rawValue:)) }
    static var isFemale: Bool { d.string(forKey: "bodyGender") == BodyGender.female.rawValue }

    /// Último peso de Peso e medidas (copiado aqui para estimativas fora das telas)
    static var weight: Double? {
        let w = d.double(forKey: weightKey)
        return w > 0 ? w : nil
    }

    static func remember(weight: Double?) {
        if let weight, weight > 0 { d.set(weight, forKey: weightKey) }
    }

    /// Peso para estimar calorias quando o Saúde não tem o dado
    static var weightForEstimates: Double { weight ?? LeagueScoring.referenceWeight }

    static func bmi(weight: Double, height: Double) -> Double? {
        height > 0 ? weight / pow(height / 100, 2) : nil
    }

    /// Metabolismo basal (Mifflin-St Jeor)
    static func bmr(weight: Double, height: Double, age: Int, female: Bool) -> Double {
        10 * weight + 6.25 * height - 5 * Double(age) + (female ? -161 : 5)
    }

    /// Fator de atividade pela média de treinos por semana
    static func activityFactor(perWeek: Double) -> Double {
        switch perWeek {
        case ..<1: 1.2
        case ..<3: 1.375
        case ..<5.5: 1.55
        default: 1.725
        }
    }

    struct Targets {
        let maintenance: Double
        let energy: Double
        let protein: ClosedRange<Double>
        let water: Double
    }

    /// Referência diária para o objetivo; nil se faltar algum dado
    static func targets(weight: Double, perWeek: Double) -> Targets? {
        guard height > 0, let age, let goal else { return nil }
        let maintenance = bmr(weight: weight, height: height, age: age, female: isFemale) * activityFactor(perWeek: perWeek)
        // Déficit nunca passa de 20 % do gasto
        let energy = max(maintenance + goal.energyShift, maintenance * 0.8)
        return Targets(maintenance: maintenance, energy: energy,
                       protein: (goal.protein.lowerBound * weight)...(goal.protein.upperBound * weight), water: 0.035 * weight)
    }
}

/// Seção de Metas: dados do corpo e a referência de energia, proteína e água
struct BodyProfileSection: View {
    @Query(sort: \BodyEntry.date, order: .reverse) private var entries: [BodyEntry]
    @Query(sort: \Activity.date, order: .reverse) private var activities: [Activity]
    @AppStorage(BodyProfile.heightKey) private var height = 0.0
    @AppStorage(BodyProfile.birthYearKey) private var birthYear = 0
    @AppStorage(BodyProfile.goalKey) private var goalRaw = ""
    @AppStorage(BodyProfile.experienceKey) private var experienceRaw = ""
    @AppStorage("bodyGender") private var genderRaw = BodyGender.male.rawValue

    private var weight: Double? { entries.compactMap(\.weight).first }

    /// Treinos por semana nas últimas 4 semanas
    private var perWeek: Double {
        let since = Date.now.addingTimeInterval(-28 * 86400)
        return Double(activities.filter { $0.date >= since }.count) / 4
    }

    var body: some View {
        GMSection("Seu corpo", footer: "Tudo opcional e só neste iPhone; nunca aparece no seu perfil público. O peso vem de Peso e medidas (ou do Apple Saúde).") {
            GMLockedRow(title: "Altura", value: height > 0 ? "\(Int(height)) cm" : "") {
                GMDecimalField(title: "", value: Binding(get: { height > 0 ? height : nil }, set: { height = $0 ?? 0 }),
                               step: 1, unit: "cm", start: 170)
            }
            GMDivider()
            GMLockedRow(title: "Ano de nascimento", value: birthYear > 0 ? "\(birthYear)" + (BodyProfile.age.map { " · \($0) anos" } ?? "") : "") {
                GMDecimalField(title: "", value: Binding(get: { birthYear > 0 ? Double(birthYear) : nil },
                                                        set: { birthYear = $0.map { Int($0) } ?? 0 }),
                               step: 1, unit: "", start: 1995, grouping: false)
            }
            GMDivider()
            GMLockedRow(title: "Sexo", value: genderRaw == BodyGender.female.rawValue ? "Feminino" : "Masculino") {
                GMSegmented(options: [(BodyGender.male.rawValue, "Masculino"), (BodyGender.female.rawValue, "Feminino")], selection: $genderRaw)
            }
            if let weight {
                GMDivider()
                HStack {
                    Text("Peso").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("\(Progression.fmt(weight)) kg" + (BodyProfile.bmi(weight: weight, height: height).map { " · IMC \(String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ","))" } ?? ""))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.dim)
                }
            }
        }
        GMSection("Objetivo e experiência", footer: Experience(rawValue: experienceRaw)?.detail) {
            GMLockedRow(title: "Objetivo", value: FitnessGoal(rawValue: goalRaw)?.name ?? "") {
                GMChoiceChips(options: [("", "Não informar")] + FitnessGoal.allCases.map { ($0.rawValue, $0.name) }, selection: $goalRaw)
            }
            GMDivider()
            GMLockedRow(title: "Experiência", value: Experience(rawValue: experienceRaw)?.name ?? "") {
                GMChoiceChips(options: [("", "Não informar")] + Experience.allCases.map { ($0.rawValue, $0.name) }, selection: $experienceRaw)
            }
        }
        nutrition
            .onChange(of: weight, initial: true) { _, w in BodyProfile.remember(weight: w) }
    }

    @ViewBuilder
    private var nutrition: some View {
        if let weight, let t = BodyProfile.targets(weight: weight, perWeek: perWeek) {
            GMSection("Referência do dia", footer: "Estimativa (Mifflin-St Jeor × \(String(format: "%.2f", BodyProfile.activityFactor(perWeek: perWeek)).replacingOccurrences(of: ".", with: ",")) pelos seus \(String(format: "%.1f", perWeek).replacingOccurrences(of: ".", with: ",")) treinos por semana). Ponto de partida, não substitui nutricionista: ajuste pelo que a balança e o rendimento mostrarem em 2–3 semanas.") {
                row("Gasto estimado", "\(Int(t.maintenance.rounded())) kcal")
                GMDivider()
                row("Para o objetivo", "\(Int(t.energy.rounded())) kcal")
                GMDivider()
                row("Proteína", "\(Int(t.protein.lowerBound.rounded()))–\(Int(t.protein.upperBound.rounded())) g")
                GMDivider()
                row("Água", String(format: "%.1f L", t.water).replacingOccurrences(of: ".", with: ","))
            }
        } else {
            GMSection("Referência do dia") {
                Text("Informe altura, ano de nascimento e objetivo, e registre seu peso em Peso e medidas, para ver uma referência de calorias, proteína e água.")
                    .font(.subheadline).foregroundStyle(Theme.dim)
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(value).font(.subheadline.monospacedDigit().weight(.bold)).foregroundStyle(Theme.accent)
        }
    }
}

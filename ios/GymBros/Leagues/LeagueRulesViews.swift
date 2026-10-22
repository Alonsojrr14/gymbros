import SwiftUI

// Seções do formulário da liga para as regras de LeagueRules.swift: verificação, revisão do dono, pose do dia,
// tabela de pontos, limites, metas e início da semana.

/// Verificação do check-in: presets com o resumo em tópicos e, em "Personalizar", cada regra
struct LeagueVerificationSection: View {
    @Binding var settings: LeagueSettings

    private var v: CheckInVerification { settings.verification }

    var body: some View {
        GMSection("Verificação do check-in", footer: v.preset.detail) {
            GMChoiceChips(options: VerificationPreset.allCases.map { ($0, $0.name) }, selection: Binding(
                get: { v.preset },
                set: { settings.verification = .preset($0) }))
            if v.preset != .off {
                GMDivider()
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(v.bullets, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(Theme.dim) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        if v.preset == .personalizado {
            GMSection("Foto obrigatória", footer: v.media.detail) {
                GMSegmented(options: MediaPolicy.allCases.map { ($0, $0.name) }, selection: binding(\.media))
            }
            GMSection("Foto da galeria", footer: v.library.detail) {
                GMSegmented(options: LibraryMediaPolicy.allCases.map { ($0, $0.name) }, selection: binding(\.library))
            }
            GMSection("Horário do check-in", footer: v.time.detail + " A hora verificada é a do aparelho que gravou o treino ou a da foto da galeria; na câmera do app, a hora do post.") {
                GMSegmented(options: CheckInTimePolicy.allCases.map { ($0, $0.name) }, selection: binding(\.time))
            }
            GMSection("Retroativo", footer: "Até quantos dias para trás dá para postar um treino.") {
                GMChoiceChips(options: CheckInVerification.backlogOptions.map { ($0, CheckInVerification.backlogName($0)) },
                              selection: binding(\.backlogDays))
            }
            GMSection {
                GMToggle(title: "Aparelho obrigatório", subtitle: "Só vale treino gravado pelo Apple Watch, pelo Apple Saúde ou pelo GPS do app",
                         isOn: binding(\.deviceRequired))
                GMDivider()
                GMToggle(title: "Local obrigatório", subtitle: "O check-in precisa ter o local (academia marcada ou foto com local)",
                         isOn: binding(\.locationRequired))
            }
        }
    }

    private func binding<T>(_ path: WritableKeyPath<CheckInVerification, T>) -> Binding<T> {
        Binding(get: { settings.verification[keyPath: path] }, set: { settings.verification[keyPath: path] = $0 })
    }
}

/// Revisão do dono e pose do dia
struct LeagueProofSection: View {
    @Binding var settings: LeagueSettings

    var body: some View {
        GMSection(footer: "Com a revisão ligada, cada check-in espera você aprovar ou negar antes de pontuar. Negado, ele sai da liga. A pose do dia muda todo dia e precisa aparecer na foto: sem ela, você pode negar o check-in.") {
            GMToggle(title: "Revisar check-ins", subtitle: "Você aprova ou nega cada check-in", isOn: Binding(
                get: { settings.reviewRequired },
                set: {
                    settings.reviewRequired = $0
                    // O que já estava postado continua valendo
                    settings.reviewSince = $0 ? .now : nil
                }))
            GMDivider()
            GMToggle(title: "Pose do dia", subtitle: "Hoje: \(DailyPose.today.emoji) \(DailyPose.today.name)", isOn: $settings.posesEnabled)
        }
    }
}

/// Tabela do modo "Por atividade"
struct LeaguePointsSection: View {
    @Binding var rules: [ActivityPointRule]
    @State private var editing: ActivityPointRule?

    var body: some View {
        GMSection("Tabela de pontos", footer: "Cada treino vale a linha mais específica que o cobre (um tipo antes de uma seção). Treino fora da tabela vale 0.") {
            if rules.isEmpty {
                Text("Nenhuma atividade ainda: todo check-in vale 0.").font(.subheadline).foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(rules) { r in
                GMRow(icon: r.points < 0 ? "minus.circle" : "plus.circle", iconTint: r.points < 0 ? .red : Theme.accent,
                      title: r.targetName, subtitle: r.summary, chevron: true) { editing = r }
                GMDivider()
            }
            GMRow(icon: "plus", iconTint: Theme.accent, title: "Adicionar atividade") { editing = ActivityPointRule() }
        }
        .gmModal(item: $editing) { r in
            PointRuleEditor(rule: r, isNew: !rules.contains { $0.id == r.id }) { saved in
                if let saved {
                    if let i = rules.firstIndex(where: { $0.id == saved.id }) { rules[i] = saved } else { rules.append(saved) }
                } else {
                    rules.removeAll { $0.id == r.id }
                }
            }
        }
    }
}

private struct PointRuleEditor: View {
    @State var rule: ActivityPointRule
    let isNew: Bool
    /// nil = apagar
    let done: (ActivityPointRule?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false

    var body: some View {
        GMModal(isNew ? "Nova atividade" : "Editar atividade", confirm: "Salvar",
                confirmEnabled: !rule.workoutTypeIDs.isEmpty || !rule.sections.isEmpty, onConfirm: { done(rule); dismiss() }) {
            GMSection("Treinos", footer: "Escolha tipos de treino ou seções inteiras do catálogo.") {
                GMRow(icon: "checklist", iconTint: Theme.accent,
                      title: rule.workoutTypeIDs.isEmpty ? "Escolher tipos" : "\(rule.workoutTypeIDs.count) tipo\(rule.workoutTypeIDs.count == 1 ? "" : "s")",
                      subtitle: rule.workoutTypeIDs.compactMap { WorkoutType.byID($0)?.name }.prefix(4).joined(separator: ", "), chevron: true) { choosing = true }
                GMDivider()
                GMFlow {
                    ForEach(WorkoutType.Section.allCases, id: \.self) { s in
                        let on = rule.sections.contains(s.rawValue)
                        Button {
                            if on { rule.sections.removeAll { $0 == s.rawValue } } else { rule.sections.append(s.rawValue) }
                        } label: {
                            Text(s.rawValue).font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(on ? Theme.accent : Theme.raised, in: .capsule)
                                .foregroundStyle(on ? .black : .white)
                        }
                        .buttonStyle(GMPress())
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            GMSection("Como pontua", footer: rule.method == .perCheckIn ? "Vale os pontos toda vez que a atividade é registrada." : "Vale os pontos a cada quantidade completa: 59 min num \"a cada 30 min\" valem 1 vez.") {
                GMSegmented(options: ActivityPointRule.Method.allCases.map { ($0, $0.name) }, selection: $rule.method)
                GMDivider()
                GMStepper(title: "Pontos", value: $rule.points, range: -100...100, format: { $0 < 0 ? "−\(-$0)" : "\($0)" })
                if rule.method == .perAmount {
                    GMDivider()
                    GMChoiceChips(options: ActivityPointRule.Metric.allCases.map { ($0, $0.name) }, selection: $rule.metric)
                    GMDivider()
                    GMStepper(title: "A cada", value: $rule.every, range: 1...600, step: rule.metric == .km ? 1 : 5,
                              format: { "\($0) \(rule.metric.name)" })
                }
            }
            if rule.points < 0 {
                Text("Pontos negativos: esta atividade tira pontos de quem registrar.").font(.footnote).foregroundStyle(Theme.dim)
            }
            if !isNew {
                GMButton("Tirar da tabela", icon: "trash", kind: .danger) { done(nil); dismiss() }
            }
        }
        .gmSheet(isPresented: $choosing) { close in
            LeagueWorkoutTypePicker(selection: Binding(get: { Set(rule.workoutTypeIDs) }, set: { rule.workoutTypeIDs = $0.sorted() }), close: close)
        }
    }
}

/// Teto de pontos por período
struct LeagueLimitsSection: View {
    @Binding var limits: ScoringLimits
    let scoring: LeagueScoring
    let hasTeams: Bool

    var body: some View {
        GMSection("Limite de pontos", footer: "Deixa a disputa justa: o que passar do teto no período não conta. 0 = sem teto.") {
            GMToggle(title: "Usar limites", isOn: Binding(
                get: { limits.isEnabled },
                set: { on in limits = on ? ScoringLimits(individual: [.day: defaultCap], team: [:]) : ScoringLimits() }))
            if limits.isEnabled {
                ForEach(LimitPeriod.allCases) { p in
                    GMDivider()
                    GMStepper(title: "Pessoa · \(p.name.lowercased())", value: cap(\.individual, p), range: 0...stepRange, step: step,
                              format: format)
                }
                if hasTeams {
                    ForEach(LimitPeriod.allCases) { p in
                        GMDivider()
                        GMStepper(title: "Time · \(p.name.lowercased())", value: cap(\.team, p), range: 0...stepRange * 10, step: step,
                                  format: format)
                    }
                }
            }
        }
    }

    private func format(_ v: Int) -> String { v == 0 ? "—" : scoring.short(v) }

    /// Passo do stepper na unidade da pontuação
    private var step: Int {
        switch scoring {
        case .treinos, .dias: 1
        case .minutos: 15
        case .distancia: 1000
        case .calorias: 50
        case .pontos, .atividades: 10
        }
    }

    private var stepRange: Int { step * 200 }

    private var defaultCap: Int {
        switch scoring {
        case .treinos, .dias: 1
        case .minutos: 120
        case .distancia: 20_000
        case .calorias: 1000
        case .pontos, .atividades: 100
        }
    }

    private func cap(_ side: WritableKeyPath<ScoringLimits, [LimitPeriod: Int]>, _ p: LimitPeriod) -> Binding<Int> {
        Binding(get: { limits[keyPath: side][p] ?? 0 }, set: { limits[keyPath: side][p] = $0 == 0 ? nil : $0 })
    }
}

/// Metas no lugar do ranking, e o início da semana
struct LeagueGoalsSection: View {
    @Binding var settings: LeagueSettings
    let scoring: LeagueScoring
    let hasTeams: Bool

    var body: some View {
        GMSection("Metas", footer: settings.rankingsDisabled
                  ? "Sem ranking: cada pessoa vê só a barra de progresso até a meta. Bom para grupos de constância, sem competição."
                  : "Com meta, cada pessoa (e cada time) vê a barra de progresso até ela, junto do ranking.") {
            GMStepper(title: "Meta por pessoa", value: $settings.individualGoal, range: 0...(step * 500), step: step, format: format)
            if hasTeams {
                GMDivider()
                GMStepper(title: "Meta por time", value: $settings.teamGoal, range: 0...(step * 5000), step: step, format: format)
            }
            GMDivider()
            GMToggle(title: "Esconder o ranking", subtitle: "Só as metas aparecem", isOn: $settings.rankingsDisabled)
        }
        GMSection("Início da semana", footer: "Dia em que o ranking da semana zera.") {
            GMChoiceChips(options: [(0, "Padrão (domingo)")] + (1...7).map { ($0, Self.weekday($0)) },
                          selection: Binding(get: { settings.weekStart ?? 0 }, set: { settings.weekStart = $0 == 0 ? nil : $0 }))
        }
    }

    static func weekday(_ n: Int) -> String {
        var cal = Calendar.current
        cal.locale = Locale(identifier: "pt_BR")
        return cal.shortWeekdaySymbols[n - 1].replacingOccurrences(of: ".", with: "").capitalized
    }

    private func format(_ v: Int) -> String { v == 0 ? "—" : scoring.format(v) }

    private var step: Int {
        switch scoring {
        case .treinos, .dias: 1
        case .minutos: 30
        case .distancia: 1000
        case .calorias: 100
        case .pontos, .atividades: 50
        }
    }
}

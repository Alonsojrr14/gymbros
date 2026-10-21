import SwiftData
import SwiftUI

/// Metas: as pessoais (com cadência, sequência e histórico) e o peso alvo
struct GoalsView: View {
    @Query(sort: \Activity.date) private var activities: [Activity]
    @Query(sort: \BodyEntry.date, order: .reverse) private var body_: [BodyEntry]
    @AppStorage("goalWeight") private var weightGoal = 0.0
    @State private var goals = PersonalGoals.all()
    @State private var editing: PersonalGoal?
    @State private var choosingTemplate = false

    var body: some View {
        let weight = body_.compactMap(\.weight).first
        GMScreen("Metas", back: true) {
            BodyProfileSection()
            GMSection("Minhas metas", footer: "Bater a meta de cada período mantém a sequência viva. O período atual só entra na sequência quando a meta for batida.") {
                if goals.isEmpty {
                    Text("Nenhuma meta. Comece por um modelo ou monte a sua.").font(.subheadline).foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(goals) { g in
                    NavigationLink { GoalDetailView(goal: g, activities: activities) { save($0, delete: $1) } } label: { GoalRow(goal: g, activities: activities) }
                        .buttonStyle(GMPress())
                    GMDivider()
                }
                GMRow(icon: "plus", iconTint: Theme.accent, title: "Nova meta", chevron: true) { choosingTemplate = true }
            }
            GMSection("Peso", footer: "Use Peso e medidas para registrar ou importar do Apple Saúde.") {
                GMLockedRow(title: "Peso alvo", value: weightGoal > 0 ? "\(Progression.fmt(weightGoal)) kg" : "") {
                    GMDecimalField(title: "", value: Binding(get: { weightGoal > 0 ? weightGoal : nil }, set: { weightGoal = $0 ?? 0 }),
                                   step: 0.5, start: weight ?? 70)
                }
                if let weight, weightGoal > 0 {
                    let diff = ((weight - weightGoal) * 10).rounded() / 10
                    Text(diff == 0 ? "Você chegou no peso alvo! 🎯" : "Atual \(Progression.fmt(weight)) kg · faltam \(Progression.fmt(abs(diff))) kg para \(diff > 0 ? "perder" : "ganhar")")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .gmModal(isPresented: $choosingTemplate) {
            GoalTemplatesView { picked in editing = picked }
        }
        .gmModal(item: $editing) { g in GoalFormView(goal: g) { save($0, delete: false) } }
    }

    private func save(_ g: PersonalGoal, delete: Bool) {
        if delete { goals.removeAll { $0.id == g.id } }
        else if let i = goals.firstIndex(where: { $0.id == g.id }) { goals[i] = g }
        else { goals.append(g) }
        PersonalGoals.save(goals)
    }
}

/// Linha da meta: progresso do período atual e a sequência
private struct GoalRow: View {
    let goal: PersonalGoal
    let activities: [Activity]

    var body: some View {
        let periods = goal.periods(activities)
        let now = periods.last
        let streak = goal.streak(periods)
        HStack(spacing: 12) {
            Text(goal.emoji).font(.title2).frame(width: 40, height: 40).background(Theme.raised, in: .circle)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(goal.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer()
                    if streak > 0 && goal.targetDate == nil {
                        Label("\(streak)", systemImage: "flame.fill").font(.caption.bold()).foregroundStyle(Theme.streak)
                            .accessibilityLabel("Sequência de \(goal.cadence.count(streak))")
                    }
                }
                GMProgressBar(value: min((now?.value ?? 0) / max(goal.amount, 0.01), 1), height: 6)
                Text("\(goal.metric.format(now?.value ?? 0)) de \(goal.metric.format(goal.amount))" + (now?.met == true ? " ✅" : ""))
                    .font(.caption.monospacedDigit()).foregroundStyle(Theme.dim)
            }
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.dim)
        }
        .contentShape(Rectangle())
        .foregroundStyle(.white)
    }
}

/// Detalhe: sequência atual e melhor, e o histórico dos períodos
private struct GoalDetailView: View {
    let goal: PersonalGoal
    let activities: [Activity]
    let done: (PersonalGoal, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @State private var all = false

    var body: some View {
        let periods = goal.periods(activities)
        let streak = goal.streak(periods)
        let best = goal.bestStreak(periods)
        GMScreen("\(goal.emoji) \(goal.title)", back: true, large: false) {
            GMIconButton(icon: "pencil", label: "Editar meta") { editing = true }
        } content: {
            Text(goal.summary).font(.subheadline).foregroundStyle(Theme.dim)
            if goal.targetDate == nil {
                HStack {
                    stat("🔥 \(streak)", "sequência atual")
                    stat("🏆 \(best)", "melhor sequência")
                    stat("\(periods.filter(\.met).count)/\(periods.count)", "\(goal.cadence.name.lowercased())s batidos")
                }
                .padding(.vertical, 12)
                .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
                if let last = periods.last {
                    Text(last.met ? "Meta batida \(periodName(last)). A sequência está em \(goal.cadence.count(streak))."
                                  : "Bater \(goal.metric.format(goal.amount)) \(periodName(last)) " + (streak > 0 ? "mantém viva a sequência de \(goal.cadence.count(streak))." : "começa uma sequência nova."))
                        .font(.subheadline)
                }
            }
            let list = Array(periods.reversed())
            GMSection("Histórico") {
                ForEach(Array((all ? list : Array(list.prefix(12))).enumerated()), id: \.element.id) { i, p in
                    if i > 0 { GMDivider() }
                    HStack {
                        Text(periodTitle(p)).font(.subheadline)
                        Spacer()
                        Text(goal.metric.format(p.value)).font(.subheadline.monospacedDigit()).foregroundStyle(p.met ? Theme.accent : Theme.dim)
                        Image(systemName: p.met ? "checkmark.circle.fill" : "circle").foregroundStyle(p.met ? Theme.accent : Theme.dim)
                    }
                }
                if list.count > 12 {
                    GMDivider()
                    GMRow(icon: all ? "chevron.up" : "chevron.down", iconTint: Theme.accent, title: all ? "Mostrar menos" : "Ver os \(list.count)") { all.toggle() }
                }
            }
            GMButton("Apagar meta", icon: "trash", kind: .danger) { deleting = true }
        }
        .gmModal(isPresented: $editing) { GoalFormView(goal: goal) { done($0, false) } }
        .gmActions(isPresented: $deleting, title: "Apagar esta meta?", message: "O histórico dela some. Suas atividades continuam.", actions: [
            GMAction("Apagar", icon: "trash", destructive: true) { done(goal, true); dismiss() }
        ])
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline.monospacedDigit())
            Text(label).font(.caption).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func periodName(_ p: PersonalGoal.Period) -> String {
        switch goal.cadence {
        case .daily: "hoje"
        case .weekly: "nesta semana"
        case .monthly: "neste mês"
        case .yearly: "neste ano"
        }
    }

    private func periodTitle(_ p: PersonalGoal.Period) -> String {
        if goal.targetDate != nil { return "Até \(p.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated).year()))" }
        switch goal.cadence {
        case .daily: return GMDateText.day(p.start)
        case .weekly: return "Semana de \(p.start.formatted(.dateTime.day().month(.abbreviated)))"
        case .monthly: let s = p.start.formatted(.dateTime.month(.wide).year()); return s.prefix(1).uppercased() + s.dropFirst()
        case .yearly: return p.start.formatted(.dateTime.year())
        }
    }
}

/// Escolha de um modelo pronto ou meta do zero
private struct GoalTemplatesView: View {
    let pick: (PersonalGoal) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GMModal("Nova meta") {
            GMSection {
                GMRow(icon: "plus", iconTint: Theme.accent, title: "Montar do zero", chevron: true) { choose(PersonalGoal()) }
            }
            GMSection("Modelos") {
                ForEach(Array(PersonalGoals.templates.enumerated()), id: \.offset) { i, t in
                    if i > 0 { GMDivider() }
                    GMRow(title: "\(t.emoji) \(t.name)", subtitle: t.summary, chevron: true) { choose(t) }
                }
            }
        }
    }

    private func choose(_ g: PersonalGoal) {
        var g = g
        g.id = UUID()
        if g.targetDate == nil { g.start = Calendar.current.startOfDay(for: .now) }
        dismiss()
        // Abre o formulário depois que este fecha
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pick(g) }
    }
}

/// Criar ou editar uma meta
struct GoalFormView: View {
    @State var goal: PersonalGoal
    let save: (PersonalGoal) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choosingTypes = false

    var body: some View {
        GMModal("Meta", confirm: "Salvar", confirmEnabled: goal.amount > 0, onConfirm: { save(goal); dismiss() }) {
            GMSection("Nome") {
                GMTextField(placeholder: "Ex.: Treinar 4× por semana", text: $goal.name)
                GMFlow {
                    ForEach(["🎯", "💪", "🏃", "🔥", "🧘", "🏋️", "⚡", "👑", "🗓️", "🚴"], id: \.self) { e in
                        Button { goal.emoji = e } label: {
                            Text(e).font(.title2).frame(width: 44, height: 44)
                                .background(goal.emoji == e ? Theme.accent.opacity(0.3) : Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
                        }
                        .buttonStyle(GMPress())
                    }
                }
            }
            GMSection("O que medir") {
                GMChoiceChips(options: GoalMetric.allCases.map { ($0, $0.name) }, selection: $goal.metric)
                GMDivider()
                GMStepper(title: "Alvo", value: Binding(get: { Int(goal.amount / goal.metric.step) }, set: { goal.amount = Double($0) * goal.metric.step }),
                          range: 1...2000, format: { goal.metric.format(Double($0) * goal.metric.step) })
            }
            GMSection("Prazo", footer: goal.targetDate == nil ? "Repete todo período; bater a meta mantém a sequência." : "Conta tudo do início até a data, uma vez só.") {
                GMSegmented(options: [(false, "Repetir"), (true, "Até uma data")], selection: Binding(
                    get: { goal.targetDate != nil },
                    set: { goal.targetDate = $0 ? Calendar.current.date(byAdding: .month, value: 3, to: .now) : nil }))
                GMDivider()
                if let d = goal.targetDate {
                    GMDateTimePicker(date: Binding(get: { d }, set: { goal.targetDate = $0 }))
                } else {
                    GMChoiceChips(options: GoalCadence.allCases.map { ($0, $0.name) }, selection: $goal.cadence)
                }
            }
            GMSection("Treinos que contam") {
                GMSegmented(options: [(true, "Todos"), (false, "Só estes")], selection: Binding(
                    get: { goal.activityTypes.isEmpty },
                    set: { all in if all { goal.activityTypes = [] } else { choosingTypes = true } }))
                if !goal.activityTypes.isEmpty {
                    GMDivider()
                    GMRow(icon: "checklist", iconTint: Theme.accent, title: "\(goal.activityTypes.count) tipo\(goal.activityTypes.count == 1 ? "" : "s")",
                          subtitle: goal.activityTypes.compactMap { WorkoutType.byID($0)?.name }.prefix(4).joined(separator: ", "), chevron: true) { choosingTypes = true }
                }
            }
        }
        .gmSheet(isPresented: $choosingTypes) { close in
            LeagueWorkoutTypePicker(selection: Binding(get: { Set(goal.activityTypes) }, set: { goal.activityTypes = $0.sorted() }), close: close)
        }
    }
}

/// Sequências (dia, semana, mês) e recordes de constância
struct ConstancyView: View {
    @Query(sort: \Activity.date) private var activities: [Activity]

    var body: some View {
        let c = Constancy.of(activities)
        GMScreen("Constância", back: true) {
            if activities.isEmpty {
                GMEmptyState(icon: "flame", title: "Nenhum treino ainda", message: "Registre um treino para começar seus recordes.")
            }
            GMSection("Sequências") {
                streak("Dias seguidos", c.daily, .daily)
                GMDivider()
                streak("Semanas seguidas", c.weekly, .weekly)
                GMDivider()
                streak("Meses seguidos", c.monthly, .monthly)
            }
            GMSection("Recordes") {
                if let d = c.bestDay { line("Melhor dia", "\(GMDateText.day(d.date)): \(durationText(d.minutes)) de treino") }
                if let w = c.bestWeek { GMDivider(); line("Melhor semana", "Semana de \(w.start.formatted(.dateTime.day().month(.abbreviated).year())): \(w.days) dia\(w.days == 1 ? "" : "s") ativo\(w.days == 1 ? "" : "s")") }
                if let m = c.bestMonth { GMDivider(); line("Melhor mês", "\(monthName(m.start)): \(m.days) dia\(m.days == 1 ? "" : "s") ativo\(m.days == 1 ? "" : "s")") }
                if let y = c.bestYear { GMDivider(); line("Melhor ano", "\(y.start.formatted(.dateTime.year())): \(y.days) dia\(y.days == 1 ? "" : "s") ativo\(y.days == 1 ? "" : "s")") }
            }
            GMSection("Seu jeito de treinar", footer: "Madrugador: treino que começou antes das \(Constancy.earlyHour) h. Coruja: a partir das \(Constancy.lateHour) h.") {
                if let w = c.topWeekday { line("Dia mais ativo", "\(weekdayName(w.weekday)), em \(w.days) dias diferentes") }
                if let h = c.topHour { GMDivider(); line("Hora mais ativa", "\(h.hour) h, em \(h.days) dias diferentes") }
                GMDivider()
                line("🐓 Madrugador", "\(c.earlyBird) treino\(c.earlyBird == 1 ? "" : "s")")
                GMDivider()
                line("🦉 Coruja", "\(c.nightOwl) treino\(c.nightOwl == 1 ? "" : "s")")
            }
        }
    }

    private func streak(_ title: String, _ s: (current: StreakRun?, best: StreakRun?), _ cadence: GoalCadence) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Label("\(s.current?.length ?? 0)", systemImage: "flame.fill").font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle((s.current?.length ?? 0) > 0 ? Theme.streak : Theme.dim)
            }
            if let b = s.best {
                Text("Melhor: \(cadence.count(b.length)), \(range(b, cadence))" + (b.ongoing ? " e continua agora" : ""))
                    .font(.caption).foregroundStyle(Theme.dim)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func range(_ r: StreakRun, _ c: GoalCadence) -> String {
        switch c {
        case .daily: "de \(r.start.formatted(.dateTime.day().month(.abbreviated))) a \(r.end.formatted(.dateTime.day().month(.abbreviated).year()))"
        case .weekly: "da semana de \(r.start.formatted(.dateTime.day().month(.abbreviated))) à de \(r.end.formatted(.dateTime.day().month(.abbreviated).year()))"
        case .monthly, .yearly: "de \(monthName(r.start).lowercased()) a \(monthName(r.end).lowercased())"
        }
    }

    private func line(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.dim)
            Text(value).font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func monthName(_ d: Date) -> String {
        let s = d.formatted(.dateTime.month(.wide).year())
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    private func weekdayName(_ n: Int) -> String {
        var cal = Calendar.current
        cal.locale = Locale(identifier: "pt_BR")
        return cal.weekdaySymbols[n - 1].capitalized
    }
}

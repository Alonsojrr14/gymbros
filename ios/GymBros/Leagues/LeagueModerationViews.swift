import SwiftData
import SwiftUI

// Moderação da liga: papéis (dono e moderadores), tirar e banir membros, pedidos de entrada,
// prévia antes de entrar e quem fica de dono quando o dono sai. As decisões do dono ficam nas regras da liga
// (`LeagueSettings`), que sobem com ela para o servidor.

extension League {
    /// Aplica uma decisão de moderação nas regras e marca a liga para subir de novo
    @MainActor
    func moderate(_ change: (inout LeagueSettings) -> Void) {
        var s = settings
        change(&s)
        settings = s
        syncedAt = nil
        LeagueRemoteStore.shared.scheduleFlush()
    }
}

/// Pedidos para entrar: o dono (ou um moderador) aceita ou ignora
struct LeagueRequestsSection: View {
    let league: League
    let requests: [RemoteMember]
    @Environment(\.modelContext) private var context

    var body: some View {
        if !requests.isEmpty {
            GMSection("Pedidos para entrar", footer: "Aceito, a pessoa entra na liga. Ignorado, o pedido some (ela pode pedir de novo).") {
                ForEach(Array(requests.enumerated()), id: \.element.id) { i, m in
                    HStack(spacing: 12) {
                        MonsterSprite(form: m.form).frame(width: 38, height: 38)
                        Text(m.name.isEmpty ? "Treinador" : m.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Spacer()
                        GMButton("Ignorar", kind: .secondary, full: false, small: true) { decide(m, accept: false) }
                        GMButton("Aceitar", full: false, small: true) { decide(m, accept: true) }
                    }
                    if i < requests.count - 1 { GMDivider() }
                }
            }
        }
    }

    private func decide(_ m: RemoteMember, accept: Bool) {
        withAnimation {
            league.moderate { s in
                if accept { s.approved.append(m.id) } else { s.ignored.append(m.id) }
            }
        }
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Banidos, na edição da liga: o dono pode desbanir
struct LeagueBannedSection: View {
    @Binding var settings: LeagueSettings
    let names: [String: String]

    var body: some View {
        if !settings.banned.isEmpty {
            GMSection("Banidos", footer: "Quem foi banido não volta nem pelo código.") {
                ForEach(Array(settings.banned.enumerated()), id: \.element) { i, id in
                    HStack {
                        Text(names[id] ?? id).font(.subheadline.weight(.semibold))
                        Spacer()
                        GMButton("Desbanir", kind: .secondary, full: false, small: true) {
                            settings.banned.removeAll { $0 == id }
                            settings.removed.removeAll { $0 == id }
                        }
                    }
                    if i < settings.banned.count - 1 { GMDivider() }
                }
            }
        }
    }
}

/// O dono sai e escolhe quem fica no lugar (ou sorteia)
struct LeagueSuccessorPicker: View {
    let league: League
    let members: [RemoteMember]
    let leave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var choice: String?

    var body: some View {
        GMModal("Quem fica de dono?", confirm: "Sair", confirmEnabled: true, onConfirm: confirm) {
            Text("A liga continua sem você. Escolha quem passa a cuidar das regras, dos pedidos e da revisão. Sem escolha, alguém é sorteado.")
                .font(.subheadline).foregroundStyle(Theme.dim)
            GMSection {
                ForEach(Array(members.enumerated()), id: \.element.id) { i, m in
                    GMRow(title: m.name.isEmpty ? "Treinador" : m.name,
                          subtitle: league.settings.mods.contains(m.id) ? "Moderador" : nil, action: { choice = m.id }) {
                        Image(systemName: choice == m.id ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(choice == m.id ? Theme.accent : Theme.dim)
                    }
                    if i < members.count - 1 { GMDivider() }
                }
            }
        }
    }

    private func confirm() {
        // Sem escolha: sorteia, dando preferência a quem já modera
        let pool = members.filter { league.settings.mods.contains($0.id) }
        let id = choice ?? (pool.isEmpty ? members : pool).randomElement()?.id
        dismiss()
        if let id { leave(id) }
    }
}

// MARK: - Pedido de entrada pendente

/// Pedidos que você fez para entrar em ligas com aprovação (ficam até o dono aceitar ou você cancelar)
struct PendingJoin: Codable, Hashable, Identifiable {
    let code: String
    let name: String
    let emoji: String
    let date: Date
    /// Quem vai representar (nil = ovo novo, criado só quando o pedido for aceito)
    var monsterUUID: UUID?

    var id: String { code }
}

@MainActor
enum PendingJoins {
    static let key = "league.pendingJoins"

    static func all(_ defaults: UserDefaults = .standard) -> [PendingJoin] {
        (defaults.data(forKey: key)).flatMap { try? JSONDecoder().decode([PendingJoin].self, from: $0) } ?? []
    }

    static func save(_ list: [PendingJoin], _ defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(list), forKey: key)
    }

    static func add(_ p: PendingJoin) { save(all().filter { $0.code != p.code } + [p]) }
    static func remove(_ code: String) { save(all().filter { $0.code != code }) }

    /// Entra nas ligas em que o pedido foi aceito
    static func check(context: ModelContext) async {
        for p in all() {
            guard (try? await LeagueRemoteStore.shared.backend.isApproved(code: p.code)) == true,
                  let d = try? await LeagueRemoteStore.shared.join(code: p.code) else { continue }
            let l = League(draft: d)
            l.monsterUUID = context.representative(p.monsterUUID)
            context.insert(l)
            remove(p.code)
        }
        try? context.save()
    }
}

/// Lista de pedidos esperando aprovação, na tela de ligas
struct PendingJoinsSection: View {
    @State private var list = PendingJoins.all()

    var body: some View {
        if !list.isEmpty {
            GMSection("Esperando aprovação", footer: "O dono da liga aprova cada pedido. Quando aceitar, a liga aparece aqui.") {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 12) {
                        Text(p.emoji).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(.subheadline.weight(.semibold))
                            Text("Pedido enviado \(shortAgo(p.date))").font(.caption).foregroundStyle(Theme.dim)
                        }
                        Spacer()
                        GMButton("Cancelar", kind: .secondary, full: false, small: true) {
                            PendingJoins.remove(p.code)
                            list = PendingJoins.all()
                        }
                    }
                    if i < list.count - 1 { GMDivider() }
                }
            }
        }
    }
}

// MARK: - Prévia antes de entrar

/// O que a pessoa vê antes de entrar: tipo, pontuação, regras e se precisa de aprovação
struct LeaguePreviewCard: View {
    let draft: LeagueDraft

    var body: some View {
        let settings = LeagueSettings(rawValue: draft.settings ?? "")
        let scoring = LeagueScoring(rawValue: draft.scoring) ?? .pontos
        let rule = LeagueActivityRule(rawValue: draft.activityRule ?? "")
        GMCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(draft.emoji).font(.largeTitle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.name).font(.headline)
                        Text((draft.end == nil ? "Clube" : "Desafio") + " · " + scoring.name + period).font(.caption).foregroundStyle(Theme.dim)
                    }
                }
                let lines = [scoring.detail]
                    + (rule.mode == .all ? [] : [rule.detail])
                    + (settings.verification.preset == .off ? [] : settings.verification.bullets)
                    + (settings.reviewRequired ? ["O dono aprova cada check-in antes de pontuar"] : [])
                    + (settings.posesEnabled ? ["Pose do dia na foto de todo check-in"] : [])
                    + settings.limits.summary
                    + (settings.requiresApproval ? ["Para entrar, o dono precisa aprovar o seu pedido"] : [])
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(lines, id: \.self) { Text("• " + $0).font(.caption).foregroundStyle(Theme.dim) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var period: String {
        let f = Date.FormatStyle.dateTime.day().month(.abbreviated)
        guard let end = draft.end else { return "" }
        return " · \(draft.start.formatted(f)) – \(end.formatted(f))"
    }
}

// MARK: - Exportar

struct IDBoxURL: Identifiable {
    let url: URL
    var id: String { url.path }
}

enum LeagueExport {
    /// Planilha dos check-ins da liga: data, pessoa, título, atividade, minutos, pontos, foto e se está em revisão
    static func csv(league: League, feed: [FeedItem]) -> URL? {
        func q(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let f = ISO8601DateFormatter()
        var lines = ["data;pessoa;titulo;atividade;minutos;pontos;foto;situacao"]
        for i in feed.sorted(by: { $0.date < $1.date }) {
            lines.append([f.string(from: i.date), q(i.isMe ? "Você" : i.name), q(i.title), q(i.kind.name), "\(i.minutes)", "\(i.score)",
                          i.hasPhoto ? "sim" : "não", i.pending ? "em revisão" : "valendo"].joined(separator: ";"))
        }
        let name = league.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name) - check-ins.csv")
        do { try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}

/// No lugar de um recurso do Pro, quando o Pro estiver valendo
struct ProLockedRow: View {
    let feature: ProFeature

    var body: some View {
        GMSection(footer: feature.detail) {
            NavigationLink { ProPage() } label: {
                GMRow(icon: "star.fill", iconTint: Theme.accent, title: "\(feature.title) · Pro", chevron: true)
            }
            .buttonStyle(GMPress())
        }
    }
}

// MARK: - Desafios do clube e treino do dia

/// Desafios criados dentro do clube
struct ClubChallengesSection: View {
    let club: League
    @Query(sort: \League.start, order: .reverse) private var leagues: [League]
    @State private var creating = false

    var body: some View {
        let list = leagues.filter { $0.settings.parentClub == club.seriesKey && !$0.isPastSeason }
        if !list.isEmpty || club.canModerate {
            GMSection("Desafios do clube", footer: list.isEmpty ? "Crie uma competição com prazo para quem já está no clube, sem precisar convidar de novo." : nil) {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, l in
                    if i > 0 { GMDivider() }
                    NavigationLink { LeagueDetailView(league: l) } label: {
                        GMRow(title: "\(l.emoji) \(l.name)", subtitle: l.isOver ? "Encerrado" : l.hasStarted ? (l.daysLeft.map { "faltam \($0) dias" } ?? "") : League.startsText(l.start), chevron: true)
                    }
                    .buttonStyle(GMPress())
                }
                if club.canModerate {
                    if !list.isEmpty { GMDivider() }
                    GMRow(icon: "plus.circle", iconTint: Theme.accent, title: "Criar desafio no clube", chevron: true) { creating = true }
                }
            }
            .gmModal(isPresented: $creating) { CreateLeagueView(parentClub: club) }
        }
    }
}

/// Treino do dia da liga: o card para todo mundo começar e o editor do dono
struct DailyWorkoutCard: View {
    let workout: DailyWorkout
    let start: () -> Void

    var body: some View {
        GMCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("TREINO DO DIA").font(.caption2.weight(.black)).foregroundStyle(Theme.accent)
                Text(workout.title).font(.headline)
                if !workout.items.isEmpty {
                    Text(workout.items.map { "\(Exercise.name($0.exerciseID)) \($0.sets)×\($0.reps)" }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(Theme.dim).lineLimit(3)
                }
                if !workout.note.isEmpty { Text(workout.note).font(.caption).foregroundStyle(Theme.dim).lineLimit(6) }
                if !workout.items.isEmpty {
                    GMButton("Começar", icon: "play.fill", small: true, action: start)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DailyWorkoutEditor: View {
    let league: League
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Routine.order) private var routines: [Routine]
    @State private var title = ""
    @State private var note = ""
    @State private var from: UUID?
    @State private var loaded = false

    var body: some View {
        GMModal("Treino do dia", confirm: "Postar", confirmEnabled: !title.trimmingCharacters(in: .whitespaces).isEmpty, onConfirm: save) {
            GMSection("Título") { GMTextField(placeholder: "Ex.: Perna pesada", text: $title) }
            GMSection("Exercícios", footer: "Copia os exercícios de uma rotina sua; quem abrir a liga hoje começa o treino com um toque.") {
                GMRow(title: "Sem exercícios (só o texto)", action: { from = nil }) {
                    Image(systemName: from == nil ? "checkmark.circle.fill" : "circle").foregroundStyle(from == nil ? Theme.accent : Theme.dim)
                }
                ForEach(routines) { r in
                    GMDivider()
                    GMRow(title: r.name, subtitle: "\(r.items.count) exercícios", action: {
                        from = r.uuid
                        if title.isEmpty { title = r.name }
                    }) {
                        Image(systemName: from == r.uuid ? "checkmark.circle.fill" : "circle").foregroundStyle(from == r.uuid ? Theme.accent : Theme.dim)
                    }
                }
            }
            GMSection("Texto", footer: "WOD do coach, aquecimento, observações.") {
                GMTextField(placeholder: "Opcional", text: $note, axis: .vertical)
            }
            if league.settings.dailyWorkout?.isToday == true {
                GMButton("Tirar o treino de hoje", icon: "trash", kind: .danger) {
                    league.moderate { $0.dailyWorkout = nil }
                    try? context.save()
                    dismiss()
                }
            }
        }
        .onAppear {
            guard !loaded, let w = league.settings.dailyWorkout, w.isToday else { return }
            loaded = true
            title = w.title
            note = w.note
        }
    }

    private func save() {
        guard ContentFilter.allows(title, note) else { return }
        let items = routines.first { $0.uuid == from }?.sortedItems.map { DailyWorkout.Item(exerciseID: $0.exerciseID, sets: $0.sets, reps: $0.reps) }
            ?? league.settings.dailyWorkout.flatMap { $0.isToday ? $0.items : nil } ?? []
        league.moderate { $0.dailyWorkout = DailyWorkout(day: .now, title: title.trimmingCharacters(in: .whitespaces), items: items, note: note) }
        try? context.save()
        dismiss()
    }
}

extension DailyWorkout {
    /// Rotina de passagem com os exercícios do dia (não fica salva nas suas rotinas)
    var routine: Routine {
        let r = Routine(name: title)
        for (i, item) in items.enumerated() {
            r.items.append(RoutineItem(exerciseID: item.exerciseID, sets: item.sets, reps: item.reps, rest: 90, order: i))
        }
        return r
    }
}

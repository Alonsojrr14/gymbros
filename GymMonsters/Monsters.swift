import Foundation
import SwiftData
import SwiftUI

// Coleção de monstros do jogador. Começa com um (o do onboarding); ao entrar numa liga o
// jogador escolhe quem o representa: um que já tem ou um ovo novo adotado na hora.
//
// Para onde vai o XP de cada atividade:
//   · postada em ligas → para os monstros que representam o jogador nessas ligas
//   · não postada      → para o monstro que era o principal quando ela foi registrada

@Model
final class Monster {
    var uuid: UUID = UUID()
    /// Apelido; vazio usa o nome da forma atual
    var name: String = ""
    var createdAt: Date = Date.now
    var isStarter: Bool = false
    /// Última forma vista, para disparar a cena de evolução uma vez só
    var lastFormID: String = ""
    /// Espécie, fixada quando o ovo choca (nil enquanto é ovo)
    var speciesID: String?

    init(name: String = "", isStarter: Bool = false) {
        self.name = name
        self.isStarter = isStarter
        self.lastFormID = MonsterForm.egg.id
    }

    func displayName(_ form: MonsterForm) -> String {
        form.stage == .egg || name.isEmpty ? form.name : name
    }
}

enum MainMonster {
    private static let key = "mainMonster"

    static var id: UUID? {
        get { UserDefaults.standard.string(forKey: key).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: key) }
    }
}

struct Roster {
    let monsters: [Monster]
    let mainID: UUID?
    /// Atividades de cada monstro
    let records: [UUID: [ActivityRecord]]
    let snapshots: [UUID: Snapshot]

    var main: Monster? { monsters.first { $0.uuid == mainID } ?? monsters.first { $0.isStarter } ?? monsters.first }
    var mainSnapshot: Snapshot { main.flatMap { snapshots[$0.uuid] } ?? Snapshot() }

    func snapshot(_ id: UUID?) -> Snapshot { id.flatMap { snapshots[$0] } ?? Snapshot() }
    func monster(_ id: UUID?) -> Monster? { monsters.first { $0.uuid == id } }

    /// XP que cada atividade rendeu (para listas); se foi para mais de um monstro, o maior
    var xpByActivity: [UUID: Int] {
        snapshots.values.reduce(into: [:]) { acc, s in acc.merge(s.xpByActivity) { max($0, $1) } }
    }

    init(monsters: [Monster], activities: [Activity], checkIns: [LeagueCheckIn], leagues: [League]) {
        self.monsters = monsters
        let starter = monsters.first { $0.isStarter } ?? monsters.first
        let mainID = MainMonster.id.flatMap { id in monsters.contains { $0.uuid == id } ? id : nil } ?? starter?.uuid
        self.mainID = mainID

        let known = Set(monsters.map(\.uuid))
        let leagueMonster = Dictionary(leagues.map { ($0.uuid, $0.monsterUUID) }, uniquingKeysWith: { a, _ in a })
        var posted: [UUID: Set<UUID>] = [:]
        for c in checkIns {
            if let m = leagueMonster[c.leagueUUID] ?? nil, known.contains(m) { posted[c.activityUUID, default: []].insert(m) }
        }

        var recs: [UUID: [ActivityRecord]] = [:]
        for a in activities {
            let fallback = a.monsterUUID.flatMap { known.contains($0) ? $0 : nil } ?? starter?.uuid
            let owners = posted[a.uuid].map(Array.init) ?? [fallback].compactMap { $0 }
            for o in owners { recs[o, default: []].append(a.record) }
        }
        records = recs
        snapshots = Dictionary(uniqueKeysWithValues: monsters.map { m in
            var s = Game.snapshot(recs[m.uuid] ?? [])
            // Espécie gravada no monstro; se acabou de chocar e ainda não foi gravada, calcula pelos treinos do ovo
            if s.stage > .egg {
                let species = m.speciesID ?? Species.hatch(attributes: s.hatchAttributes, seed: m.uuid).id
                s.form = s.form.with(species: species)
                s.evolutions = s.evolutions.map { Evolution(date: $0.date, form: $0.form.with(species: species)) }
            }
            return (m.uuid, s)
        })
    }

    /// Garante o monstro inicial (e migra dados de versões anteriores)
    @MainActor
    static func ensureStarter(context: ModelContext) {
        let monsters = (try? context.fetch(FetchDescriptor<Monster>())) ?? []
        var starter = monsters.first { $0.isStarter }
        if starter == nil {
            let d = UserDefaults.standard
            let m = Monster(name: d.string(forKey: "monsterNick") ?? "", isStarter: true)
            m.createdAt = .distantPast
            m.lastFormID = d.string(forKey: "lastFormID") ?? MonsterForm.egg.id
            context.insert(m)
            starter = m
        }
        if MainMonster.id == nil || !(monsters + [starter!]).contains(where: { $0.uuid == MainMonster.id }) {
            MainMonster.id = starter?.uuid
        }
        // Ligas sem representante (versão anterior ou monstro apagado) ficam com o inicial
        let ids = Set((monsters + [starter!]).map(\.uuid))
        for l in (try? context.fetch(FetchDescriptor<League>())) ?? [] where l.monsterUUID.map({ !ids.contains($0) }) ?? true {
            l.monsterUUID = starter?.uuid
        }
        try? context.save()
    }
}

// MARK: - Telas

/// Coleção: quem é o principal, quem representa cada liga, apelidos
struct TeamView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]
    @Query private var activities: [Activity]
    @Query private var checkIns: [LeagueCheckIn]
    @Query private var leagues: [League]
    @State private var menu: Monster?
    @State private var renaming = false
    @State private var renameTarget: Monster?
    @State private var newName = ""
    @State private var mainID = MainMonster.id

    var body: some View {
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: leagues)
        GMModal("Meus bros", cancel: "Fechar") {
            ForEach(monsters) { m in
                let s = roster.snapshot(m.uuid)
                let reps = leagues.filter { $0.monsterUUID == m.uuid }
                Button { menu = m } label: {
                    GMCard {
                        HStack(spacing: 14) {
                            LivingMonster(form: s.form, progress: s.progress).frame(width: 64, height: 64)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(m.displayName(s.form)).font(.headline)
                                    if m.uuid == roster.mainID { GMBadge(text: "principal") }
                                }
                                Text(s.stage == .egg ? "Ovo · \(s.xpToNext ?? 0) XP para chocar" : "\(s.stage.name) · Nível \(s.level) · \(s.totalXP) XP")
                                    .font(.caption).foregroundStyle(Theme.dim)
                                GMProgressBar(value: s.progress, height: 5)
                                Text(reps.isEmpty ? "Não representa nenhuma liga" : "Liga: " + reps.map { "\($0.emoji) \($0.name)" }.joined(separator: ", "))
                                    .font(.caption2).foregroundStyle(Theme.dim)
                            }
                            Image(systemName: "ellipsis").foregroundStyle(Theme.dim)
                        }
                    }
                }
                .buttonStyle(GMPress())
            }
            Text("O principal aparece na tela inicial e nos widgets e recebe o XP das atividades que não vão para nenhuma liga. Cada liga dá XP só ao bro que te representa nela. Ovos novos você adota ao entrar numa liga.")
                .font(.caption).foregroundStyle(Theme.dim)
        }
        .gmActions(isPresented: Binding(get: { menu != nil }, set: { if !$0 { menu = nil } }),
                   title: menu.map { m in m.displayName(roster.snapshot(m.uuid).form) }, actions: actions)
        .gmPrompt(isPresented: $renaming, title: "Apelido", message: "Vazio usa o nome da forma atual.",
                  placeholder: "Apelido", text: $newName) {
            renameTarget?.name = newName.trimmingCharacters(in: .whitespaces)
            try? context.save()
            renameTarget = nil
        }
    }

    private var actions: [GMAction] {
        guard let m = menu else { return [] }
        var list: [GMAction] = []
        if m.uuid != (mainID ?? MainMonster.id) {
            list.append(GMAction("Tornar principal", icon: "star") {
                MainMonster.id = m.uuid
                mainID = m.uuid
                try? context.save()
            })
        }
        list.append(GMAction("Dar apelido", icon: "pencil") {
            newName = m.name
            renameTarget = m
            renaming = true
        })
        return list
    }
}

/// Escolha de quem representa o jogador numa liga: um monstro da coleção ou um ovo novo
struct MonsterChoiceSection: View {
    /// nil = adotar ovo novo
    @Binding var choice: UUID?
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]
    @Query private var activities: [Activity]
    @Query private var checkIns: [LeagueCheckIn]
    @Query private var leagues: [League]

    var body: some View {
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: leagues)
        GMSection("Quem te representa nesta liga", footer: "Os check-ins desta liga dão XP só para ele.") {
            ForEach(monsters) { m in
                let s = roster.snapshot(m.uuid)
                row(selected: choice == m.uuid, form: s.form, title: m.displayName(s.form),
                    subtitle: s.stage == .egg ? "Ovo" : "\(s.stage.name) · Nível \(s.level)") { choice = m.uuid }
                GMDivider()
            }
            row(selected: choice == nil, form: .egg, title: "Adotar um ovo novo",
                subtitle: "Começa do zero, só com os check-ins desta liga") { choice = nil }
        }
    }

    private func row(selected: Bool, form: MonsterForm, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            HStack(spacing: 12) {
                MonsterSprite(form: form).frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.accent : Theme.dim)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GMPress())
    }
}

extension ModelContext {
    /// Resolve a escolha do representante, criando o ovo novo se for o caso
    @MainActor
    func representative(_ choice: UUID?) -> UUID {
        if let choice { return choice }
        let egg = Monster()
        insert(egg)
        return egg.uuid
    }
}

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
        snapshots = Dictionary(uniqueKeysWithValues: monsters.map { ($0.uuid, Game.snapshot(recs[$0.uuid] ?? [])) })
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
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]
    @Query private var activities: [Activity]
    @Query private var checkIns: [LeagueCheckIn]
    @Query private var leagues: [League]
    @State private var renaming: Monster?
    @State private var newName = ""
    @State private var mainID = MainMonster.id

    var body: some View {
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: leagues)
        NavigationStack {
            List {
                ForEach(monsters) { m in
                    let s = roster.snapshot(m.uuid)
                    let reps = leagues.filter { $0.monsterUUID == m.uuid }
                    HStack(spacing: 14) {
                        LivingMonster(form: s.form, progress: s.progress).frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(m.displayName(s.form)).font(.headline)
                                if m.uuid == roster.mainID {
                                    Text("principal").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Theme.accent.opacity(0.25), in: .capsule)
                                }
                            }
                            Text(s.stage == .egg ? "Ovo · \(s.xpToNext ?? 0) XP para chocar" : "\(s.stage.name) · Nível \(s.level) · \(s.totalXP) XP")
                                .font(.caption).foregroundStyle(Theme.dim)
                            Text(reps.isEmpty ? "Não representa nenhuma liga" : "Liga: " + reps.map { "\($0.emoji) \($0.name)" }.joined(separator: ", "))
                                .font(.caption2).foregroundStyle(Theme.dim)
                        }
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Tornar principal", systemImage: "star") { setMain(m) }
                        Button("Dar apelido", systemImage: "pencil") { newName = m.name; renaming = m }
                    }
                    .swipeActions(edge: .leading) {
                        if m.uuid != roster.mainID { Button("Principal") { setMain(m) }.tint(Theme.accent) }
                    }
                    .onTapGesture { newName = m.name; renaming = m }
                    .listRowBackground(Theme.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Meus monstros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                Text("O principal aparece na tela inicial e nos widgets e recebe o XP das atividades que não vão para nenhuma liga. Cada liga dá XP só ao monstro que te representa nela. Ovos novos você adota ao entrar numa liga. Segure um monstro para mais opções.")
                    .font(.caption).foregroundStyle(Theme.dim).padding()
            }
            .alert("Apelido", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Vazio usa o nome da forma", text: $newName)
                Button("Salvar") {
                    renaming?.name = newName.trimmingCharacters(in: .whitespaces)
                    try? context.save()
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }

    private func setMain(_ m: Monster) {
        MainMonster.id = m.uuid
        mainID = m.uuid
        try? context.save()
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
        Section {
            ForEach(monsters) { m in
                let s = roster.snapshot(m.uuid)
                row(selected: choice == m.uuid) {
                    MonsterSprite(form: s.form).frame(width: 40, height: 40)
                    VStack(alignment: .leading) {
                        Text(m.displayName(s.form))
                        Text(s.stage == .egg ? "Ovo" : "\(s.stage.name) · Nível \(s.level)").font(.caption).foregroundStyle(Theme.dim)
                    }
                } action: { choice = m.uuid }
            }
            row(selected: choice == nil) {
                MonsterSprite(form: .egg).frame(width: 40, height: 40)
                VStack(alignment: .leading) {
                    Text("Adotar um ovo novo")
                    Text("Começa do zero, só com os check-ins desta liga").font(.caption).foregroundStyle(Theme.dim)
                }
            } action: { choice = nil }
        } header: {
            Text("Quem te representa nesta liga")
        } footer: {
            Text("Os check-ins desta liga dão XP só para ele.")
        }
    }

    private func row<Content: View>(selected: Bool, @ViewBuilder content: () -> Content, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                content()
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Theme.accent : Theme.dim)
            }
        }
        .buttonStyle(.plain)
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

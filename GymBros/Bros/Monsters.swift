import Foundation
import SwiftData
import SwiftUI

// Coleção de monstros do jogador. Começa com um (o do onboarding); ao entrar numa liga o
// jogador escolhe quem o representa: um que já tem ou um ovo novo adotado na hora.
//
// Para onde vai o XP de cada atividade:
//   · postada em ligas → para os monstros que representam o jogador nessas ligas
//   · não postada      → para o monstro que era o principal quando ela foi registrada

enum MainMonster {
    /// Chave no UserDefaults (telas observam com @AppStorage para trocar o principal na hora)
    static let key = "mainMonster"

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
    /// Para a regra do destino do XP (`owners`)
    private let known: Set<UUID>
    private let leagueMonster: [UUID: UUID?]
    private let starterID: UUID?

    var main: Monster? { monsters.first { $0.uuid == mainID } ?? monsters.first { $0.isStarter } ?? monsters.first }
    var mainSnapshot: Snapshot { main.flatMap { snapshots[$0.uuid] } ?? Snapshot() }

    func snapshot(_ id: UUID?) -> Snapshot { id.flatMap { snapshots[$0] } ?? Snapshot() }
    func monster(_ id: UUID?) -> Monster? { monsters.first { $0.uuid == id } }

    /// XP que cada atividade rendeu (para listas); se foi para mais de um monstro, o maior
    var xpByActivity: [UUID: Int] {
        snapshots.values.reduce(into: [:]) { acc, s in acc.merge(s.xpByActivity) { max($0, $1) } }
    }

    /// Quem recebe o XP: representantes das ligas marcadas (cada um uma vez); sem liga, o dono gravado ou o inicial
    static func owners(leagueIDs: Set<UUID>, owner: UUID?, known: Set<UUID>, leagueMonster: [UUID: UUID?], starter: UUID?) -> Set<UUID> {
        let reps = Set(leagueIDs.compactMap { leagueMonster[$0] ?? nil }.filter(known.contains))
        if !reps.isEmpty { return reps }
        return Set([owner.flatMap { known.contains($0) ? $0 : nil } ?? starter].compactMap { $0 })
    }

    /// Mesma regra, para uma atividade ainda não salva (prévia do XP)
    func owners(leagueIDs: Set<UUID>, owner: UUID?) -> Set<UUID> {
        Roster.owners(leagueIDs: leagueIDs, owner: owner, known: known, leagueMonster: leagueMonster, starter: starterID)
    }

    init(monsters: [Monster], activities: [Activity], checkIns: [LeagueCheckIn], leagues: [League]) {
        self.monsters = monsters
        let starter = monsters.first { $0.isStarter } ?? monsters.first
        let mainID = MainMonster.id.flatMap { id in monsters.contains { $0.uuid == id } ? id : nil } ?? starter?.uuid
        self.mainID = mainID

        let known = Set(monsters.map(\.uuid))
        let leagueMonster = Dictionary(leagues.map { ($0.uuid, $0.monsterUUID) }, uniquingKeysWith: { a, _ in a })
        self.known = known
        self.leagueMonster = leagueMonster
        starterID = starter?.uuid
        var posted: [UUID: Set<UUID>] = [:]
        for c in checkIns { posted[c.activityUUID, default: []].insert(c.leagueUUID) }

        var recs: [UUID: [ActivityRecord]] = [:]
        for a in activities {
            let owners = Roster.owners(leagueIDs: posted[a.uuid] ?? [], owner: a.monsterUUID, known: known,
                                       leagueMonster: leagueMonster, starter: starter?.uuid)
            for o in owners { recs[o, default: []].append(a.record) }
        }
        records = recs
        snapshots = Dictionary(uniqueKeysWithValues: monsters.map { m in
            var s = Game.cachedSnapshot(recs[m.uuid] ?? [])
            // Espécie gravada no monstro; se acabou de chocar e ainda não foi gravada, calcula pelos treinos do ovo
            if s.stage > .egg {
                let hatched = s.evolutions.first?.date ?? .distantFuture
                let species = m.speciesID ?? Species.hatch(records: (recs[m.uuid] ?? []).filter { $0.date <= hatched }, seed: m.uuid).id
                // Híbrido sem arte ainda: segue a forma normal do atributo dominante
                func resolve(_ f: MonsterForm) -> MonsterForm { let g = f.with(species: species); return g.hasArt ? g : g.single }
                s.form = resolve(s.form)
                s.evolutions = s.evolutions.map { Evolution(date: $0.date, form: resolve($0.form)) }
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

/// "Meus bros" como uma Box: todos os bros em slots e, embaixo, o resumo do selecionado
/// (principal, apelido, ligas, atributos e a ficha no BroBook).
struct MyBrosList: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Monster.createdAt) private var monsters: [Monster]
    @Query private var activities: [Activity]
    @Query private var checkIns: [LeagueCheckIn]
    @Query private var leagues: [League]
    @AppStorage("discovered") private var discovered = ""
    @AppStorage("dexRevealAll") private var revealAll = false
    @State private var selectedID: UUID?
    @State private var renaming = false
    @State private var newName = ""
    @State private var mainID = MainMonster.id
    @State private var dexEntry: MonsterForm?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        let roster = Roster(monsters: monsters, activities: activities, checkIns: checkIns, leagues: leagues)
        let current = roster.monster(selectedID) ?? roster.main
        VStack(alignment: .leading, spacing: 16) {
            box(roster, selected: current?.uuid)
            if let m = current { summary(m, roster.snapshot(m.uuid), isMain: m.uuid == roster.mainID) }
            Text("O principal aparece na tela inicial e nos widgets e recebe o XP das atividades que não vão para nenhuma liga. Cada liga dá XP só ao bro que te representa nela. Ovos novos você adota ao entrar numa liga.")
                .font(.caption).foregroundStyle(Theme.dim)
        }
        .gmPrompt(isPresented: $renaming, title: "Apelido", message: "Vazio usa o nome da forma atual.",
                  placeholder: "Apelido", text: $newName) {
            current?.name = newName.trimmingCharacters(in: .whitespaces)
            try? context.save()
        }
        .sheet(item: $dexEntry) { f in
            let seen = Set(discovered.split(separator: ",").map(String.init))
            DexEntryView(form: f, snapshot: roster.snapshot(current?.uuid), isKnown: { [revealAll] in revealAll || seen.contains($0.id) })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(Theme.radiusXL)
                .presentationBackground(Theme.bg)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }

    // MARK: Box

    private func box(_ roster: Roster, selected: UUID?) -> some View {
        // Sempre fileiras cheias, com pelo menos 3 (os vazios lembram que dá para ter mais)
        let slots = max(12, Int((Double(monsters.count) / 4).rounded(.up)) * 4)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Box", systemImage: "square.grid.3x3.fill").font(.headline)
                Spacer()
                Text("\(monsters.count) \(monsters.count == 1 ? "bro" : "bros")")
                    .font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.dim)
            }
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(0..<slots, id: \.self) { i in
                    if i < monsters.count {
                        let m = monsters[i]
                        slot(m, roster.snapshot(m.uuid), isMain: m.uuid == roster.mainID, selected: m.uuid == selected)
                    } else {
                        RoundedRectangle(cornerRadius: Theme.radiusM)
                            .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                            .aspectRatio(0.82, contentMode: .fit)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(14)
        .background {
            ZStack {
                Theme.card
                LinearGradient(colors: [Theme.accent.opacity(0.08), .clear], startPoint: .top, endPoint: .bottom)
            }
            .clipShape(.rect(cornerRadius: Theme.radius))
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(.white.opacity(0.08), lineWidth: 1))
    }

    private func slot(_ m: Monster, _ s: Snapshot, isMain: Bool, selected: Bool) -> some View {
        let color = s.form.attribute?.color ?? Theme.accent
        let reps = leagues.filter { $0.monsterUUID == m.uuid }
        return Button {
            withAnimation(.snappy) { selectedID = m.uuid }
        } label: {
            VStack(spacing: 2) {
                MonsterSprite(form: s.form).frame(width: 52, height: 52).padding(.top, 10)
                Text(m.displayName(s.form)).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.7)
                Text(s.stage == .egg ? "Ovo" : "Nv \(s.level)").gmFont(9, weight: .semibold, mono: true, relativeTo: .caption2)
                    .foregroundStyle(Theme.dim)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .aspectRatio(0.82, contentMode: .fit)
            .background(selected ? color.opacity(0.2) : Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusM).stroke(selected ? color : .clear, lineWidth: 2))
            .overlay(alignment: .topLeading) {
                if isMain {
                    Image(systemName: "star.fill").font(.system(size: 9, weight: .black)).foregroundStyle(.black)
                        .frame(width: 18, height: 18).background(Theme.accent, in: .circle).offset(x: -4, y: -4)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let l = reps.first {
                    Text(l.emoji).font(.system(size: 11)).frame(width: 20, height: 20)
                        .background(Theme.bg, in: .circle).offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(GMPress())
        .sensoryFeedback(.selection, trigger: selected)
        .accessibilityLabel("\(m.displayName(s.form))\(isMain ? ", principal" : ""), \(s.stage == .egg ? "ovo" : "nível \(s.level)")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Resumo do selecionado

    private func summary(_ m: Monster, _ s: Snapshot, isMain: Bool) -> some View {
        let color = s.form.attribute?.color ?? Theme.accent
        let reps = leagues.filter { $0.monsterUUID == m.uuid }
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                LivingMonster(form: s.form, progress: s.progress)
                    .frame(width: 84, height: 84)
                    .background(color.opacity(0.15), in: .circle)
                    .id(m.uuid)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(m.displayName(s.form)).font(.title3.bold()).lineLimit(1)
                        if isMain { GMBadge(text: "Principal") }
                    }
                    if !m.name.isEmpty, s.stage != .egg {
                        Text(s.form.name).font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
                    }
                    Text(s.stage == .egg ? "Ovo · \(s.xpToNext ?? 0) XP para chocar" : "\(s.stage.name) · Nível \(s.level) · \(s.totalXP.formatted()) XP")
                        .font(.caption).foregroundStyle(Theme.dim)
                    GMProgressBar(value: s.progress, tint: color, height: 5)
                }
            }
            attributes(s)
            HStack(spacing: 6) {
                Image(systemName: "flag.fill").font(.caption).foregroundStyle(Theme.dim)
                Text(reps.isEmpty ? "Não representa nenhuma liga" : reps.map { "\($0.emoji) \($0.name)" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(Theme.dim)
            }
            HStack(spacing: 8) {
                if !isMain {
                    GMButton("Principal", icon: "star", small: true) {
                        MainMonster.id = m.uuid
                        mainID = m.uuid
                        try? context.save()
                    }
                }
                GMButton("Apelido", icon: "pencil", kind: .secondary, small: true) {
                    newName = m.name
                    renaming = true
                }
                GMButton("BroBook", icon: "book.closed", kind: .secondary, small: true) { dexEntry = s.form }
            }
        }
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(color.opacity(0.35), lineWidth: 1))
        .animation(.snappy, value: m.uuid)
    }

    /// Atributos de tudo que ele já treinou (barras relativas ao maior)
    @ViewBuilder
    private func attributes(_ s: Snapshot) -> some View {
        let top = max(s.lifetimeAttributes.values.max() ?? 0, 1)
        if s.lifetimeAttributes.values.contains(where: { $0 > 0 }) {
            VStack(spacing: 7) {
                ForEach(Attribute.allCases) { a in
                    HStack(spacing: 8) {
                        Image(systemName: a.symbol).font(.caption2.bold()).foregroundStyle(a.color).frame(width: 16)
                        Text(a.name).font(.caption.weight(.semibold)).frame(width: 84, alignment: .leading)
                        GMProgressBar(value: (s.lifetimeAttributes[a] ?? 0) / top, tint: a.color, height: 6)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
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

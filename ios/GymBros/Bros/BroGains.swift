import SwiftData
import SwiftUI

/// Um bro que ganha (ou ganhou) XP com uma atividade: o principal leva tudo, quem representa nas ligas um pouco menos
struct BroGain: Identifiable {
    let monster: Monster
    let form: MonsterForm
    let xp: Int
    let main: Bool
    /// Liga em que ele te representa nesta atividade (nil no principal)
    let league: League?

    var id: UUID { monster.uuid }
    var name: String { monster.displayName(form) }

    /// Principal primeiro, depois quem ganhou mais
    static func sorted(_ list: [BroGain]) -> [BroGain] {
        list.sorted { ($0.main ? 1 : 0, $0.xp, $1.name) > ($1.main ? 1 : 0, $1.xp, $0.name) }
    }

    /// Quem ganhou XP com uma atividade já salva, pelo que o Roster calculou
    static func of(_ activity: Activity, roster: Roster, leagues: [League], posted: Set<UUID>) -> [BroGain] {
        let main = roster.monster(activity.monsterUUID)?.uuid ?? roster.mainID
        return sorted(roster.monsters.compactMap { m in
            let s = roster.snapshot(m.uuid)
            guard let xp = s.xpByActivity[activity.uuid], xp > 0 else { return nil }
            return BroGain(monster: m, form: s.form, xp: xp, main: m.uuid == main,
                           league: m.uuid == main ? nil : leagues.first { $0.monsterUUID == m.uuid && posted.contains($0.uuid) })
        })
    }

    /// Prévia de quem vai ganhar XP (registro de atividade, fim do treino): XP de cada bro já calculado
    static func preview(_ xp: [UUID: Int], roster: Roster, leagues: [League], selected: Set<UUID>) -> [BroGain] {
        sorted(xp.compactMap { id, value in
            guard let m = roster.monster(id) else { return nil }
            let isMain = id == roster.mainID
            return BroGain(monster: m, form: roster.snapshot(id).form, xp: value, main: isMain,
                           league: isMain ? nil : leagues.first { $0.monsterUUID == id && selected.contains($0.uuid) })
        })
    }
}

/// Para quem vai o XP de uma atividade. Fechado, uma linha só: os bros em miniatura, o principal e quantos mais,
/// e o total. Tocar abre a lista, um bro por linha (nome, de onde vem e o XP). Funciona igual com 1 ou 30 bros.
struct BroGainsView: View {
    let gains: [BroGain]
    @State private var open = false

    var body: some View {
        let main = gains.first { $0.main } ?? gains[0]
        let others = gains.filter { $0.id != main.id }
        let total = gains.reduce(0) { $0 + $1.xp }
        VStack(spacing: 0) {
            Button {
                guard !others.isEmpty else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.snappy) { open.toggle() }
            } label: {
                HStack(spacing: 10) {
                    BroAvatars(forms: gains.map(\.form), size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(others.isEmpty ? main.name : "\(main.name) e mais \(others.count)").font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(others.isEmpty ? "Principal" : "Principal + \(others.count) de liga")
                            .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Text("+\(total) XP").font(.subheadline.weight(.heavy).monospacedDigit()).foregroundStyle(Theme.accent)
                    if !others.isEmpty {
                        Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(Theme.dim)
                            .rotationEffect(.degrees(open ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
                .foregroundStyle(.white)
            }
            .buttonStyle(GMPress())
            .accessibilityLabel(others.isEmpty ? "\(main.name), principal, mais \(total) XP"
                                : "\(gains.count) bros ganham \(total) XP no total")
            .accessibilityHint(others.isEmpty ? "" : open ? "Fecha a lista" : "Mostra cada bro")
            if open {
                VStack(spacing: 0) {
                    ForEach(gains) { g in
                        GMDivider().padding(.leading, 40)
                        HStack(spacing: 10) {
                            MonsterSprite(form: g.form).frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(g.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    if g.main { GMBadge(text: "Principal") }
                                }
                                Text(g.main ? "Recebe o XP inteiro" : g.league.map { "\($0.emoji) \($0.name)" } ?? "Liga")
                                    .font(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text("+\(g.xp) XP").font(.subheadline.weight(.bold).monospacedDigit())
                                .foregroundStyle(g.main ? Theme.accent : .white)
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Bros de uma atividade em miniatura, um sobre o outro (listas): até 3 e o "+N"
struct BroAvatars: View {
    let forms: [MonsterForm]
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: -size * 0.4) {
            ForEach(Array(forms.prefix(3).enumerated()), id: \.offset) { _, f in
                MonsterSprite(form: f)
                    .frame(width: size * 0.85, height: size * 0.85)
                    .frame(width: size, height: size)
                    .background(Theme.card, in: .circle)
                    .overlay(Circle().stroke(Theme.raised, lineWidth: 1))
            }
            if forms.count > 3 {
                Text("+\(forms.count - 3)").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.dim)
                    .frame(width: size, height: size).background(Theme.card, in: .circle)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(forms.count == 1 ? "1 bro" : "\(forms.count) bros")
    }
}

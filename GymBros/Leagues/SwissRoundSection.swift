import SwiftUI

/// Seu confronto suíço de hoje e as suas últimas rodadas
struct SwissRoundSection: View {
    let league: League
    let table: SwissTable
    /// Ranking da liga toda, para nome e bro de cada pessoa
    let people: [RankRow]

    var body: some View {
        let history = table.history(of: "me")
        if let match = table.today?.match(of: "me") {
            GMSection("Rodada suíça de hoje", footer: footer) {
                today(match)
                if !history.isEmpty {
                    GMDivider()
                    historyRow(history)
                }
            }
        } else if !history.isEmpty {
            GMSection("Rodada suíça", footer: footer) { historyRow(history) }
        }
    }

    private var footer: String {
        let b = SwissBonus.table[league.scoring] ?? (0, 0)
        let bonus = "No fim do dia, vitória ou folga soma \(league.scoring.format(b.win)) no placar"
            + (b.draw > 0 ? " e empate, \(league.scoring.format(b.draw))." : ".")
        return "Todo dia você enfrenta alguém com pontuação suíça parecida, sem repetir adversário enquanto der. "
            + "\(league.swiss.detail) Vitória e folga valem 1, empate ½; se ninguém treinou, 0 para os dois. " + bonus
    }

    @ViewBuilder
    private func today(_ match: SwissMatch) -> some View {
        if match.isBye {
            HStack(spacing: 12) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.info)
                    .frame(width: 44, height: 44)
                    .background(Theme.raised, in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Folga hoje: +1").font(.subheadline.bold())
                    Text("Número ímpar de pessoas: vale como vitória.").font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
            }
        } else if let opponent = match.opponent(of: "me") {
            let mine = match.tally(of: "me"), theirs = match.opponentTally(of: "me")
            let (a, b) = (league.swiss.value(mine), league.swiss.value(theirs))
            HStack(spacing: 8) {
                side("me", tally: mine, ahead: a > b)
                VStack(spacing: 2) {
                    Text("×").font(.title3.bold()).foregroundStyle(Theme.dim)
                    Text("em andamento").font(.caption2).foregroundStyle(Theme.dim)
                }
                .fixedSize()
                side(opponent, tally: theirs, ahead: b > a)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func side(_ id: String, tally: SwissTally, ahead: Bool) -> some View {
        let row = people.first { $0.id == id }
        let name = id == "me" ? "Você" : row?.name ?? "?"
        return VStack(spacing: 4) {
            MonsterSprite(form: row?.avatar ?? .egg).frame(width: 44, height: 44)
            Text(name).font(.caption.bold()).lineLimit(1)
            Text(partial(tally))
                .font(.headline.monospacedDigit())
                .foregroundStyle(ahead ? Theme.accent : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// Placar parcial do dia no critério da liga
    private func partial(_ t: SwissTally) -> String {
        switch league.swiss {
        case .pontos: league.scoring.short(t.score)
        case .checkins: "\(t.checkIns) check-in\(t.checkIns == 1 ? "" : "s")"
        case .presenca: t.trained ? "treinou" : "ainda não"
        }
    }

    private func historyRow(_ history: [(day: Date, result: SwissResult)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suas rodadas").font(.caption.weight(.semibold)).foregroundStyle(Theme.dim)
            HStack(spacing: 10) {
                ForEach(history.reversed(), id: \.day) { h in
                    VStack(spacing: 3) {
                        GMBadge(text: h.result.letter, tint: tint(h.result))
                        Text(h.day.formatted(.dateTime.day().month(.defaultDigits))).font(.caption2).foregroundStyle(Theme.dim)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(h.result.name), \(h.day.formatted(date: .abbreviated, time: .omitted))")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tint(_ r: SwissResult) -> Color {
        switch r {
        case .vitoria: Theme.accent
        case .empate: .white
        case .derrota: Theme.danger
        case .folga: Theme.info
        }
    }
}

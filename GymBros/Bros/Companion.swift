import Foundation
import MuscleMap
import SwiftData
import UserNotifications

// MARK: - Frases do monstro

enum Companion {
    struct Context {
        var name: String
        var mood: Mood
        var snapshot: Snapshot
        var trainedToday: Bool
        var todayRoutine: String?
        /// Músculos sem treino nos últimos 7 dias (só faz sentido para quem usa o treino guiado)
        var neglected: [Muscle]
        var daysAway: Int
    }

    /// Uma frase por dia e humor: muda ao longo do tempo, mas não a cada vez que a tela redesenha
    static func line(_ c: Context, now: Date = .now) -> String {
        let options = candidates(c)
        let seed = Calendar.current.ordinality(of: .day, in: .era, for: now) ?? 0
        return options[seed % options.count]
    }

    private static func candidates(_ c: Context) -> [String] {
        let s = c.snapshot
        switch c.mood {
        case .ovo:
            return s.totalXP == 0
                ? ["Toc toc… tem alguém aqui dentro.", "Um treino e eu começo a esquentar!", "Estou esperando você se mexer!"]
                : ["Tá ficando quentinho aqui dentro…", "Faltam \(s.xpToNext ?? 0) XP para eu sair!", "Senti esse último treino! Mais um!"]
        case .exausto:
            return ["Ufa… hoje já deu, né? Descanso também me faz crescer.", "Bati o limite do dia. Amanhã tem mais!",
                    "Tô suado até a alma. Bora descansar?"]
        case .animado:
            return ["\(s.streak) dias seguidos! Ninguém segura a gente! 🔥", "Tô me sentindo mais forte a cada dia!",
                    "Que sequência! Já sinto a próxima evolução chegando."]
        case .feliz:
            if !c.trainedToday, let r = c.todayRoutine {
                return ["Hoje é dia de \(r)! Vamos?", "\(r) hoje, hein? Tô pronto!"]
            }
            if !c.trainedToday, let m = c.neglected.first {
                return ["Faz uma semana que a gente não treina \(m.ptName.lowercased()). Que tal hoje?",
                        "E se hoje fosse dia de \(m.ptName.lowercased())?"]
            }
            if c.trainedToday {
                return ["Treino feito! Agora é comer bem e descansar.", "Boa! Senti essa.", "Mais um treino no bolso 💪"]
            }
            return ["Bora treinar hoje?", "Tô com energia sobrando!", "Que tal mexer o corpo hoje?"]
        case .entediado:
            if let r = c.todayRoutine { return ["Faz \(c.daysAway) dias… hoje tem \(r), vamos?"] }
            return ["Faz \(c.daysAway) dias que a gente não treina… tô ficando mole.", "Tô entediado. Bora sair um pouco?",
                    "Qualquer treino serve! Até uma caminhada."]
        case .triste:
            return ["Faz \(c.daysAway) dias… senti sua falta. 😢", "Será que você me esqueceu?",
                    "Uma caminhada curtinha já me deixaria feliz."]
        }
    }
}

// MARK: - Conquistas

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let current: Double
    let goal: Double

    var unlocked: Bool { current >= goal }
    var progress: Double { min(current / goal, 1) }
}

enum Achievements {
    struct Input {
        var activities: [ActivityRecord]
        var fromHealth: Int
        var snapshot: Snapshot
        /// Treinos guiados concluídos, do mais antigo ao mais novo
        var sessions: [SessionLog]
        /// Espécies diferentes entre os monstros já chocados
        var species = 0
        /// Monstros que chegaram à Lenda
        var ultimates = 0
        /// Formas descobertas no BroBook e total existente
        var discovered = 0
        var dexTotal = 1
    }

    static func evaluate(_ i: Input) -> [Achievement] {
        let acts = i.activities
        let n = Double(acts.count)
        let kinds = Double(Set(acts.map(\.kind)).count)
        let longest = Double(acts.map(\.minutes).max() ?? 0)
        let hours = acts.map { Calendar.current.component(.hour, from: $0.date) }
        let stage = i.snapshot.stage.rawValue
        let done = i.sessions.flatMap(\.sets).filter(\.done)
        let tons = done.reduce(0) { $0 + $1.weight * Double($1.reps) } / 1000

        var prs = 0
        for (k, s) in i.sessions.enumerated() where k > 0 {
            prs += Progression.records(in: s, history: Array(i.sessions[..<k])).count
        }

        // Semana completa: todos os músculos do mapa trabalhados em alguma janela de 7 dias
        var fullWeek = false
        for s in i.sessions {
            let window = i.sessions.filter { $0.date <= s.date && $0.date > s.date.addingTimeInterval(-7 * 86400) }
            let hit = Set(muscleLoad(window.flatMap(\.sets)).keys)
            if Muscle.tracked.allSatisfy(hit.contains) {
                fullWeek = true
                break
            }
        }

        return [
            Achievement(id: "primeiro", title: "Primeiro passo", detail: "Registre sua primeira atividade", symbol: "figure.walk", current: n, goal: 1),
            Achievement(id: "chocou", title: "Chocou!", detail: "Choque o ovo", symbol: "sparkles", current: Double(stage), goal: 1),
            Achievement(id: "rookie", title: "Crescendo", detail: "Chegue ao estágio Novato", symbol: "arrow.up.circle", current: Double(stage), goal: 2),
            Achievement(id: "champion", title: "Campeão", detail: "Chegue ao estágio Atleta", symbol: "trophy", current: Double(stage), goal: 3),
            Achievement(id: "ultimate", title: "Forma final", detail: "Chegue ao estágio Lenda", symbol: "crown", current: Double(stage), goal: 4),
            Achievement(id: "treinos10", title: "Pegando o ritmo", detail: "10 atividades", symbol: "10.circle", current: n, goal: 10),
            Achievement(id: "treinos50", title: "Rotina de atleta", detail: "50 atividades", symbol: "50.circle", current: n, goal: 50),
            Achievement(id: "treinos100", title: "Centenário", detail: "100 atividades", symbol: "100.circle", current: n, goal: 100),
            Achievement(id: "seq3", title: "Embalado", detail: "3 dias seguidos", symbol: "flame", current: Double(i.snapshot.bestStreak), goal: 3),
            Achievement(id: "seq7", title: "Semana cheia", detail: "7 dias seguidos", symbol: "flame.fill", current: Double(i.snapshot.bestStreak), goal: 7),
            Achievement(id: "seq30", title: "Imparável", detail: "30 dias seguidos", symbol: "bolt.heart", current: Double(i.snapshot.bestStreak), goal: 30),
            Achievement(id: "variado", title: "Eclético", detail: "5 tipos de atividade diferentes", symbol: "square.grid.2x2", current: kinds, goal: 5),
            Achievement(id: "maratona", title: "Maratonista", detail: "Uma atividade de 2 horas", symbol: "timer", current: longest, goal: 120),
            Achievement(id: "madrugador", title: "Madrugador", detail: "Treine antes das 7h", symbol: "sunrise", current: hours.contains { $0 < 7 } ? 1 : 0, goal: 1),
            Achievement(id: "coruja", title: "Coruja", detail: "Treine depois das 21h", symbol: "moon.stars", current: hours.contains { $0 >= 21 } ? 1 : 0, goal: 1),
            Achievement(id: "guiado10", title: "Disciplina", detail: "10 treinos guiados", symbol: "list.clipboard", current: Double(i.sessions.count), goal: 10),
            Achievement(id: "pr1", title: "Recordista", detail: "Bata seu primeiro recorde", symbol: "medal", current: Double(prs), goal: 1),
            Achievement(id: "pr25", title: "Máquina de PRs", detail: "25 recordes", symbol: "medal.fill", current: Double(prs), goal: 25),
            Achievement(id: "ton10", title: "Dez toneladas", detail: "10 t levantadas no total", symbol: "scalemass", current: tons, goal: 10),
            Achievement(id: "ton100", title: "Cem toneladas", detail: "100 t levantadas no total", symbol: "scalemass.fill", current: tons, goal: 100),
            Achievement(id: "corpo", title: "Corpo inteiro", detail: "Treine todos os músculos do mapa em 7 dias", symbol: "figure.stand", current: fullWeek ? 1 : 0, goal: 1),
            Achievement(id: "especies2", title: "Nova espécie", detail: "Choque um bro de outra espécie", symbol: "pawprint", current: Double(i.species), goal: 2),
            Achievement(id: "especies4", title: "Colecionador", detail: "Bros de 4 espécies diferentes", symbol: "pawprint.fill", current: Double(i.species), goal: 4),
            Achievement(id: "especies8", title: "Zoológico completo", detail: "Bros das 8 espécies", symbol: "tortoise.fill", current: Double(i.species), goal: Double(max(Species.catalog.count, 2))),
            Achievement(id: "ultimate2", title: "Treinador de elite", detail: "2 bros no estágio Lenda", symbol: "crown.fill", current: Double(i.ultimates), goal: 2),
            Achievement(id: "dex25", title: "Pesquisador", detail: "Descubra 25 formas no BroBook", symbol: "book", current: Double(i.discovered), goal: 25),
            Achievement(id: "dexall", title: "BroBook completo", detail: "Descubra todas as formas", symbol: "book.fill", current: Double(i.discovered), goal: Double(i.dexTotal)),
            Achievement(id: "saude", title: "Conectado", detail: "Importe um treino do Apple Saúde", symbol: "heart.text.square", current: Double(i.fromHealth), goal: 1),
        ]
    }
}

// MARK: - Lembretes

enum Reminders {
    static let prefix = "reminder-"

    /// Agenda os próximos 7 dias. Dias já treinados ficam de fora; reagendado a cada mudança.
    static func schedule(enabled: Bool, minuteOfDay: Int, onlyRoutineDays: Bool, routines: [Int: String],
                         name: String, streak: Int, trainedToday: Bool, isEgg: Bool) {
        let center = UNUserNotificationCenter.current()
        let ids = (0..<8).map { "\(prefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
        guard enabled else { return }

        let cal = Calendar.current
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: .now)),
                  let fire = cal.date(byAdding: .minute, value: minuteOfDay, to: day), fire > .now else { continue }
            if offset == 0 && trainedToday { continue }
            let routine = routines[cal.component(.weekday, from: day)]
            if onlyRoutineDays && routine == nil { continue }

            let content = UNMutableNotificationContent()
            content.title = isEgg ? "Seu ovo está esfriando 🥚" : "\(name) está te chamando"
            if let routine {
                content.body = "Hoje é dia de \(routine). Bora?"
            } else if offset == 0 && streak > 0 {
                content.body = "Não deixa a sequência de \(streak) dia\(streak == 1 ? "" : "s") acabar 🔥"
            } else {
                content.body = "Que tal um treino hoje? Qualquer atividade conta."
            }
            content.sound = .default
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            center.add(UNNotificationRequest(identifier: "\(prefix)\(offset)", content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}

// MARK: - Resumo semanal

/// Notificação de domingo à noite com a semana: treinos, tempo, PRs e posição nas ligas.
/// O texto é montado ao agendar e reagendado sempre que os dados mudam.
enum WeeklySummary {
    static let id = "weekly-summary"

    @MainActor
    static func schedule(enabled: Bool, trainer: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard enabled else { return }
        let cal = Calendar.current
        // Próximo domingo às 19h (hoje, se ainda não passou)
        guard let fire = cal.nextDate(after: .now.addingTimeInterval(-1), matching: DateComponents(hour: 19, minute: 0, weekday: 1),
                                      matchingPolicy: .nextTime),
              let weekStart = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: fire)) else { return }

        let ctx = AppData.container.mainContext
        let activities = ((try? ctx.fetch(FetchDescriptor<Activity>())) ?? []).filter { $0.date >= weekStart }
        let sessions = ((try? ctx.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.start)]))) ?? []).filter { $0.end != nil }
        var prs = 0
        for (i, s) in sessions.enumerated() where s.start >= weekStart {
            prs += Progression.records(in: s.log, history: sessions[..<i].map(\.log)).count
        }
        prs += ((try? ctx.fetch(FetchDescriptor<PersonalRecord>())) ?? []).filter { $0.date >= weekStart }.count

        var lines: [String] = []
        if activities.isEmpty {
            lines.append("Nenhum treino nesta semana. Segunda é um ótimo dia para voltar 💪")
        } else {
            let minutes = activities.reduce(0) { $0 + $1.minutes }
            lines.append("\(activities.count) treino\(activities.count == 1 ? "" : "s") · \(durationText(minutes))" + (prs > 0 ? " · \(prs) PR\(prs == 1 ? "" : "s") 🏆" : ""))
        }

        // Posição em cada liga ativa
        let leagues = ((try? ctx.fetch(FetchDescriptor<League>())) ?? []).filter { !$0.isOver }
        if !leagues.isEmpty {
            let checkIns = (try? ctx.fetch(FetchDescriptor<LeagueCheckIn>())) ?? []
            let all = (try? ctx.fetch(FetchDescriptor<Activity>())) ?? []
            let byID = Dictionary(all.map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
            let avatar = MonsterForm(stage: .egg, attribute: nil)
            for l in leagues.prefix(2) {
                let feed = LeagueBoard.feed(league: l, mine: checkIns.filter { $0.leagueUUID == l.uuid }, activities: byID, me: trainer, myAvatar: avatar)
                let rank = LeagueBoard.ranking(feed: feed, league: l, me: trainer, myAvatar: avatar, since: nil)
                let pos = (rank.firstIndex { $0.isMe } ?? 0) + 1
                let days = l.end.map { cal.dateComponents([.day], from: cal.startOfDay(for: fire), to: cal.startOfDay(for: $0)).day ?? 0 }
                lines.append("\(l.emoji) \(pos)º de \(rank.count) na \(l.name)" + (days.map { $0 > 0 ? " · faltam \($0 + 1) dias" : " · último dia!" } ?? ""))
            }
        }

        let content = UNMutableNotificationContent()
        content.title = "Sua semana no GymBros"
        content.body = lines.joined(separator: "\n")
        content.sound = .default
        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
    }
}

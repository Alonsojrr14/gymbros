import Foundation

// Dicas por tela: um mini tutorial que aparece na primeira vez que a pessoa abre uma tela com mecânica pouco óbvia.
// O tutorial inicial (OnboardingStep.tour) explica o app; estas explicam a tela. O app Android usa o mesmo catálogo
// (ids e textos) e a mesma chave.

struct ScreenTipCard: Hashable {
    let title: String
    let text: String
    let symbol: String
}

struct ScreenTip: Identifiable, Hashable {
    /// Estável, em kebab-case: é o que fica gravado em `tipsSeen`. Não renomeie (quem já viu veria de novo).
    let id: String
    /// Nome da tela, no alto da folha
    let screen: String
    let cards: [ScreenTipCard]
}

/// Quais dicas a conta já viu.
/// Chave `tipsSeen` no UserDefaults: texto com os ids separados por vírgula, sem espaços, na ordem em que foram vistos
/// (ex.: "box,brobook,x1"). Está em `AccountData.userKeys`, então vai na cópia da conta (accountSettings) e vale em
/// todos os aparelhos e depois de reinstalar. Sem a chave ou vazia: nenhuma vista. "Pular" também conta como vista.
enum ScreenTips {
    static let key = "tipsSeen"

    /// Ids na ordem gravada, sem vazios nem repetidos (aceita espaços e vírgulas sobrando)
    static func parse(_ raw: String?) -> [String] {
        var seen = Set<String>()
        return (raw ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func encode(_ ids: [String]) -> String { parse(ids.joined(separator: ",")).joined(separator: ",") }

    static func seen(_ defaults: UserDefaults = .standard) -> Set<String> { Set(parse(defaults.string(forKey: key))) }

    static func hasSeen(_ id: String, _ defaults: UserDefaults = .standard) -> Bool { seen(defaults).contains(id) }

    static func markSeen(_ id: String, _ defaults: UserDefaults = .standard) {
        let list = parse(defaults.string(forKey: key))
        guard !list.contains(id) else { return }
        defaults.set(encode(list + [id]), forKey: key)
    }

    /// "Rever dicas das telas" nos Ajustes
    static func reset(_ defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }

    /// `blocked`: tutorial inicial ativo, outra dica na tela ou algo por cima
    static func shouldShow(_ tip: ScreenTip, blocked: Bool = false, _ defaults: UserDefaults = .standard) -> Bool {
        !blocked && !tip.cards.isEmpty && !hasSeen(tip.id, defaults)
    }
}

// MARK: - Catálogo

extension ScreenTip {
    static let box = ScreenTip(id: "box", screen: "Box", cards: [
        .init(title: "Sua Box", text: "Todos os seus bros ficam aqui. Toque num deles para ver a ficha com treinos, evoluções e X1; arraste para os lados para passar pelos outros.",
              symbol: "square.grid.3x3.fill"),
        .init(title: "O principal", text: "A estrela marca o principal: ele aparece na tela inicial e nos widgets e recebe o XP de todas as atividades. Troque pelo botão Principal na ficha.",
              symbol: "star.fill"),
        .init(title: "Bros das ligas", text: "O emoji no canto mostra a liga que o bro representa: ele leva 80% do XP dos check-ins dela. Ovos novos você adota ao entrar numa liga.",
              symbol: "flag.fill"),
        .init(title: "Trocas", text: "Em Trocar, você troca bros com amigos, 1 por 1. O bro vai com a forma e o XP dele.",
              symbol: "arrow.left.arrow.right"),
    ])

    static let brobook = ScreenTip(id: "brobook", screen: "BroBook", cards: [
        .init(title: "Todas as formas", text: "O BroBook mostra cada forma de cada espécie. Silhueta é forma que você ainda não encontrou: ela aparece quando um bro seu chega nela.",
              symbol: "book.closed.fill"),
        .init(title: "A espécie vem do ovo", text: "O ovo choca com 60 XP, e os treinos feitos nele decidem a espécie. Escolha uma espécie lá em cima para ver a árvore dela.",
              symbol: "sparkles"),
        .init(title: "O treino escolhe o galho", text: "Na fase Novato, o atributo mais treinado escolhe o Atleta; dois quase empatados viram um híbrido. Na fase Atleta, mudar de treino leva a uma Lenda de virada.",
              symbol: "arrow.triangle.branch"),
        .init(title: "Revelar todas", text: "Mostra as formas sem silhueta só para olhar, sem contar como descoberta. Toque numa forma para abrir a ficha dela.",
              symbol: "eye"),
    ])

    static let leagues = ScreenTip(id: "ligas", screen: "Ligas", cards: [
        .init(title: "Clube ou desafio", text: "Clube é um grupo permanente, com rankings da semana e do mês. Desafio tem data para começar, acabar e coroar um vencedor.",
              symbol: "trophy.fill"),
        .init(title: "Código da liga", text: "Crie uma liga e chame a galera pelo código dela, ou entre com o código que te passaram.",
              symbol: "ticket"),
        .init(title: "Um bro te representa", text: "Ao entrar, você escolhe um bro seu ou adota um ovo novo. Os check-ins da liga dão XP a ele, e o seu principal continua recebendo tudo.",
              symbol: "pawprint.fill"),
    ])

    static let leagueDetail = ScreenTip(id: "liga-detalhe", screen: "Liga", cards: [
        .init(title: "Check-in pontua", text: "Toque no + para postar um treino na liga. Conforme as regras, ele pode pedir foto ou passar pela revisão do dono antes de pontuar.",
              symbol: "plus.circle.fill"),
        .init(title: "Ranking", text: "Veja a liga toda, só esta semana ou este mês. As regras de pontuação ficam no fim dessa aba.",
              symbol: "chart.bar.fill"),
        .init(title: "Mural", text: "Recados para todo mundo da liga, cada um com o seu bro.",
              symbol: "bubble.left.and.bubble.right"),
        .init(title: "Mais opções", text: "No botão ··· ficam as notificações da liga e a saída. Quem cuida da liga também edita as regras e posta o treino do dia.",
              symbol: "ellipsis"),
    ])

    static let duels = ScreenTip(id: "x1", screen: "X1", cards: [
        .init(title: "Desafio de 24 h", text: "Desafie um amigo e escolha o que vale: XP, treinos, minutos, distância ou calorias. Aceito, conta tudo o que cada um registrar nas 24 h seguintes, inclusive do Apple Saúde.",
              symbol: "bolt.shield.fill"),
        .init(title: "Prazo para responder", text: "Quem foi desafiado tem 24 h para aceitar. Sem resposta, o desafio expira.",
              symbol: "clock"),
        .init(title: "Um bro luta por você", text: "Cada X1 leva um bro seu, e cada bro luta um X1 por vez. Ovos não lutam.",
              symbol: "pawprint.fill"),
        .init(title: "Fora das ligas", text: "O X1 não mexe no placar das ligas. Suas vitórias, empates e derrotas ficam no topo da tela.",
              symbol: "medal.fill"),
    ])

    static let trades = ScreenTip(id: "trocas", screen: "Trocas", cards: [
        .init(title: "1 por 1", text: "Escolha um bro de um amigo e ofereça um seu. Ele tem 48 h para aceitar ou recusar.",
              symbol: "arrow.left.arrow.right"),
        .init(title: "Vai com tudo", text: "O bro chega com a forma e o XP que tinha e segue evoluindo com os treinos do novo dono. Troca feita não se desfaz.",
              symbol: "sparkles"),
        .init(title: "Quem fica de fora", text: "Ovos, o seu principal, bros que representam uma liga e bros num X1 não entram em troca.",
              symbol: "lock.fill"),
        .init(title: "Receber", text: "Quando o amigo aceita, a troca aparece em Chegou para você: toque em Receber para buscar o bro.",
              symbol: "gift.fill"),
    ])

    static let feed = ScreenTip(id: "feed", screen: "Feed", cards: [
        .init(title: "Você e os amigos", text: "Aqui entram os seus posts e os dos seus amigos. Os amigos ficam no botão lá em cima, onde você adiciona gente pelo código ou QR.",
              symbol: "person.2.fill"),
        .init(title: "Toque duplo", text: "Dois toques na foto mandam força. Um toque abre o post com as reações e os comentários.",
              symbol: "hand.tap.fill"),
        .init(title: "Bolinhas no topo", text: "Cada bolinha é um amigo que postou nos últimos 3 dias; anel verde é novidade. Toque para ver um check-in por vez.",
              symbol: "rectangle.stack.fill"),
    ])

    static let deck = ScreenTip(id: "deck", screen: "Check-ins", cards: [
        .init(title: "Um por vez", text: "Arraste o cartão para o lado ou toque em Passar para ir ao próximo.",
              symbol: "hand.draw.fill"),
        .init(title: "Reaja", text: "Dois toques no cartão mandam força. Os emojis embaixo dele são outras reações.",
              symbol: "hand.tap.fill"),
        .init(title: "Responder", text: "Comente no check-in, que todo mundo da liga vê, ou mande uma mensagem direta, só entre amigos.",
              symbol: "arrowshape.turn.up.left"),
    ])

    static let map = ScreenTip(id: "mapa", screen: "Mapa", cards: [
        .init(title: "Lugares de treino", text: "Salve a academia ou o box em Adicionar. Ao começar musculação ou CrossFit, o app reconhece o lugar.",
              symbol: "dumbbell.fill"),
        .init(title: "Chegar e sair", text: "Na engrenagem, ligue o aviso ao chegar e o fim do treino ao sair. Com o app fechado, a localização precisa estar em Sempre.",
              symbol: "gearshape"),
        .init(title: "Ao ar livre", text: "Em Começar ao ar livre, o app grava o percurso pelo GPS. Os últimos percursos aparecem no mapa.",
              symbol: "figure.run"),
        .init(title: "Amigos agora", text: "Amigos que compartilham o treino ao vivo aparecem no mapa. Toque num deles para mandar força ou uma mensagem.",
              symbol: "mappin.and.ellipse"),
    ])

    static let workout = ScreenTip(id: "treino-guiado", screen: "Treino", cards: [
        .init(title: "Lista ou Guiado", text: "Na Lista você vê o treino inteiro. No Guiado, uma série por vez, com o que fez da última vez e o alvo de hoje.",
              symbol: "list.bullet"),
        .init(title: "Marque a série", text: "Marcou a série, o descanso começa sozinho. Toque no número da série para duplicar ou remover.",
              symbol: "checkmark.circle.fill"),
        .init(title: "Menu do exercício", text: "No botão ··· de cada exercício: tempo de descanso, superset com o próximo, calculadora de anilhas e troca de exercício.",
              symbol: "ellipsis"),
    ])

    static let wod = ScreenTip(id: "wod", screen: "WODs", cards: [
        .init(title: "Benchmarks", text: "Girls e Heróis são WODs clássicos. Abra um para ver os movimentos e começar com o cronômetro pronto; seu recorde fica guardado.",
              symbol: "flame.fill"),
        .init(title: "WOD livre", text: "Monte o seu em For Time, AMRAP, EMOM ou Tabata, com os movimentos que quiser.",
              symbol: "timer"),
        .init(title: "Treino do coach", text: "Cole o texto ou um print do treino: o app separa aquecimento, força e WOD e deixa tudo pronto em Treino.",
              symbol: "doc.on.clipboard"),
        .init(title: "Vira XP", text: "Cada WOD concluído vira uma atividade de CrossFit e dá XP ao seu bro.",
              symbol: "sparkles"),
    ])

    static let records = ScreenTip(id: "recordes", screen: "Meus PRs", cards: [
        .init(title: "Sessão de PR", text: "Registre carga e reps máximas de vários exercícios de uma vez. No primeiro treino de cada um, a carga sugerida já sai daqui.",
              symbol: "trophy.fill"),
        .init(title: "Melhores marcas", text: "Juntam os treinos do app e o que você registrou à mão. O 1RM é estimado pela fórmula de Epley, até 12 reps.",
              symbol: "chart.line.uptrend.xyaxis"),
    ])

    static let inbox = ScreenTip(id: "caixa-de-entrada", screen: "Caixa de entrada", cards: [
        .init(title: "Notificações", text: "Força, reações aos seus check-ins, convites para treinar e X1 chegam aqui. Dá para responder direto na linha.",
              symbol: "bell.badge.fill"),
        .init(title: "Mensagens", text: "Conversas só com amigos. Toque no lápis lá em cima para começar uma nova.",
              symbol: "envelope.fill"),
        .init(title: "Arquivar", text: "Arquive pelo menu da conversa. Ela volta sozinha quando chega mensagem nova.",
              symbol: "archivebox"),
    ])

    static let publicRoutines = ScreenTip(id: "rotinas-publicas", screen: "Rotinas públicas", cards: [
        .init(title: "Rotinas dos bros", text: "Curta e salve uma cópia das rotinas que a galera publicou. A cópia vira uma rotina sua, para mudar à vontade.",
              symbol: "person.2.fill"),
        .init(title: "Publique a sua", text: "Em Treino, abra o menu de uma rotina sua e toque em Publicar rotina.",
              symbol: "square.and.arrow.up"),
    ])

    static let body = ScreenTip(id: "peso-medidas", screen: "Peso e medidas", cards: [
        .init(title: "Registros", text: "Toque no + para registrar peso, medidas e fotos. O gráfico aparece a partir do segundo registro.",
              symbol: "scalemass.fill"),
        .init(title: "Apple Saúde", text: "Traga o peso que já está no Apple Saúde pelo botão logo abaixo do gráfico.",
              symbol: "heart"),
        .init(title: "Antes e depois", text: "Com duas fotos, compare arrastando a divisória. As fotos ficam só neste aparelho.",
              symbol: "photo.on.rectangle"),
    ])

    static let all: [ScreenTip] = [box, brobook, leagues, leagueDetail, duels, trades, feed, deck, map, workout, wod, records, inbox,
                                   publicRoutines, body]
}

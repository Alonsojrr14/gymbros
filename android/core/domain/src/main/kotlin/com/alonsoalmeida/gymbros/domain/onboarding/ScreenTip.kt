package com.alonsoalmeida.gymbros.domain.onboarding

/**
 * Dicas por tela (Onboarding/ScreenTip.swift): um mini tutorial na primeira vez que a pessoa abre uma tela com mecânica
 * pouco óbvia. Mesmos ids e textos do iPhone; onde o Android funciona diferente, só o cartão afetado muda.
 * `symbol` é o SF Symbol do iOS: o app troca pelo ícone Material equivalente.
 */
data class ScreenTipCard(val title: String, val text: String, val symbol: String)

data class ScreenTip(
    /** Estável, em kebab-case: é o que fica gravado em `tipsSeen`. Não renomeie (quem já viu veria de novo). */
    val id: String,
    /** Nome da tela, no alto da folha */
    val screen: String,
    val cards: List<ScreenTipCard>,
) {
    companion object {
        val BOX = ScreenTip("box", "Box", listOf(
            ScreenTipCard("Sua Box", "Todos os seus bros ficam aqui. Toque num deles para ver a ficha com treinos, evoluções e X1; arraste para os lados para passar pelos outros.",
                          "square.grid.3x3.fill"),
            ScreenTipCard("O principal", "A estrela marca o principal: ele aparece na tela inicial e nos widgets e recebe o XP de todas as atividades. Troque pelo botão Principal na ficha.",
                          "star.fill"),
            ScreenTipCard("Bros das ligas", "O emoji no canto mostra a liga que o bro representa: ele leva 80% do XP dos check-ins dela. Ovos novos você adota ao entrar numa liga.",
                          "flag.fill"),
            ScreenTipCard("Trocas", "Em Trocar, você troca bros com amigos, 1 por 1. O bro vai com a forma e o XP dele.",
                          "arrow.left.arrow.right"),
        ))

        val BROBOOK = ScreenTip("brobook", "BroBook", listOf(
            ScreenTipCard("Todas as formas", "O BroBook mostra cada forma de cada espécie. Silhueta é forma que você ainda não encontrou: ela aparece quando um bro seu chega nela.",
                          "book.closed.fill"),
            ScreenTipCard("A espécie vem do ovo", "O ovo choca com 60 XP, e os treinos feitos nele decidem a espécie. Escolha uma espécie lá em cima para ver a árvore dela.",
                          "sparkles"),
            ScreenTipCard("O treino escolhe o galho", "Na fase Novato, o atributo mais treinado escolhe o Atleta; dois quase empatados viram um híbrido. Na fase Atleta, mudar de treino leva a uma Lenda de virada.",
                          "arrow.triangle.branch"),
            ScreenTipCard("Revelar todas", "Mostra as formas sem silhueta só para olhar, sem contar como descoberta. Toque numa forma para abrir a ficha dela.",
                          "eye"),
        ))

        val LEAGUES = ScreenTip("ligas", "Ligas", listOf(
            ScreenTipCard("Clube ou desafio", "Clube é um grupo permanente, com rankings da semana e do mês. Desafio tem data para começar, acabar e coroar um vencedor.",
                          "trophy.fill"),
            ScreenTipCard("Código da liga", "Crie uma liga e chame a galera pelo código dela, ou entre com o código que te passaram.",
                          "ticket"),
            ScreenTipCard("Um bro te representa", "Ao entrar, você escolhe um bro seu ou adota um ovo novo. Os check-ins da liga dão XP a ele, e o seu principal continua recebendo tudo.",
                          "pawprint.fill"),
        ))

        val LEAGUE_DETAIL = ScreenTip("liga-detalhe", "Liga", listOf(
            ScreenTipCard("Check-in pontua", "Toque no + para postar um treino na liga. Conforme as regras, ele pode pedir foto ou passar pela revisão do dono antes de pontuar.",
                          "plus.circle.fill"),
            ScreenTipCard("Ranking", "Veja a liga toda, só esta semana ou este mês. As regras de pontuação ficam no fim dessa aba.",
                          "chart.bar.fill"),
            ScreenTipCard("Mural", "Recados para todo mundo da liga, cada um com o seu bro.",
                          "bubble.left.and.bubble.right"),
            ScreenTipCard("Mais opções", "No botão ··· ficam as notificações da liga e a saída. Quem cuida da liga também edita as regras e posta o treino do dia.",
                          "ellipsis"),
        ))

        val DUELS = ScreenTip("x1", "X1", listOf(
            ScreenTipCard("Desafio de 24 h", "Desafie um amigo e escolha o que vale: XP, treinos, minutos, distância ou calorias. Aceito, conta tudo o que cada um registrar nas 24 h seguintes, inclusive do Health Connect.",
                          "bolt.shield.fill"),
            ScreenTipCard("Prazo para responder", "Quem foi desafiado tem 24 h para aceitar. Sem resposta, o desafio expira.",
                          "clock"),
            ScreenTipCard("Um bro luta por você", "Cada X1 leva um bro seu, e cada bro luta um X1 por vez. Ovos não lutam.",
                          "pawprint.fill"),
            ScreenTipCard("Fora das ligas", "O X1 não mexe no placar das ligas. Suas vitórias, empates e derrotas ficam no topo da tela.",
                          "medal.fill"),
        ))

        val TRADES = ScreenTip("trocas", "Trocas", listOf(
            ScreenTipCard("1 por 1", "Escolha um bro de um amigo e ofereça um seu. Ele tem 48 h para aceitar ou recusar.",
                          "arrow.left.arrow.right"),
            ScreenTipCard("Vai com tudo", "O bro chega com a forma e o XP que tinha e segue evoluindo com os treinos do novo dono. Troca feita não se desfaz.",
                          "sparkles"),
            ScreenTipCard("Quem fica de fora", "Ovos, o seu principal, bros que representam uma liga e bros num X1 não entram em troca.",
                          "lock.fill"),
            ScreenTipCard("Receber", "Quando o amigo aceita, a troca aparece em Chegou para você: toque em Receber para buscar o bro.",
                          "gift.fill"),
        ))

        val FEED = ScreenTip("feed", "Feed", listOf(
            ScreenTipCard("Você e os amigos", "Aqui entram os seus posts e os dos seus amigos. Os amigos ficam no botão lá em cima, onde você adiciona gente pelo código ou QR.",
                          "person.2.fill"),
            ScreenTipCard("Toque duplo", "Dois toques na foto mandam força. Um toque abre o post com as reações e os comentários.",
                          "hand.tap.fill"),
            ScreenTipCard("Bolinhas no topo", "Cada bolinha é um amigo que postou nos últimos 3 dias; anel verde é novidade. Toque para ver um check-in por vez.",
                          "rectangle.stack.fill"),
        ))

        val DECK = ScreenTip("deck", "Check-ins", listOf(
            ScreenTipCard("Um por vez", "Arraste o cartão para o lado ou toque em Passar para ir ao próximo.",
                          "hand.draw.fill"),
            ScreenTipCard("Reaja", "Dois toques no cartão mandam força. Os emojis embaixo dele são outras reações.",
                          "hand.tap.fill"),
            ScreenTipCard("Responder", "Comente no check-in, que todo mundo da liga vê, ou mande uma mensagem direta, só entre amigos.",
                          "arrowshape.turn.up.left"),
        ))

        val MAP = ScreenTip("mapa", "Mapa", listOf(
            ScreenTipCard("Lugares de treino", "Salve a academia ou o box em Adicionar. Ao começar musculação ou CrossFit, o app reconhece o lugar.",
                          "dumbbell.fill"),
            ScreenTipCard("Chegar e sair", "Na engrenagem, ligue o aviso ao chegar e o fim do treino ao sair. Com o app fechado, a localização precisa estar em Permitir o tempo todo.",
                          "gearshape"),
            ScreenTipCard("Ao ar livre", "Em Começar ao ar livre, o app grava o percurso pelo GPS. Os últimos percursos aparecem no mapa.",
                          "figure.run"),
            ScreenTipCard("Amigos agora", "Amigos que compartilham o treino ao vivo aparecem no mapa. Toque num deles para mandar força ou uma mensagem.",
                          "mappin.and.ellipse"),
        ))

        val WORKOUT = ScreenTip("treino-guiado", "Treino", listOf(
            ScreenTipCard("Lista ou Guiado", "Na Lista você vê o treino inteiro. No Guiado, uma série por vez, com o que fez da última vez e o alvo de hoje.",
                          "list.bullet"),
            ScreenTipCard("Marque a série", "Marcou a série, o descanso começa sozinho. Toque no número da série para duplicar ou remover.",
                          "checkmark.circle.fill"),
            ScreenTipCard("Menu do exercício", "No botão ··· de cada exercício: tempo de descanso, superset com o próximo, calculadora de anilhas e troca de exercício.",
                          "ellipsis"),
        ))

        val WOD = ScreenTip("wod", "WODs", listOf(
            ScreenTipCard("Benchmarks", "Girls e Heróis são WODs clássicos. Abra um para ver os movimentos e começar com o cronômetro pronto; seu recorde fica guardado.",
                          "flame.fill"),
            ScreenTipCard("WOD livre", "Monte o seu em For Time, AMRAP, EMOM ou Tabata, com os movimentos que quiser.",
                          "timer"),
            ScreenTipCard("Treino do coach", "Cole ou digite o texto do treino: o app separa aquecimento, força e WOD e deixa tudo pronto em Treino.",
                          "doc.on.clipboard"),
            ScreenTipCard("Vira XP", "Cada WOD concluído vira uma atividade de CrossFit e dá XP ao seu bro.",
                          "sparkles"),
        ))

        val RECORDS = ScreenTip("recordes", "Meus PRs", listOf(
            ScreenTipCard("Sessão de PR", "Registre carga e reps máximas de vários exercícios de uma vez. No primeiro treino de cada um, a carga sugerida já sai daqui.",
                          "trophy.fill"),
            ScreenTipCard("Melhores marcas", "Juntam os treinos do app e o que você registrou à mão. O 1RM é estimado pela fórmula de Epley, até 12 reps.",
                          "chart.line.uptrend.xyaxis"),
        ))

        val INBOX = ScreenTip("caixa-de-entrada", "Caixa de entrada", listOf(
            ScreenTipCard("Notificações", "Força, reações aos seus check-ins, convites para treinar e pedidos de amizade chegam aqui. Dá para responder direto na linha.",
                          "bell.badge.fill"),
            ScreenTipCard("Mensagens", "Conversas só com amigos. Toque no lápis lá em cima para começar uma nova.",
                          "envelope.fill"),
            ScreenTipCard("Arquivar", "Arquive pelo menu da conversa. Ela volta sozinha quando chega mensagem nova.",
                          "archivebox"),
        ))

        val PUBLIC_ROUTINES = ScreenTip("rotinas-publicas", "Rotinas públicas", listOf(
            ScreenTipCard("Rotinas dos bros", "Curta e salve uma cópia das rotinas que a galera publicou. A cópia vira uma rotina sua, para mudar à vontade.",
                          "person.2.fill"),
            ScreenTipCard("Publique a sua", "Em Treino, abra o menu de uma rotina sua e toque em Publicar rotina.",
                          "square.and.arrow.up"),
        ))

        val BODY = ScreenTip("peso-medidas", "Peso e medidas", listOf(
            ScreenTipCard("Registros", "Toque no + para registrar peso e medidas. O gráfico aparece a partir do segundo registro.",
                          "scalemass.fill"),
            ScreenTipCard("Health Connect", "Traga o peso que já está no Health Connect pelo botão logo abaixo do gráfico.",
                          "heart"),
            ScreenTipCard("Medidas", "Toque numa medida com mais de um registro para ver como ela mudou no gráfico.",
                          "chart.line.uptrend.xyaxis"),
        ))

        val ALL: List<ScreenTip> = listOf(BOX, BROBOOK, LEAGUES, LEAGUE_DETAIL, DUELS, TRADES, FEED, DECK, MAP, WORKOUT, WOD, RECORDS, INBOX,
                                          PUBLIC_ROUTINES, BODY)
    }
}

/**
 * Quais dicas a conta já viu. Chave `tipsSeen` nos ajustes da conta (plist `accountSettings`, `AccountData.userKeys` do
 * iOS): texto com os ids separados por vírgula, sem espaços, na ordem em que foram vistos (ex.: "box,brobook,x1"). Vale
 * no iPhone e no Android. Sem a chave ou vazia: nenhuma vista. "Pular" também conta como vista.
 */
object ScreenTips {
    const val KEY = "tipsSeen"

    /** Ids na ordem gravada, sem vazios nem repetidos (aceita espaços e vírgulas sobrando) */
    fun parse(raw: String?): List<String> =
        raw.orEmpty().split(",").map { it.trim() }.filter { it.isNotEmpty() }.distinct()

    fun encode(ids: List<String>): String = parse(ids.joinToString(",")).joinToString(",")

    fun seen(settings: Map<String, Any?>): Set<String> = parse(settings[KEY] as? String).toSet()

    fun hasSeen(id: String, settings: Map<String, Any?>): Boolean = id in seen(settings)

    /** Novo valor de `tipsSeen` com o id no fim; null quando já estava lá (nada a gravar). Ids desconhecidos ficam. */
    fun markSeen(id: String, raw: String?): String? {
        val list = parse(raw)
        return if (id in list) null else encode(list + id)
    }

    /** `blocked`: outra dica na tela ou algo por cima */
    fun shouldShow(tip: ScreenTip, settings: Map<String, Any?>, blocked: Boolean = false): Boolean =
        !blocked && tip.cards.isNotEmpty() && !hasSeen(tip.id, settings)
}

// Termos bloqueados pelo ContentFilter. Um termo por linha, em minúsculas; acento, maiúsculas e trocas
// como @→a, 0→o e 1→i não importam (o filtro normaliza). Vale só a palavra inteira; termina com `*` para
// pegar também o que começa com ele (ex.: "fuck*" pega "fucking"). Termos com espaço casam a frase.
// Antes de pôr um `*`, confira se nenhuma palavra comum começa com o termo.

enum BlockedTerms {
    static let portuguese = [
        "porra", "caralho*", "merda", "merdas", "cu", "cuzao", "cuzinho", "puta", "putas", "putinha", "putaria",
        "fdp", "vsf", "vtnc", "tnc", "pqp", "foder", "fodase", "foda-se", "fodido", "fodida",
        "buceta*", "boceta*", "xoxota*", "piroca*", "punheta*", "vagabunda", "vagabundas",
        "viado", "viados", "viadinho", "sapatao", "traveco", "crioulo", "crioula",
        "retardado", "retardada", "otario", "otaria", "babaca", "imbecil", "corno",
        "vai se matar", "se mata logo",
    ]

    static let english = [
        "fuck*", "motherfuck*", "shit", "shits", "shitty", "bullshit", "bitch*", "cunt*", "whore*", "slut*",
        "asshole*", "dickhead*", "nigger*", "nigga*", "faggot*", "fag", "fags", "retard", "retarded",
        "kys", "kill yourself", "kill urself",
    ]

    static let all = portuguese + english
}

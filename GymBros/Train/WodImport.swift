import PhotosUI
import SwiftData
import SwiftUI
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

// Treino do coach: o texto (colado de uma mensagem ou lido de um print) vira um WOD agendado para o dia,
// que aparece em Treino → Hoje e no aviso de chegada ao box. Tudo no aparelho.

/// Parte do treino que não é cronometrada (aquecimento, força, skill…)
struct WodPart: Codable, Hashable {
    var title: String
    var lines: [String]
}

struct PlannedWod: Codable, Identifiable, Hashable {
    var id = UUID()
    var day: Date
    var name: String
    var format: WodFormat
    var lines: [String]
    var parts: [WodPart] = []

    var wodID: String { "coach-" + id.uuidString }
    var wod: Wod { Wod(id: wodID, name: name, category: "Coach", format: format, lines: lines) }
}

/// WODs agendados, em `UserDefaults` (poucos itens; os mais velhos que 14 dias saem sozinhos)
enum WodPlan {
    static let key = "plannedWods"

    static func all(_ raw: String? = UserDefaults.standard.string(forKey: key)) -> [PlannedWod] {
        guard let data = raw?.data(using: .utf8) else { return [] }
        return ((try? JSONDecoder().decode([PlannedWod].self, from: data)) ?? []).sorted { $0.day < $1.day }
    }

    static func save(_ p: PlannedWod) {
        var list = all().filter { $0.id != p.id }
        list.append(p)
        store(list)
    }

    static func delete(_ p: PlannedWod) { store(all().filter { $0.id != p.id }) }

    private static func store(_ list: [PlannedWod]) {
        let limit = Calendar.current.date(byAdding: .day, value: -14, to: Calendar.current.startOfDay(for: .now))!
        let kept = list.filter { $0.day >= limit }
        UserDefaults.standard.set(String(data: (try? JSONEncoder().encode(kept)) ?? Data(), encoding: .utf8), forKey: key)
    }

    /// WOD de um dia que ainda não tem resultado salvo
    static func pending(on day: Date = .now, raw: String? = UserDefaults.standard.string(forKey: key), done: Set<String>) -> PlannedWod? {
        all(raw).first { Calendar.current.isDate($0.day, inSameDayAs: day) && !done.contains($0.wodID) }
    }

    @MainActor
    static func pendingToday() -> PlannedWod? {
        let ids = ((try? AppData.container.mainContext.fetch(FetchDescriptor<WodResult>())) ?? []).map(\.wodID)
        return pending(done: Set(ids))
    }
}

// MARK: - Leitura do texto

struct WodDraft: Equatable {
    var name = "WOD do coach"
    var format: WodFormat = .forTime(capMinutes: nil)
    var lines: [String] = []
    var parts: [WodPart] = []
    /// Nenhum formato apareceu no texto: For Time sem limite é só um palpite
    var guessed = true
}

enum WodParser {
    private enum Kind { case warmup, skill, strength, wod, extra }

    private static let headers: [(Kind, String, [String])] = [
        (.warmup, "Aquecimento", ["aquecimento", "warm up", "warm-up", "warmup", "mobilidade", "mobility", "ativação", "ativacao"]),
        (.skill, "Skill", ["skill", "técnica", "tecnica", "habilidade", "gymnastics", "ginástica", "ginastica"]),
        (.strength, "Força", ["força", "forca", "strength", "lpo", "weightlifting", "levantamento olímpico", "levantamento olimpico"]),
        (.wod, "WOD", ["wod", "metcon", "conditioning", "condicionamento"]),
        (.extra, "Extra", ["acessório", "acessórios", "acessorio", "acessorios", "accessory", "core", "cooldown", "cool down",
                           "alongamento", "finisher", "volta à calma", "volta a calma"]),
    ]

    static func parse(_ text: String) -> WodDraft {
        let lines = text.components(separatedBy: .newlines).map(clean).filter { !$0.isEmpty }
        var sections: [(kind: Kind?, title: String, lines: [String])] = [(nil, "", [])]
        for line in lines {
            if let (kind, title, rest) = header(line) {
                sections.append((kind, title, rest.isEmpty ? [] : [rest]))
            } else {
                sections[sections.count - 1].lines.append(line)
            }
        }
        sections.removeAll { $0.kind == nil && $0.lines.isEmpty }

        let hasHeaders = sections.contains { $0.kind != nil }
        let wodIndex = sections.lastIndex { $0.kind == .wod }
            ?? sections.lastIndex { $0.lines.contains { format(in: $0) != nil } }
            ?? (hasHeaders ? sections.lastIndex { $0.kind != nil } : sections.indices.last)

        var draft = WodDraft()
        guard let wodIndex else { return draft }
        let wodLines = sections[wodIndex].lines
        if let found = wodLines.lazy.compactMap(format(in:)).first {
            draft.format = found
            draft.guessed = false
            // "For time" numa linha e "Cap: 15'" na outra
            if case .forTime(nil) = found, let c = wodLines.lazy.compactMap(cap(in:)).first { draft.format = .forTime(capMinutes: c) }
        }
        draft.lines = wodLines.filter { !isOnlyFormat($0) }
        // Antes do primeiro título costuma vir "Treino de sexta 17/10" ou o nome do box: não é parte do treino
        draft.parts = sections.enumerated().compactMap { i, s in
            i == wodIndex || s.kind == nil || s.lines.isEmpty ? nil : WodPart(title: s.title, lines: s.lines)
        }
        return draft
    }

    /// Tira negrito/itálico de mensagem (*, _, ~), emojis, marcadores de lista e espaços repetidos
    static func clean(_ line: String) -> String {
        let scalars = line.unicodeScalars.filter { s in
            !(s.properties.isEmojiPresentation || (s.properties.isEmoji && s.value > 0x2000 && !(0x2018...0x201F).contains(s.value)))
                && s.value != 0xFE0F && s.value != 0x200D
        }
        var s = String(String.UnicodeScalarView(scalars))
        s = s.replacingOccurrences(of: "[*_~`]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "^\\s*[-•▪◦>·]+\\s*", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// "AQUECIMENTO", "B) Força:", "WOD: AMRAP 15'" (o que vem depois dos dois-pontos fica como linha)
    private static func header(_ line: String) -> (Kind, String, String)? {
        let stripped = line.replacingOccurrences(of: "^([a-zA-Z0-9][).]|parte \\d+)\\s*", with: "", options: [.regularExpression, .caseInsensitive])
        let lower = stripped.lowercased()
        for (kind, title, words) in headers {
            for w in words where lower.hasPrefix(w) {
                let rest = stripped.dropFirst(w.count)
                guard rest.isEmpty || !(rest.first!.isLetter) else { continue }
                let tail = rest.trimmingCharacters(in: CharacterSet(charactersIn: " :-–—|"))
                // "Core: 3x20 abdominais" é título com conteúdo; "Força total no agachamento" não é título
                if tail.isEmpty || rest.trimmingCharacters(in: .whitespaces).first.map({ ":-–—|".contains($0) }) == true || format(in: tail) != nil {
                    return (kind, title, tail)
                }
            }
        }
        return nil
    }

    private static func match(_ pattern: String, _ text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: text).map { String(text[$0]) } ?? "" }
    }

    private static let minutes = "(\\d{1,3})\\s*(?:'|’|min\\b|minutos|minutes)?"

    static func format(in line: String) -> WodFormat? {
        if let m = match("\\bamrap\\s*(?:de|in|em|:|-)?\\s*" + minutes, line) ?? match("\\b" + minutes + "\\s*(?:de\\s*)?amrap\\b", line),
           let n = Int(m[1]), (1...90).contains(n) {
            return .amrap(minutes: n)
        }
        if let m = match("\\be\\d?mom\\s*(?:de|x|:|-)?\\s*" + minutes, line) ?? match("\\b" + minutes + "\\s*(?:de\\s*)?e\\d?mom\\b", line),
           let n = Int(m[1]), (1...90).contains(n) {
            return .emom(minutes: n)
        }
        if match("\\btabata\\b", line) != nil {
            let rounds = match("(\\d{1,2})\\s*(?:x|rounds?|rodadas?)", line).flatMap { Int($0[1]) }.flatMap { (1...20).contains($0) ? $0 : nil }
            return .tabata(rounds: rounds ?? 8)
        }
        if match("\\bfor\\s*time\\b|\\bft\\b|\\bpor\\s*tempo\\b", line) != nil || cap(in: line) != nil {
            return .forTime(capMinutes: cap(in: line))
        }
        return nil
    }

    private static func cap(in line: String) -> Int? {
        match("\\b(?:tc|time\\s*cap|cap)\\s*(?:de|:|=|-)?\\s*" + minutes, line).flatMap { Int($0[1]) }.flatMap { (1...90).contains($0) ? $0 : nil }
    }

    /// "AMRAP 20'", "For Time (TC 12 min)": só o formato, sem movimento
    private static func isOnlyFormat(_ line: String) -> Bool {
        guard format(in: line) != nil else { return false }
        let rest = line.lowercased().replacingOccurrences(
            of: "amrap|e\\d?mom|tabata|for\\s*time|\\bft\\b|por\\s*tempo|time\\s*cap|\\btc\\b|\\bcap\\b|min(?:utos|utes)?\\b|\\bde\\b|\\bem\\b|\\bin\\b|[0-9'’():=\\-–—.,\\s]",
            with: "", options: .regularExpression)
        return rest.isEmpty
    }
}

// MARK: - Print (Vision) e modelo do aparelho

enum WodOCR {
    /// Texto de um print ou foto, de cima para baixo; horários soltos de mensagens ("10:32") saem
    static func text(from image: UIImage) async throws -> String {
        guard let cg = image.cgImage else { return "" }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["pt-BR", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .filter { $0.range(of: "^\\d{1,2}:\\d{2}$", options: .regularExpression) == nil }
                .joined(separator: "\n")
        }.value
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@Generable
struct AIWod {
    @Guide(description: "Formato do WOD principal: amrap, emom, tabata ou fortime")
    var formato: String
    @Guide(description: "Minutos do AMRAP ou do EMOM, ou o time cap do For Time; 0 se não houver")
    var minutos: Int
    @Guide(description: "Rodadas do Tabata; 0 se não for Tabata")
    var rodadas: Int
    @Guide(description: "Movimentos do WOD principal, um por item, como estão no texto (repetições e cargas incluídas)")
    var movimentos: [String]
    @Guide(description: "Outras partes do treino (aquecimento, força, skill, acessórios), na ordem do texto")
    var partes: [AIPart]
}

@available(iOS 26.0, *)
@Generable
struct AIPart {
    @Guide(description: "Título curto: Aquecimento, Força, Skill ou Extra")
    var titulo: String
    var linhas: [String]
}
#endif

enum WodAI {
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    /// Lê textos bagunçados com o modelo do próprio aparelho (Apple Intelligence); nil se não der
    static func parse(_ text: String) async -> WodDraft? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            let session = LanguageModelSession(instructions: """
                Você recebe o treino de CrossFit que o coach mandou e separa o WOD principal \
                (a parte cronometrada) das outras partes. Não invente movimentos: copie do texto.
                """)
            guard let ai = try? await session.respond(to: text, generating: AIWod.self).content, !ai.movimentos.isEmpty else { return nil }
            var d = WodDraft()
            let n = ai.minutos > 0 ? min(ai.minutos, 90) : nil
            switch ai.formato.lowercased().filter(\.isLetter) {
            case "amrap": d.format = .amrap(minutes: n ?? 12)
            case "emom": d.format = .emom(minutes: n ?? 10)
            case "tabata": d.format = .tabata(rounds: ai.rodadas > 0 ? min(ai.rodadas, 20) : 8)
            default: d.format = .forTime(capMinutes: n)
            }
            d.guessed = false
            d.lines = ai.movimentos.map(WodParser.clean).filter { !$0.isEmpty }
            d.parts = ai.partes.map { WodPart(title: $0.titulo, lines: $0.linhas.map(WodParser.clean).filter { !$0.isEmpty }) }.filter { !$0.lines.isEmpty }
            return d
        }
        #endif
        return nil
    }
}

// MARK: - Telas

/// Colar o texto ou escolher o print, conferir e agendar
struct ImportWodView: View {
    var editing: PlannedWod?
    @Environment(\.dismiss) private var dismiss
    @State private var raw = ""
    @State private var photo: PhotosPickerItem?
    @State private var reading = false
    @State private var error: String?
    @State private var reviewing = false
    @State private var name = "WOD do coach"
    @State private var day = Date.now
    @State private var kind = 0
    @State private var minutes = 12
    @State private var rounds = 8
    @State private var linesText = ""
    @State private var parts: [WodPart] = []
    @State private var guessed = false
    @State private var start: Wod?
    /// 0 hoje, 1 amanhã, 2 outro dia (calendário)
    @State private var dayChoice = 0

    var body: some View {
        GMModal(editing == nil ? "Treino do coach" : "Editar treino", confirm: reviewing ? "Salvar" : nil, confirmEnabled: !lines.isEmpty,
                onConfirm: { save(); dismiss() }) {
            if reviewing { review } else { input }
        }
        .overlay { if reading { readingOverlay } }
        .animation(.snappy, value: reviewing)
        .onChange(of: photo) { _, item in if let item { Task { await read(item) } } }
        .onChange(of: dayChoice) { _, c in
            if c < 2 { day = Calendar.current.date(byAdding: .day, value: c, to: Calendar.current.startOfDay(for: .now))! }
        }
        .onAppear { if let editing { load(editing) } }
        .gmModal(item: $start) { WodTimerView(wod: $0) }
    }

    // MARK: Entrada

    @ViewBuilder
    private var input: some View {
        VStack(spacing: 10) {
            Image(systemName: "flame.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.streak)
                .frame(width: 68, height: 68)
                .background(Theme.streak.opacity(0.15), in: .circle)
            Text("Traga o treino do coach").gmFont(24, weight: .bold, design: .rounded, relativeTo: .title2)
            Text("O app separa aquecimento, força e WOD e deixa o cronômetro pronto para quando você chegar no box.")
                .font(.subheadline).foregroundStyle(Theme.dim).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)

        HStack(spacing: 12) {
            PhotosPicker(selection: $photo, matching: .screenshots) {
                sourceTile(icon: "text.viewfinder", title: "Print", subtitle: "Captura de tela")
            }
            PhotosPicker(selection: $photo, matching: .images) {
                sourceTile(icon: "photo.on.rectangle", title: "Foto", subtitle: "Ex.: quadro do box")
            }
        }
        .buttonStyle(GMPress())

        GMCard {
            HStack(spacing: 12) {
                Image(systemName: "doc.on.clipboard").font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Texto copiado").font(.headline)
                    Text("Copie a mensagem do coach e cole aqui").font(.caption).foregroundStyle(Theme.dim)
                }
                Spacer()
                PasteButton(payloadType: String.self) { strings in
                    guard let text = strings.first else { return }
                    Task { @MainActor in
                        raw = text
                        await interpret()
                    }
                }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .tint(Theme.accent)
            }
        }

        HStack {
            Rectangle().fill(Theme.stroke).frame(height: 1)
            Text("ou digite").font(.caption).foregroundStyle(Theme.dim)
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }

        WodTextEditor(text: $raw, placeholder: "AQUECIMENTO\n3 rounds: 10 air squats\n\nWOD\nAMRAP 15'\n10 wall balls\n10 burpees", minHeight: 170)
        Label("Títulos como AQUECIMENTO, FORÇA e WOD separam as partes.", systemImage: "lightbulb")
            .font(.caption).foregroundStyle(Theme.dim)

        if let error { notice(error, icon: "exclamationmark.circle.fill", tint: Theme.danger) }

        GMButton("Ler treino", icon: "wand.and.stars", enabled: !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !reading) {
            Task { await interpret() }
        }
    }

    private func sourceTile(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(subtitle).font(.caption).foregroundStyle(Theme.dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.card, in: .rect(cornerRadius: Theme.radius))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Escolher uma imagem do treino")
    }

    private var readingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large).tint(Theme.accent)
                Text("Lendo o treino…").font(.subheadline.weight(.semibold))
            }
            .padding(24)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: Theme.radius))
        }
        .transition(.opacity)
    }

    private func notice(_ text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.12), in: .rect(cornerRadius: Theme.radiusM))
    }

    // MARK: Conferência

    @ViewBuilder
    private var review: some View {
        GMCard {
            HStack(spacing: 14) {
                Image(systemName: "flame.fill")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.streak)
                    .frame(width: 52, height: 52)
                    .background(Theme.streak.opacity(0.15), in: .rect(cornerRadius: Theme.radiusL))
                VStack(alignment: .leading, spacing: 4) {
                    TextField("", text: $name, prompt: Text("Nome do treino").foregroundStyle(Theme.dim))
                        .font(.title3.bold())
                        .textInputAutocapitalization(.words)
                    Text("\(format.name) · \(lines.count) \(lines.count == 1 ? "movimento" : "movimentos")")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                }
                Image(systemName: "pencil").font(.caption).foregroundStyle(Theme.dim)
            }
        }

        if guessed { notice("Não achei o formato no texto: confira abaixo.", icon: "exclamationmark.triangle.fill", tint: Theme.warning) }

        GMSection("Quando") {
            GMChoiceChips(options: [(0, "Hoje"), (1, "Amanhã"), (2, "Outro dia")], selection: $dayChoice)
            if dayChoice == 2 {
                GMDivider()
                GMDateField(date: $day, limitToNow: false, title: "Dia")
            }
        }

        GMSection("Formato") {
            GMChoiceChips(options: [(0, "For Time"), (1, "AMRAP"), (2, "EMOM"), (3, "Tabata")], selection: $kind)
            GMDivider()
            if kind == 3 {
                GMStepper(title: "Rodadas", value: $rounds, range: 1...20)
            } else {
                GMStepper(title: kind == 0 ? "Time cap" : "Duração", value: $minutes, range: kind == 0 ? 0...90 : 1...90,
                          format: { kind == 0 && $0 == 0 ? "Sem limite" : "\($0) min" })
            }
        }

        GMSection("WOD", footer: "Um movimento por linha; é o que aparece no cronômetro.") {
            WodTextEditor(text: $linesText, placeholder: "10 wall balls\n10 burpees", minHeight: 120)
        }

        ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
            GMCard {
                HStack {
                    Text(part.title.uppercased()).font(.caption.bold()).foregroundStyle(Theme.dim)
                    Spacer()
                    GMIconButton(icon: "trash", size: 28, label: "Tirar \(part.title)") {
                        withAnimation(.snappy) { _ = parts.remove(at: i) }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(part.lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Theme.accent).frame(width: 5, height: 5)
                            Text(line).font(.subheadline)
                        }
                    }
                }
            }
        }

        VStack(spacing: 6) {
            if Calendar.current.isDateInToday(day) {
                GMButton("Salvar e começar agora", icon: "play.fill", enabled: !lines.isEmpty) { start = save().wod }
            } else {
                GMButton("Agendar para \(PlannedWodView.dayText(day).prefix(1).lowercased() + PlannedWodView.dayText(day).dropFirst())", icon: "calendar.badge.plus", enabled: !lines.isEmpty) {
                    save()
                    dismiss()
                }
            }
            if editing == nil {
                GMTextButton(title: "Usar outro texto", icon: "arrow.uturn.backward") { reviewing = false }
            }
        }
        .padding(.top, 4)
    }

    private var lines: [String] {
        linesText.components(separatedBy: .newlines).map(WodParser.clean).filter { !$0.isEmpty }
    }

    private var format: WodFormat {
        switch kind {
        case 0: .forTime(capMinutes: minutes > 0 ? minutes : nil)
        case 1: .amrap(minutes: minutes)
        case 2: .emom(minutes: minutes)
        default: .tabata(rounds: rounds)
        }
    }

    @discardableResult
    private func save() -> PlannedWod {
        var p = editing ?? PlannedWod(day: day, name: name, format: format, lines: lines)
        p.day = Calendar.current.startOfDay(for: day)
        p.name = name.trimmingCharacters(in: .whitespaces).isEmpty ? "WOD do coach" : name.trimmingCharacters(in: .whitespaces)
        p.format = format
        p.lines = lines
        p.parts = parts
        WodPlan.save(p)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return p
    }

    private func load(_ p: PlannedWod) {
        name = p.name
        let offset = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: p.day).day ?? 2
        dayChoice = (0...1).contains(offset) ? offset : 2
        day = p.day
        apply(p.format)
        linesText = p.lines.joined(separator: "\n")
        parts = p.parts
        reviewing = true
    }

    private func apply(_ f: WodFormat) {
        switch f {
        case .forTime(let cap): kind = 0; minutes = cap ?? 0
        case .amrap(let m): kind = 1; minutes = m
        case .emom(let m): kind = 2; minutes = m
        case .tabata(let r): kind = 3; rounds = r
        }
    }

    private func read(_ item: PhotosPickerItem) async {
        error = nil
        reading = true
        defer { reading = false; photo = nil }
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
            error = "Não deu para abrir a imagem."
            return
        }
        let text = (try? await WodOCR.text(from: image)) ?? ""
        guard !text.isEmpty else {
            error = "Não achei texto nessa imagem. Tente um print mais de perto."
            return
        }
        raw = text
        await interpret()
    }

    private func interpret() async {
        error = nil
        reading = true
        defer { reading = false }
        let heuristic = WodParser.parse(raw)
        let draft = heuristic.guessed || heuristic.lines.isEmpty ? (await WodAI.parse(raw) ?? heuristic) : heuristic
        guard !draft.lines.isEmpty else {
            error = "Não achei os movimentos do WOD. Confira o texto."
            return
        }
        apply(draft.format)
        linesText = draft.lines.joined(separator: "\n")
        parts = draft.parts
        guessed = draft.guessed
        reviewing = true
    }
}

/// Campo de texto grande com dica por cima enquanto vazio
private struct WodTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var minHeight: CGFloat = 120

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder).foregroundStyle(Theme.dim.opacity(0.7)).padding(.horizontal, 5).padding(.vertical, 8)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
        }
        .font(.callout)
        .frame(minHeight: minHeight)
        .padding(10)
        .background(Theme.raised, in: .rect(cornerRadius: Theme.radiusM))
    }
}

/// Treino do coach completo: partes, WOD e ações
struct PlannedWodView: View {
    let initial: PlannedWod
    @AppStorage(WodPlan.key) private var raw = ""
    @Environment(\.dismiss) private var dismiss
    @State private var start: Wod?
    @State private var editing = false
    @State private var confirmDelete = false

    /// Volta da edição com o que foi salvo
    private var plan: PlannedWod { WodPlan.all(raw).first { $0.id == initial.id } ?? initial }

    var body: some View {
        GMModal(plan.name) {
            Text(PlannedWodView.dayText(plan.day) + " · " + plan.format.name).font(.subheadline).foregroundStyle(Theme.dim)
            ForEach(Array(plan.parts.enumerated()), id: \.offset) { _, part in
                GMSection(part.title) {
                    ForEach(Array(part.lines.enumerated()), id: \.offset) { Text($0.element).font(.subheadline) }
                }
            }
            GMSection("WOD · \(plan.format.name)") {
                Text(plan.format.detail).font(.caption).foregroundStyle(Theme.dim)
                ForEach(Array(plan.lines.enumerated()), id: \.offset) { Text($0.element).font(.headline) }
            }
            GMButton("Começar WOD", icon: "play.fill") { start = plan.wod }
            GMButton("Editar", icon: "pencil", kind: .secondary) { editing = true }
            GMButton("Apagar treino", icon: "trash", kind: .danger) { confirmDelete = true }
        }
        .gmModal(item: $start) { WodTimerView(wod: $0) }
        .gmModal(isPresented: $editing) { ImportWodView(editing: plan) }
        .gmActions(isPresented: $confirmDelete, title: "Apagar \(plan.name)?", message: "Resultados já salvos continuam no histórico.",
                   actions: [GMAction("Apagar", icon: "trash", destructive: true) { WodPlan.delete(plan); dismiss() }])
    }

    static func dayText(_ d: Date) -> String {
        Calendar.current.isDateInTomorrow(d) ? "Amanhã" : GMDateText.day(d)
    }
}

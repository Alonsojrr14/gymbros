import Foundation

// Importação dos treinos do MFIT Personal (api.mfitpersonal.com.br), feita no próprio aparelho.
// O app nativo não tem CORS, então chama a API do MFIT direto, com a conta do usuário, lendo só os dados dele.
// As credenciais são usadas apenas no login (em memória) e não são gravadas.
//
// Contrato (engenharia reversa observando a sessão autenticada do próprio usuário):
//   POST /auth/client { mail, senha } -> JWT (header `authorization`, sem "Bearer")
//   GET  /v2/client/workout/all               -> [resumo de plano]
//   GET  /v2/client/workout/?id={planId}      -> plano com workouts[] (divisões)
//   GET  /v2/client/workout/session?id={dayId}-> exercs[] -> exercises[] -> series[]

// MARK: - Modelo normalizado (fiel, guardado em MFitImportRecord)

struct MFitSet: Codable, Hashable {
    var order: Int
    var reps: String          // ex: "1x12"
    var weight: String        // ex: "11" (kg)
    var restSeconds: Int
    var time: String
    var speed: String
    var distance: String
    var pace: String
    var incline: String
    var cadence: String
    var notes: String
}

struct MFitExercise: Codable, Hashable {
    var sourceID: String
    var name: String
    var category: String      // strength | cardio | flexibility
    var categoryRaw: String
    var group: String
    var videoURL: String
    var posterURL: String
    var sets: [MFitSet]
}

struct MFitBlock: Codable, Hashable {
    var order: Int
    var type: Int
    var isSuperset: Bool
    var exercises: [MFitExercise]
}

struct MFitDay: Codable, Hashable {
    var sourceID: String
    var name: String
    var weekday: String
    var dayTypeCode: Int
    var order: Int
    var notes: String
    var blocks: [MFitBlock]

    var exerciseCount: Int { blocks.reduce(0) { $0 + $1.exercises.count } }
}

struct MFitPlan: Codable, Hashable {
    var source: String
    var sourceID: String
    var name: String
    var planDescription: String
    var goal: String
    var goalCode: Int?
    var difficulty: String
    var difficultyCode: Int?
    var startDate: String
    var endDate: String
    var days: [MFitDay]
}

// MARK: - Erros

enum MFitError: LocalizedError {
    case auth(String)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .auth(let m): m
        case .api(let m): m
        }
    }
}

// MARK: - JSON cru do MFIT (só os campos que usamos; o resto é ignorado)

private struct RawSummary: Decodable { let id: Int }

private struct RawPlan: Decodable {
    let id: Int
    let nome: String?
    let descricao: String?
    let objetivo: Int?
    let dificuldade: Int?
    let dataInicio: String?
    let dataFim: String?
    let workouts: [RawDay]?
}

private struct RawDay: Decodable {
    let id: Int
    let nome: String?
    let obs: String?
    let diaTipo: Int?
    let ordenacao: Int?
}

private struct RawSession: Decodable {
    let id: Int
    let nome: String?
    let obs: String?
    let exercs: [RawSlot]?
}

private struct RawSlot: Decodable {
    let order: Int?
    let type: Int?
    let exercises: [RawExercise]?
}

private struct RawExercise: Decodable {
    let id: Int
    let name: String?
    let urlMedia: String?
    let urlPoster: String?
    let series: [RawSeries]?
    let exerciseGroup: RawNamed?
    let exerciseCategory: RawNamed2?
}

private struct RawNamed: Decodable { let nome: String? }
private struct RawNamed2: Decodable { let name: String? }

private struct RawSeries: Decodable {
    let repeticao: String?
    let carga: String?
    let tempo: String?
    let velocidade: String?
    let distancia: String?
    let pace: String?
    let inclinacao: String?
    let cadencia: String?
    let intervalo: Int?
    let intervalSeconds: Int?
    let obs: String?
    let ordenacao: Int?
}

// MARK: - Transformador (porte fiel de transform.js, validado contra a conta real)

enum MFitTransformer {
    private static let weekdays = ["", "Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"]
    private static let difficultyNames = [1: "Iniciante", 2: "Intermediário", 3: "Avançado"]
    private static let goalNames = [3: "Redução de gordura e hipertrofia"]

    static func htmlDecode(_ value: String?) -> String {
        guard var s = value else { return "" }
        // Entidades numéricas: &#9940; e &#x...;
        s = replaceEntities(s, pattern: "&#x([0-9A-Fa-f]+);", radix: 16)
        s = replaceEntities(s, pattern: "&#([0-9]+);", radix: 10)
        let named = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " "]
        for (k, v) in named { s = s.replacingOccurrences(of: k, with: v) }
        return s
    }

    private static func replaceEntities(_ input: String, pattern: String, radix: Int) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return input }
        let ns = input as NSString
        var result = ""
        var last = 0
        re.enumerateMatches(in: input, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges == 2 else { return }
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let code = ns.substring(with: m.range(at: 1))
            if let n = UInt32(code, radix: radix), let scalar = Unicode.Scalar(n) {
                result += String(scalar)
            }
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    private static func clean(_ value: String?) -> String {
        htmlDecode(value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func category(_ raw: String?) -> String {
        let n = (raw ?? "").lowercased()
        if n.contains("mobil") || n.contains("stretch") || n.contains("along") || n.contains("flex") { return "flexibility" }
        if n.contains("cardio") || n.contains("run") || n.contains("corrida") || n.contains("aerob") || n.contains("aeró") { return "cardio" }
        return "strength"
    }

    private static func transform(_ s: RawSeries) -> MFitSet {
        MFitSet(order: s.ordenacao ?? 0,
                reps: s.repeticao ?? "",
                weight: s.carga ?? "",
                restSeconds: s.intervalSeconds ?? s.intervalo ?? 0,
                time: s.tempo ?? "",
                speed: s.velocidade ?? "",
                distance: s.distancia ?? "",
                pace: s.pace ?? "",
                incline: s.inclinacao ?? "",
                cadence: s.cadencia ?? "",
                notes: clean(s.obs))
    }

    private static func transform(_ ex: RawExercise) -> MFitExercise {
        let series = (ex.series ?? []).sorted { ($0.ordenacao ?? 0) < ($1.ordenacao ?? 0) }
        return MFitExercise(sourceID: String(ex.id),
                            name: clean(ex.name),
                            category: category(ex.exerciseCategory?.name),
                            categoryRaw: ex.exerciseCategory?.name ?? "",
                            group: clean(ex.exerciseGroup?.nome),
                            videoURL: ex.urlMedia ?? "",
                            posterURL: ex.urlPoster ?? "",
                            sets: series.map(transform))
    }

    private static func transform(_ slot: RawSlot) -> MFitBlock {
        let exercises = (slot.exercises ?? []).map(transform)
        return MFitBlock(order: slot.order ?? 0, type: slot.type ?? 0, isSuperset: exercises.count > 1, exercises: exercises)
    }

    private static func buildPlan(_ plan: RawPlan, sessions: [Int: RawSession]) -> MFitPlan {
        let days = (plan.workouts ?? []).sorted { ($0.ordenacao ?? 0) < ($1.ordenacao ?? 0) }
        return MFitPlan(
            source: "mfit",
            sourceID: String(plan.id),
            name: clean(plan.nome),
            planDescription: clean(plan.descricao),
            goal: plan.objetivo.flatMap { goalNames[$0] } ?? (plan.objetivo.map { "Objetivo \($0)" } ?? ""),
            goalCode: plan.objetivo,
            difficulty: plan.dificuldade.flatMap { difficultyNames[$0] } ?? "",
            difficultyCode: plan.dificuldade,
            startDate: plan.dataInicio ?? "",
            endDate: plan.dataFim ?? "",
            days: days.map { d in
                let slots = (sessions[d.id]?.exercs ?? []).sorted { ($0.order ?? 0) < ($1.order ?? 0) }
                return MFitDay(sourceID: String(d.id),
                               name: clean(d.nome),
                               weekday: weekdays[safe: d.diaTipo ?? 0] ?? "",
                               dayTypeCode: d.diaTipo ?? 0,
                               order: d.ordenacao ?? 0,
                               notes: clean(d.obs),
                               blocks: slots.map(transform))
            })
    }

    // Decodificadores usados pelos testes (vetores compartilhados) e pelo cliente.
    static func plan(fromDetail data: Data, sessions: [Int: Data]) throws -> MFitPlan {
        let raw: RawPlan = try decodeOneOrFirst(data)
        var raws: [Int: RawSession] = [:]
        for (id, d) in sessions { raws[id] = try decodeOneOrFirst(d) as RawSession }
        return buildPlan(raw, sessions: raws)
    }

    fileprivate static func decodeOneOrFirst<T: Decodable>(_ data: Data) throws -> T {
        let dec = JSONDecoder()
        if let one = try? dec.decode(T.self, from: data) { return one }
        let list = try dec.decode([T].self, from: data)
        guard let first = list.first else { throw MFitError.api("resposta vazia") }
        return first
    }

    fileprivate static func summaries(_ data: Data) throws -> [Int] {
        let list = try JSONDecoder().decode([RawSummary].self, from: data)
        return list.map(\.id)
    }
}

// MARK: - Cliente HTTP

final class MFitClient {
    private let base = URL(string: "https://api.mfitpersonal.com.br")!
    private let session: URLSession
    private var token: String?
    private let minDelay: TimeInterval
    private var lastCall = Date.distantPast

    init(session: URLSession = .shared, minDelay: TimeInterval = 0.35) {
        self.session = session
        self.minDelay = minDelay
    }

    private func throttle() async {
        let wait = lastCall.addingTimeInterval(minDelay).timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        lastCall = Date()
    }

    private func get(_ path: String) async throws -> Data {
        guard let token else { throw MFitError.auth("não autenticado") }
        await throttle()
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.setValue(token, forHTTPHeaderField: "authorization")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MFitError.api("GET \(path) falhou")
        }
        return data
    }

    // Monta caminhos com query manualmente (o path tem "?") para bater com a API.
    private func getRaw(_ pathAndQuery: String) async throws -> Data {
        guard let token else { throw MFitError.auth("não autenticado") }
        await throttle()
        guard let url = URL(string: base.absoluteString + pathAndQuery) else { throw MFitError.api("URL inválida") }
        var req = URLRequest(url: url)
        req.setValue(token, forHTTPHeaderField: "authorization")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "accept")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MFitError.api("GET \(pathAndQuery) falhou")
        }
        return data
    }

    func login(mail: String, senha: String) async throws {
        await throttle()
        var req = URLRequest(url: base.appendingPathComponent("/auth/client"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue("application/json", forHTTPHeaderField: "accept")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["mail": mail, "senha": senha])
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw MFitError.auth("sem resposta") }
        guard (200..<300).contains(http.statusCode) else {
            throw MFitError.auth("login falhou (verifique e-mail e senha)")
        }
        if let header = http.value(forHTTPHeaderField: "authorization"), isJWT(header) {
            token = header
        } else if let t = Self.extractJWT(data) {
            token = t
        } else {
            throw MFitError.auth("login ok, mas o token não veio na resposta")
        }
    }

    /// Login + busca encadeada + transformação. Devolve os planos normalizados.
    func importPlans(progress: ((String) -> Void)? = nil) async throws -> [MFitPlan] {
        let ids = try MFitTransformer.summaries(try await get("/v2/client/workout/all"))
        progress?("Planos encontrados: \(ids.count)")
        var plans: [MFitPlan] = []
        for id in ids {
            let detail = try await getRaw("/v2/client/workout/?id=\(id)")
            let rawPlan: RawPlan = try MFitTransformer.decodeOneOrFirst(detail)
            var sessions: [Int: Data] = [:]
            for day in rawPlan.workouts ?? [] {
                if let s = try? await getRaw("/v2/client/workout/session?id=\(day.id)") { sessions[day.id] = s }
            }
            let plan = try MFitTransformer.plan(fromDetail: detail, sessions: sessions)
            progress?("“\(plan.name)”: \(plan.days.count) divisão(ões)")
            plans.append(plan)
        }
        return plans
    }

    private func isJWT(_ s: String) -> Bool { Self.jwtRegex.firstMatch(in: s.trimmingCharacters(in: .whitespaces)) }

    private static let jwtRegex = NSRegularExpression.jwt
    private static func extractJWT(_ data: Data) -> String? {
        let text = (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if jwtRegex.firstMatch(in: text) { return text }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let s = obj as? String, jwtRegex.firstMatch(in: s.trimmingCharacters(in: .whitespaces)) { return s }
        guard let dict = obj as? [String: Any] else { return nil }
        let preferred = ["token", "accessToken", "access_token", "jwt", "authorization", "auth"]
        for key in preferred {
            if let v = dict[key] as? String, jwtRegex.firstMatch(in: v.trimmingCharacters(in: .whitespaces)) { return v }
        }
        for case let v as String in dict.values where jwtRegex.firstMatch(in: v.trimmingCharacters(in: .whitespaces)) { return v }
        return nil
    }
}

private extension NSRegularExpression {
    static let jwt = try! NSRegularExpression(pattern: "^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$")
    func firstMatch(in s: String) -> Bool {
        firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }
}

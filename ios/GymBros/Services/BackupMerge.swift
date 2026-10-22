import Foundation

// Mesclagem da cópia da conta entre aparelhos (IOS-08, engenharia/arquitetura/ios-08-mesclagem.md).
// Três vias: a cópia deste aparelho, a da nuvem e a base (a última que este aparelho enviou ou recebeu).
// Trabalha sobre o JSON do Backup: toda lista de itens com `uuid` é mesclada por item, as notas pelo exercício e os
// ajustes por chave. Campo novo no Backup entra na mesclagem sem código novo. O app Android faz a mesma coisa.

enum BackupMerge {
    /// Campos de foto: a cópia da nuvem vai sem eles, então não contam como mudança e a foto local fica
    static let photoKeys: Set<String> = ["photo", "photoFront", "photoSide", "extraPhotos"]
    /// Listas que se mesclam por outra chave que não o `uuid`
    static let listKeys: [String: String] = ["notes": "exerciseID"]
    /// Ajustes que são registros (só crescem): une os dois lados em vez de escolher um
    static let registryKeys: Set<String> = [RetiredActivities.key, "duelScoreRecords", TradeLedger.basesKey, TradeLedger.goneKey,
                                            TradeLedger.appliedKey]

    struct Result {
        var backup: Backup
        /// Itens que mudaram nos dois aparelhos: fica a versão do lado mais novo e a outra vai para cá (guardada à parte)
        var conflicts: [String] = []
    }

    /// `remote` e `base` vêm da nuvem e do arquivo deste aparelho; `newerIsLocal` desempata itens mudados dos dois lados
    static func merge(local: Backup, remote: Backup, base: Backup?) throws -> Result {
        let l = try json(local), r = try json(remote), b = try base.map(json)
        let newerIsLocal = local.exportedAt.timeIntervalSince1970.rounded(.down) >= remote.exportedAt.timeIntervalSince1970.rounded(.down)
        var out = l
        var conflicts: [String] = []
        for key in Set(l.keys).union(r.keys) {
            let lv = l[key], rv = r[key], bv = b?[key]
            if key == "accountSettings" {
                out[key] = try mergeSettingsPlist(lv as? String, rv as? String, bv as? String, newerIsLocal: newerIsLocal) ?? NSNull()
            } else if key == "settings" || key == "typedSettings" {
                out[key] = mergeDict(lv as? [String: Any], rv as? [String: Any], bv as? [String: Any], newerIsLocal: newerIsLocal) ?? NSNull()
            } else if lv is [Any] || rv is [Any] {
                // Listas de itens (atividades, rotinas, sessões, ligas, bros, medidas, check-ins…): por item
                let id = listKeys[key] ?? "uuid"
                let (items, c) = mergeItems(lv as? [[String: Any]] ?? [], rv as? [[String: Any]] ?? [], bv as? [[String: Any]],
                                            id: id, newerIsLocal: newerIsLocal)
                out[key] = items
                conflicts += c.map { "\(key):\($0)" }
            } else if key == "exportedAt" {
                out[key] = newerIsLocal ? lv : rv
            } else if lv == nil || lv is NSNull {
                out[key] = rv
            }
            // Outros campos (versão, foto do perfil, estado de sincronização): ficam os deste aparelho
        }
        let data = try JSONSerialization.data(withJSONObject: out, options: [.sortedKeys])
        return Result(backup: try Backup.decoder.decode(Backup.self, from: data), conflicts: conflicts.sorted())
    }

    // MARK: Itens

    /// Três vias por item. Ordem: a deste aparelho, depois os novos da nuvem na ordem dela.
    static func mergeItems(_ local: [[String: Any]], _ remote: [[String: Any]], _ base: [[String: Any]]?, id: String,
                           newerIsLocal: Bool) -> ([[String: Any]], [String]) {
        func index(_ list: [[String: Any]]) -> [String: [String: Any]] {
            Dictionary(list.compactMap { i in (i[id] as? String).map { ($0, i) } }, uniquingKeysWith: { a, _ in a })
        }
        let li = index(local), ri = index(remote), bi = base.map(index) ?? [:]
        let hasBase = base != nil
        var out: [[String: Any]] = []
        var conflicts: [String] = []
        let order = local.compactMap { $0[id] as? String } + remote.compactMap { $0[id] as? String }.filter { li[$0] == nil }
        for key in order {
            let l = li[key], r = ri[key], b = bi[key]
            switch (l, r) {
            case let (l?, r?):
                if same(l, r) || (b.map { same(r, $0) } ?? false) {
                    out.append(l)
                } else if let b, same(l, b) {
                    out.append(withPhotos(r, from: l))
                } else {
                    // Mudou dos dois lados (ou sem base): fica o do aparelho com a cópia mais nova
                    out.append(newerIsLocal ? l : withPhotos(r, from: l))
                    conflicts.append(key)
                }
            case let (l?, nil):
                // Só aqui: novo deste aparelho, ou apagado no outro (some, a menos que tenha mudado aqui depois)
                if !hasBase || b == nil || !same(l, b!) { out.append(l) }
            case let (nil, r?):
                // Só na nuvem: novo do outro aparelho, ou apagado aqui (não volta, a menos que tenha mudado lá)
                if !hasBase || b == nil || !same(r, b!) { out.append(r) }
            default:
                break
            }
        }
        return (out, conflicts)
    }

    /// Iguais fora as fotos (a cópia da nuvem não tem)
    static func same(_ a: [String: Any], _ b: [String: Any]) -> Bool {
        canonical(a.filter { !photoKeys.contains($0.key) }) == canonical(b.filter { !photoKeys.contains($0.key) })
    }

    private static func withPhotos(_ item: [String: Any], from local: [String: Any]) -> [String: Any] {
        var out = item
        for k in photoKeys where (out[k] == nil || out[k] is NSNull) { if let v = local[k], !(v is NSNull) { out[k] = v } }
        return out
    }

    // MARK: Ajustes

    static func mergeDict(_ l: [String: Any]?, _ r: [String: Any]?, _ b: [String: Any]?, newerIsLocal: Bool) -> [String: Any]? {
        guard l != nil || r != nil else { return nil }
        let l = l ?? [:], r = r ?? [:]
        var out: [String: Any] = [:]
        for key in Set(l.keys).union(r.keys) {
            let lv = l[key], rv = r[key], bv = b?[key]
            if registryKeys.contains(key) {
                out[key] = union(lv, rv)
                continue
            }
            switch (lv, rv) {
            case let (lv?, rv?):
                if canonical(lv) == canonical(rv) || bv.map({ canonical($0) == canonical(rv) }) ?? false { out[key] = lv }
                else if let bv, canonical(bv) == canonical(lv) { out[key] = rv }
                else { out[key] = newerIsLocal ? lv : rv }
            case let (lv?, nil):
                // Só aqui: novo, ou apagado no outro aparelho sem mudança aqui
                if bv == nil || canonical(bv!) != canonical(lv) { out[key] = lv }
            case let (nil, rv?):
                if bv == nil || canonical(bv!) != canonical(rv) { out[key] = rv }
            default:
                break
            }
        }
        return out
    }

    /// `accountSettings`: plist binário em base64 no JSON
    private static func mergeSettingsPlist(_ l: String?, _ r: String?, _ b: String?, newerIsLocal: Bool) throws -> String? {
        func dict(_ s: String?) throws -> [String: Any]? {
            guard let s, let data = Data(base64Encoded: s) else { return nil }
            return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        }
        guard let merged = mergeDict(try dict(l), try dict(r), try dict(b), newerIsLocal: newerIsLocal) else { return nil }
        return try PropertyListSerialization.data(fromPropertyList: merged, format: .binary, options: 0).base64EncodedString()
    }

    /// União de registros: listas sem repetir, dicionários chave a chave (o deste aparelho primeiro)
    private static func union(_ a: Any?, _ b: Any?) -> Any? {
        switch (a, b) {
        case let (a as [Any], b as [Any]):
            var seen = Set(a.map(canonical))
            return a + b.filter { seen.insert(canonical($0)).inserted }
        case let (a as [String: Any], b as [String: Any]):
            return a.merging(b) { l, _ in l }
        default:
            return a ?? b
        }
    }

    // MARK: JSON

    private static func json(_ b: Backup) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Backup.encoder.encode(b)) as? [String: Any] ?? [:]
    }

    /// Texto estável para comparar valores (chaves ordenadas). Datas e dados viram texto antes (plist).
    static func canonical(_ v: Any) -> String {
        if let d = v as? Date { return "date:\(d.timeIntervalSince1970)" }
        if let d = v as? Data { return "data:\(d.base64EncodedString())" }
        if let dict = v as? [String: Any] { return "{" + dict.keys.sorted().map { "\($0):\(canonical(dict[$0]!))" }.joined(separator: ",") + "}" }
        if let list = v as? [Any] { return "[" + list.map(canonical).joined(separator: ",") + "]" }
        if v is NSNull { return "null" }
        if let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
        return "\(v)"
    }
}

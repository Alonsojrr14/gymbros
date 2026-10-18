import Foundation
import SwiftData

@Model
final class Monster {
    var uuid: UUID = UUID()
    /// Apelido; vazio usa o nome da forma atual
    var name: String = ""
    var createdAt: Date = Date.now
    var isStarter: Bool = false
    /// Última forma vista, para disparar a cena de evolução uma vez só
    var lastFormID: String = ""
    /// Espécie, fixada quando o ovo choca (nil enquanto é ovo)
    var speciesID: String?

    init(name: String = "", isStarter: Bool = false) {
        self.name = name
        self.isStarter = isStarter
        self.lastFormID = MonsterForm.egg.id
    }

    func displayName(_ form: MonsterForm) -> String {
        form.stage == .egg || name.isEmpty ? form.name : name
    }
}

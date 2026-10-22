import SwiftUI

// Cores do tema, compartilhadas entre o app e o widget

enum Theme {
    static let bg = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let card = Color(red: 0.10, green: 0.11, blue: 0.14)
    static let accent = Color(red: 0.64, green: 0.90, blue: 0.21)
    static let dim = Color.white.opacity(0.55)
    static let raised = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.08)
    /// Trilho vazio de barras e régua
    static let track = Color.white.opacity(0.1)
    static let danger = Color(red: 1.0, green: 0.38, blue: 0.38)

    /// Fogo: sequência de dias, WOD, série de aquecimento
    static let streak = Color.orange
    /// Alerta: meta não batida, volume abaixo do ideal, CAP, descanso do WOD, aviso de permissão
    static let warning = Color.orange
    /// Superset e volume acima do ideal
    static let info = Color.cyan
    /// Conquistas e recordes
    static let trophy = Color.yellow
    /// Anotações do treino
    static let note = Color.yellow
    /// Origem Apple Saúde
    static let health = Color.pink
    /// Amigo online / treinando agora
    static let online = Color(red: 0.25, green: 0.88, blue: 0.42)
    /// Contador de notificação
    static let badge = Color.red
    /// Vídeo (YouTube)
    static let video = Color(red: 0.9, green: 0.2, blue: 0.2)
}

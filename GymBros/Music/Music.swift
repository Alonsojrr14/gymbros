import Foundation
import MediaPlayer
import Observation

// "Ouvindo agora": a música que a pessoa escuta aparece para os amigos enquanto ela treina ao vivo.
// Opcional e desligado por padrão. Cada serviço entra por um `NowPlayingProvider`:
// - Apple Music: o que toca no app Música (MediaPlayer), com a permissão de Apple Music. Funciona hoje.
// - Spotify: Web API (`/me/player/currently-playing`) com login OAuth (PKCE). Precisa registrar o app no
//   Spotify for Developers e preencher `SpotifyNowPlaying.clientID`; até lá ele não aparece no app.
// O envio para os amigos vai junto com o status ao vivo, quando houver servidor (docs/servidor-real.md).

enum MusicSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleMusic, spotify

    var id: String { rawValue }
    var name: String { self == .appleMusic ? "Apple Music" : "Spotify" }
}

struct NowPlayingTrack: Codable, Equatable, Sendable {
    var title: String
    var artist: String
    var source: MusicSource

    var line: String { artist.isEmpty ? title : "\(title) · \(artist)" }
}

protocol NowPlayingProvider: Sendable {
    var source: MusicSource { get }
    /// Disponível neste build (o Spotify depende de um app registrado no Spotify for Developers)
    var isAvailable: Bool { get }
    func isAuthorized() async -> Bool
    /// Pede o acesso; devolve se ficou liberado
    func requestAccess() async -> Bool
    /// O que está tocando agora (nil: nada tocando ou sem acesso)
    func current() async -> NowPlayingTrack?
}

/// App Música do iPhone, pelo MediaPlayer: não precisa da capability MusicKit
struct AppleMusicNowPlaying: NowPlayingProvider {
    let source = MusicSource.appleMusic
    let isAvailable = true

    func isAuthorized() async -> Bool { MPMediaLibrary.authorizationStatus() == .authorized }

    func requestAccess() async -> Bool {
        if MPMediaLibrary.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { done in
            MPMediaLibrary.requestAuthorization { done.resume(returning: $0 == .authorized) }
        }
    }

    func current() async -> NowPlayingTrack? {
        guard await isAuthorized() else { return nil }
        return await MainActor.run {
            let player = MPMusicPlayerController.systemMusicPlayer
            guard player.playbackState == .playing, let item = player.nowPlayingItem,
                  let title = item.title, !title.isEmpty else { return nil }
            return NowPlayingTrack(title: title, artist: item.artist ?? "", source: .appleMusic)
        }
    }
}

/// Spotify Web API. Sem `clientID` (app ainda não registrado) fica indisponível e não aparece nos Ajustes.
struct SpotifyNowPlaying: NowPlayingProvider {
    /// Client ID do app no Spotify for Developers (não é segredo; o login usa PKCE, sem client secret)
    static let clientID: String? = nil
    let source = MusicSource.spotify
    var isAvailable: Bool { Self.clientID != nil }

    func isAuthorized() async -> Bool { false }
    func requestAccess() async -> Bool { false }
    func current() async -> NowPlayingTrack? { nil }
}

@MainActor @Observable
final class MusicShareStore {
    static let shared = MusicShareStore()

    static let shareKey = "shareMusic", sourceKey = "musicSource"
    /// Vão com a conta (AccountSync) e saem do aparelho ao sair
    static let defaultsKeys = [shareKey, sourceKey]

    var defaults: UserDefaults
    var providers: [MusicSource: any NowPlayingProvider]
    private(set) var current: NowPlayingTrack?
    private(set) var message: String?

    init(defaults: UserDefaults = .standard,
         providers: [MusicSource: any NowPlayingProvider] = [.appleMusic: AppleMusicNowPlaying(), .spotify: SpotifyNowPlaying()]) {
        self.defaults = defaults
        self.providers = providers
    }

    var sharing: Bool { defaults.bool(forKey: Self.shareKey) }

    var source: MusicSource {
        defaults.string(forKey: Self.sourceKey).flatMap(MusicSource.init(rawValue:)) ?? .appleMusic
    }

    /// Serviços que dá para escolher neste build
    var availableSources: [MusicSource] { MusicSource.allCases.filter { providers[$0]?.isAvailable == true } }

    /// Liga pedindo o acesso ao serviço; sem acesso, continua desligado e explica o motivo
    func setSharing(_ on: Bool) async {
        message = nil
        guard on else {
            defaults.set(false, forKey: Self.shareKey)
            current = nil
            return
        }
        guard let provider = providers[source], provider.isAvailable else { return }
        if await provider.requestAccess() {
            defaults.set(true, forKey: Self.shareKey)
            await refresh()
        } else {
            defaults.set(false, forKey: Self.shareKey)
            message = "Sem acesso ao \(source.name). Libere em Ajustes do iPhone > GymBros."
        }
    }

    func setSource(_ s: MusicSource) async {
        defaults.set(s.rawValue, forKey: Self.sourceKey)
        if sharing { await setSharing(true) }
    }

    func refresh() async {
        guard sharing, let provider = providers[source] else {
            current = nil
            return
        }
        current = await provider.current()
    }

    /// Recarrega depois de entrar numa conta ou sair dela
    func reload() {
        current = nil
        message = nil
    }
}

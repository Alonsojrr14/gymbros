import AVFoundation
import MediaPlayer

/// Modo fone: durante o treino o app vira o "player" do iPhone, então o play/pause do fone
/// (AirPods, fone com fio, controle do carro) marca a série ou pula o descanso, e o app fala no fone.
/// Para isso ele precisa tocar áudio (silêncio); a música de outro app para enquanto o modo está ligado.
@MainActor
final class HeadphoneControl {
    static let shared = HeadphoneControl()

    private(set) var isOn = false
    private var player: AVAudioPlayer?
    private let voice = AVSpeechSynthesizer()
    private var watcher: Task<Void, Never>?
    private var announcedRestEnd: Date?

    func start() {
        guard !isOn else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
        player = try? AVAudioPlayer(data: HeadphoneControl.silence)
        player?.numberOfLoops = -1
        player?.volume = 0.01
        player?.play()

        let center = MPRemoteCommandCenter.shared()
        for command in [center.togglePlayPauseCommand, center.playCommand, center.pauseCommand, center.nextTrackCommand] {
            command.isEnabled = true
            command.addTarget { [weak self] _ in
                Task { @MainActor in await self?.pressed() }
                return .success
            }
        }
        isOn = true
        refresh()
        watchRest()
        speak("Modo fone ligado. Aperte o play do fone para marcar a série.")
    }

    func stop() {
        guard isOn else { return }
        let center = MPRemoteCommandCenter.shared()
        for command in [center.togglePlayPauseCommand, center.playCommand, center.pauseCommand, center.nextTrackCommand] {
            command.removeTarget(nil)
        }
        watcher?.cancel()
        player?.stop()
        player = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        // Devolve o áudio: a música de outro app pode voltar a tocar
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isOn = false
    }

    /// Play/pause do fone: no descanso, pula; fora dele, marca a série
    private func pressed() async {
        guard let s = LiveWorkout.runningSession else {
            speak("Nenhum treino em andamento.")
            return
        }
        let resting = s.restEnd.map { $0 > .now } ?? false
        let msg = resting ? await LiveWorkout.skipRest() : await LiveWorkout.completeNextSet()
        speak(msg)
    }

    /// Mostra no "tocando agora" (tela de bloqueio, fone, carro) o exercício e a série
    func refresh() {
        guard isOn, let s = LiveWorkout.runningSession else { return }
        let st = LiveWorkout.state(for: s)
        let resting = st.restEnd != nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: resting ? "Descanso" : st.exercise,
            MPMediaItemPropertyArtist: st.exerciseDone ? "Exercício concluído" : "Série \(st.setNumber) de \(st.setCount) · \(st.setText)",
            MPMediaItemPropertyAlbumTitle: "GymBros",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
    }

    /// Avisa no fone quando o descanso acaba (o app segue ativo por estar tocando áudio)
    private func watchRest() {
        watcher?.cancel()
        watcher = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let s = LiveWorkout.runningSession else { continue }
                if let end = s.restEnd, end <= .now, announcedRestEnd != end {
                    announcedRestEnd = end
                    s.restEnd = nil
                    try? AppData.container.mainContext.save()
                    await LiveWorkout.refresh(s)
                    refresh()
                    let st = LiveWorkout.state(for: s)
                    speak(st.exerciseDone ? "Descanso acabou." : "Descanso acabou. \(st.exercise), série \(st.setNumber), \(st.setText).")
                } else if let end = s.restEnd, Int(end.timeIntervalSinceNow.rounded()) == 10, announcedRestEnd != end {
                    speak("Dez segundos.")
                }
            }
        }
    }

    func speak(_ text: String) {
        let u = AVSpeechUtterance(string: text.replacingOccurrences(of: " × ", with: " por "))
        u.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        u.rate = 0.52
        voice.speak(u)
    }

    /// 1 segundo de silêncio em WAV, tocado em loop para o app continuar sendo o "player"
    private static let silence: Data = {
        let rate: UInt32 = 8000, samples = rate
        var d = Data()
        func add<T>(_ v: T) { withUnsafeBytes(of: v) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); add(UInt32(36 + samples * 2).littleEndian)
        d.append(contentsOf: Array("WAVEfmt ".utf8)); add(UInt32(16).littleEndian); add(UInt16(1).littleEndian); add(UInt16(1).littleEndian)
        add(rate.littleEndian); add((rate * 2).littleEndian); add(UInt16(2).littleEndian); add(UInt16(16).littleEndian)
        d.append(contentsOf: Array("data".utf8)); add(UInt32(samples * 2).littleEndian)
        d.append(Data(count: Int(samples * 2)))
        return d
    }()
}

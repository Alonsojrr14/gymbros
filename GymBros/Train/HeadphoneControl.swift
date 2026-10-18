import AVFoundation

/// Modo fone: durante o treino o app fala no fone os avisos do descanso.
/// A sessão de áudio só fica ativa enquanto fala, abaixando a música de outro app nesse intervalo.
@MainActor
final class HeadphoneControl: NSObject {
    static let shared = HeadphoneControl()

    private(set) var isOn = false
    private let voice = AVSpeechSynthesizer()
    private var watcher: Task<Void, Never>?
    private var announcedRestEnd: Date?
    private var tenSeconds = TenSecondCue()

    override private init() {
        super.init()
        voice.delegate = self
    }

    func start() {
        guard !isOn else { return }
        isOn = true
        watchRest()
        speak("Modo fone ligado. Vou avisar no fone quando o descanso acabar.")
    }

    func stop() {
        guard isOn else { return }
        watcher?.cancel()
        voice.stopSpeaking(at: .immediate)
        release()
        isOn = false
    }

    /// Avisa no fone quando o descanso acaba (só enquanto o app está aberto)
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
                    let st = LiveWorkout.state(for: s)
                    speak(st.exerciseDone ? "Descanso acabou." : "Descanso acabou. \(st.exercise), série \(st.setNumber), \(st.setText).")
                } else if tenSeconds.check(end: s.restEnd, now: .now) {
                    speak("Dez segundos.")
                }
            }
        }
    }

    func speak(_ text: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? session.setActive(true)
        let u = AVSpeechUtterance(string: text.replacingOccurrences(of: " × ", with: " por "))
        u.voice = AVSpeechSynthesisVoice(language: "pt-BR")
        u.rate = 0.52
        voice.speak(u)
    }

    /// Devolve o áudio: a música de outro app volta ao volume normal
    private func release() {
        guard !voice.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension HeadphoneControl: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.release() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.release() }
    }
}

/// Aviso "Dez segundos" do descanso: uma vez por descanso, sem depender de cair exatamente no segundo 10
/// (o laço acorda a cada ~1 s e pode pular ou repetir o 10). Só avisa se o descanso foi visto com mais de 10 s,
/// para não falar "dez segundos" num descanso curto ou que já começou abaixo disso (ex.: depois do −15 s).
struct TenSecondCue {
    /// Descanso visto com mais de 10 s restantes (pode avisar)
    private var armed: Date?
    /// Descanso já avisado
    private var warned: Date?

    /// Devolve true no momento de falar
    mutating func check(end: Date?, now: Date) -> Bool {
        guard let end else { return false }
        let left = end.timeIntervalSince(now)
        if left > 10 {
            armed = end
            return false
        }
        guard left > 0, armed == end, warned != end else { return false }
        warned = end
        return true
    }
}

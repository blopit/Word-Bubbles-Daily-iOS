import AVFoundation
import Foundation

/// What the model needs from the sound system.
@MainActor
protocol SoundPlaying: AnyObject {
    var isOn: Bool { get set }
    func play(_ effect: SoundEffect)
    func suspend()
    func resume()
}

/// Plays pre-rendered tones through a pool of always-running player nodes, so a pick has no start-up latency.
/// `.ambient` obeys the silent switch and mixes with whatever music is playing.
@MainActor
final class SoundEngine: SoundPlaying {
    private static let defaultsKey = "wordbubbles-sound"
    private static let sampleRate = 44_100.0
    private static let voices = 12

    private let defaults: UserDefaults
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundEngine.sampleRate, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var nextVoice = 0
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var configurationObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?

    var isOn: Bool {
        didSet {
            defaults.set(isOn, forKey: Self.defaultsKey)
            if isOn { start() }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isOn = defaults.object(forKey: Self.defaultsKey) as? Bool ?? true

        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setPreferredIOBufferDuration(0.005)
        for _ in 0..<Self.voices {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restart() }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let ended = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue
            MainActor.assumeIsolated { if ended { self?.restart() } }
        }
        prerender()
        if isOn { start() }
    }

    deinit {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    private func prerender() {
        let rate = Self.sampleRate
        Task.detached(priority: .utility) { [weak self] in
            let rendered = SoundEffect.allCanonical.map { ($0, ToneSynth.render($0.tones, sampleRate: rate)) }
            await self?.install(rendered)
        }
    }

    private func install(_ rendered: [(SoundEffect, [Float])]) {
        for (effect, samples) in rendered where buffers[effect] == nil {
            buffers[effect] = makeBuffer(samples)
        }
    }

    private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    private func start() {
        guard !engine.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.prepare()
        guard (try? engine.start()) != nil else { return }
        for player in players { player.play() }
    }

    private func restart() {
        engine.stop()
        if isOn { start() }
    }

    func suspend() {
        engine.pause()
    }

    func resume() {
        if isOn { start() }
    }

    func play(_ effect: SoundEffect) {
        guard isOn else { return }
        let key = effect.canonical
        // Before the pre-render lands, a single short sound is still quick enough to make here.
        guard let buffer = buffers[key] ?? makeBuffer(ToneSynth.render(key.tones, sampleRate: Self.sampleRate)) else { return }
        buffers[key] = buffer
        start()
        guard engine.isRunning else { return }
        let player = players[nextVoice]
        nextVoice = (nextVoice + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}

/// For UI tests and anywhere sound must stay quiet.
@MainActor
final class SilentSound: SoundPlaying {
    var isOn = true
    func play(_ effect: SoundEffect) {}
    func suspend() {}
    func resume() {}
}

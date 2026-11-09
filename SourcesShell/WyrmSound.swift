import AVFoundation
import SwiftUI

/// AIR's music and sounds (OM, 2026-11-08), as Main.as plays them. The engine
/// decides what happens (game/wyrm_audio.c); this plays AIR's own files from
/// `res/sounds/`. Music off and sounds on by default (OM). Synced
/// (`wyrm.ios.audio.`) and account-wide: musicOn / soundsOn / newSounds /
/// newMusic in the shared document. Android twin: `data/WyrmSound.kt`.
@MainActor
final class WyrmSound: ObservableObject {
    static let shared = WyrmSound()
    static let musicKey = "wyrm.ios.audio.music"
    static let soundsKey = "wyrm.ios.audio.sounds"
    static let newSoundsKey = "wyrm.ios.audio.new-sounds"
    static let newMusicKey = "wyrm.ios.audio.new-music"

    @Published private(set) var musicOn = false
    @Published private(set) var soundsOn = true
    @Published private(set) var newSounds = true
    @Published private(set) var newMusic = true

    /* Players made once, off the main thread, and reused (2026-11-08): making
       an AVAudioPlayer decodes its file, and the engine runs on the main
       thread, so a new one per bite or per boost dropped frames. */
    private var pools: [String: [AVAudioPlayer]] = [:]
    private var loading: Set<String> = []
    private let loader = DispatchQueue(label: "wyrm.sound.loader", qos: .utility)
    private var boostPlayer: AVAudioPlayer?
    private var boostVolume: Float = 0
    private var menuIntro: AVAudioPlayer?
    private var menuLoop: AVAudioPlayer?
    private var song: AVAudioPlayer?
    private var songIndex = -2
    private var songVolume: Float = 0
    private var songStarted = Date.distantPast
    private var songLastPlayed = [Date](repeating: .distantPast, count: 8)
    private var inMatch = false
    private var dying = false
    private var active = true
    private var timer: Timer?
    private var last = Date()
    /// The shell says whether a match (online or Play with AI) is on screen.
    var match: () -> Bool = { false }
    private static let songVolumes: [Float] = [0.4, 0.4, 0.31, 0.4, 0.35, 0.4, 0.4, 0.4]

    private init() { reload() }

    /// iOS plays nothing (OM, 2026-11-08: removed after frame drops on every
    /// bite). The values are only kept so the shared document still carries
    /// Android's musicOn / soundsOn / newSounds / newMusic unchanged.
    static let enabled = false

    func reload() {
        let d = UserDefaults.standard
        musicOn = d.object(forKey: Self.musicKey) as? Bool ?? false
        soundsOn = d.object(forKey: Self.soundsKey) as? Bool ?? true
        newSounds = d.object(forKey: Self.newSoundsKey) as? Bool ?? true
        newMusic = d.object(forKey: Self.newMusicKey) as? Bool ?? true
        guard Self.enabled else { return }
        refreshMusic(restart: true)
        if !soundsOn { stopBoost() }
    }

    func setMusic(_ on: Bool) { musicOn = on; UserDefaults.standard.set(on, forKey: Self.musicKey); refreshMusic(restart: true) }
    func setSounds(_ on: Bool) { soundsOn = on; UserDefaults.standard.set(on, forKey: Self.soundsKey); if !on { stopBoost() } }
    func setNewSounds(_ on: Bool) { newSounds = on; UserDefaults.standard.set(on, forKey: Self.newSoundsKey) }
    func setNewMusic(_ on: Bool) {
        newMusic = on; UserDefaults.standard.set(on, forKey: Self.newMusicKey)
        if inMatch { stopSong(); if musicOn { startSong() } }
    }

    /// Shared document restore: each key on its own.
    static func restore(music: Bool?, sounds: Bool?, newSounds: Bool?, newMusic: Bool?) {
        let d = UserDefaults.standard
        if let music { d.set(music, forKey: musicKey) }
        if let sounds { d.set(sounds, forKey: soundsKey) }
        if let newSounds { d.set(newSounds, forKey: newSoundsKey) }
        if let newMusic { d.set(newMusic, forKey: newMusicKey) }
    }

    func start() {
        guard Self.enabled, timer == nil else { return }
        Self.mixWithOthers()
        // Every effect ready before it is needed (all small files).
        warm("sounds/boost.wav", count: 1)
        for n in 0..<16 { warm("sounds/bloops/\(n).mp3", count: 2) }
        for n in 1...80 { warm("sounds/foods_2/\(n).mp3", count: 1) }
        for n in 1...11 { warm("sounds/foods_1/\(n).mp3", count: 2) }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            Task { @MainActor in WyrmSound.shared.tick() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in WyrmSound.shared.pause() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in WyrmSound.shared.resume() }
        }
    }

    private func pause() {
        active = false
        menuIntro?.pause(); menuLoop?.pause(); song?.pause()
        stopBoost()
    }

    private func resume() { active = true; Self.mixWithOthers(); refreshMusic(restart: false) }

    /// Game sounds and music play along with other apps' audio and never
    /// lower or stop it (OM, 2026-11-08); the silent switch still mutes them.
    private static func mixWithOthers() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
    }

    private func tick() {
        let now = Date()
        let dt = Float(min(0.25, max(0, now.timeIntervalSince(last))))
        last = now
        let packed = String(cString: WyrmIOSAudioTake())
        let inGame = match()
        if inGame != inMatch {
            inMatch = inGame
            dying = false
            if inGame { stopMenu(); stopSong(); if musicOn && active { startSong() } }
            else { stopSong(); stopBoost(); refreshMusic(restart: true) }
        }
        let parts = packed.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let boosting = parts.first == "1"
        if parts.count > 1 { for event in parts[1].split(separator: " ") { handle(String(event)) } }
        boost(boosting && inGame && soundsOn && active, dt)
        musicFrame(dt)
    }

    private func handle(_ event: String) {
        guard let kind = event.first else { return }
        let rest = event.dropFirst()
        switch kind {
        case "K": if musicOn && song != nil { dying = true }
        case "B": if soundsOn, let n = Int(rest) { play("sounds/bloops/\(n).mp3", volume: 1) }
        case "F":
            guard soundsOn else { return }
            let values = rest.split(separator: ",").compactMap { Int($0) }
            if newSounds, let n = values.first { play("sounds/foods_2/\(n + 1).mp3", volume: 0.18) }
            else if !newSounds, values.count > 1 { play("sounds/foods_1/\(values[1] + 1).mp3", volume: 0.16) }
        default: break
        }
    }

    private static func url(_ path: String) -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("res/\(path)")
    }

    /// A music file: streamed from disk, never read whole into memory.
    private func player(_ path: String) -> AVAudioPlayer? {
        guard let url = Self.url(path) else { return nil }
        return try? AVAudioPlayer(contentsOf: url)
    }

    /// Makes `count` more players for an effect on the loader queue.
    private func warm(_ path: String, count: Int) {
        guard !loading.contains(path), let url = Self.url(path) else { return }
        loading.insert(path)
        let loop = path.hasSuffix("boost.wav")
        loader.async {
            var made: [AVAudioPlayer] = []
            for _ in 0..<count {
                guard let p = try? AVAudioPlayer(contentsOf: url) else { continue }
                if loop { p.numberOfLoops = -1 }
                p.prepareToPlay()
                made.append(p)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let sound = WyrmSound.shared
                    sound.pools[path, default: []] += made
                    sound.loading.remove(path)
                }
            }
        }
    }

    /// Low priority: an effect with no free player this moment is skipped.
    private func play(_ path: String, volume: Float) {
        guard let pool = pools[path] else { warm(path, count: 2); return }
        if let p = pool.first(where: { !$0.isPlaying }) {
            p.volume = volume
            p.currentTime = 0
            p.play()
        } else if pool.count < 4 {
            warm(path, count: 1)
        }
    }

    /// Main.as bs_v: up by 1/90 a frame while boosting, down by 1/35.
    private func boost(_ on: Bool, _ dt: Float) {
        let frames = dt * 60
        boostVolume = on ? min(1, boostVolume + frames / 90) : max(0, boostVolume - frames / 35)
        if boostVolume <= 0 { stopBoost(); return }
        if boostPlayer == nil { boostPlayer = pools["sounds/boost.wav"]?.first }
        guard let p = boostPlayer else { return }
        p.volume = (boostVolume - 0.001) * 0.115 + 0.001
        if !p.isPlaying { p.play() }
    }

    /// Paused, not thrown away: the same player loops again next boost.
    private func stopBoost() { if boostPlayer?.isPlaying == true { boostPlayer?.pause() }; boostVolume = 0 }

    /// Outside a match: menu_intro, then menu looping, with no gap.
    private func refreshMusic(restart: Bool) {
        guard musicOn, active else { if !musicOn { stopMenu(); stopSong() }; return }
        if inMatch { if song == nil { startSong() } else { song?.play() }; return }
        if !restart, menuLoop != nil || menuIntro != nil {
            if let intro = menuIntro, intro.currentTime > 0, intro.currentTime < intro.duration { intro.play() }
            else { menuLoop?.play() }
            return
        }
        if menuLoop?.isPlaying == true { return }
        stopMenu()
        guard let loop = player("sounds/menu.wav") else { return }
        loop.numberOfLoops = -1
        loop.prepareToPlay()
        menuLoop = loop
        if let intro = player("sounds/menu_intro.wav") {
            intro.prepareToPlay()
            menuIntro = intro
            let start = intro.deviceCurrentTime + 0.05
            intro.play(atTime: start)
            loop.play(atTime: start + intro.duration)   // sample-accurate: no gap
        } else { loop.play() }
    }

    private func stopMenu() { menuIntro?.stop(); menuLoop?.stop(); menuIntro = nil; menuLoop = nil }

    /// Main.as getNextGameSong, then startGameSong.
    private func startSong() {
        stopSong()
        let now = Date()
        var index = -1
        if newMusic {
            if !(0..<8).contains(songIndex) { index = Int.random(in: 0..<8) } else {
                var next = songIndex
                if now.timeIntervalSince(songStarted) > 10 {
                    if Bool.random() { next = (next + 1) % 8 } else {
                        var probe = Int.random(in: 0..<8)
                        for _ in 0..<8 {
                            probe = (probe + 1) % 8
                            if probe != songIndex, now.timeIntervalSince(songLastPlayed[probe]) > 600 { next = probe; break }
                        }
                    }
                }
                if next == songIndex { next = (next + 1) % 8 }
                index = next
            }
        }
        let path = index == -1 ? "sounds/gs_old.mp3" : "sounds/songs/\(index + 1).mp3"
        guard let p = player(path) else { return }
        songIndex = index
        if index >= 0 { songLastPlayed[index] = now }
        songStarted = now
        songVolume = index == -1 ? 0.65 : Self.songVolumes[index]
        p.volume = songVolume
        p.enableRate = true
        song = p
        dying = false
        p.play()
    }

    private func stopSong() { song?.stop(); song = nil }

    /// A song that ended starts the next; your death fades (new) or slows (old) it.
    private func musicFrame(_ dt: Float) {
        guard let p = song else { return }
        if !dying {
            if inMatch, musicOn, active, !p.isPlaying, p.currentTime == 0 { startSong() }
            return
        }
        if newMusic {
            for _ in 0..<min(15, max(1, Int(dt * 60))) { songVolume = songVolume * 0.98 - 0.001 }
            if songVolume <= 0 { stopSong(); dying = false; return }
            p.volume = songVolume
        } else {
            p.rate = p.rate - dt * 0.6
            if p.rate <= 0.5 { stopSong(); dying = false }
        }
    }
}

struct WyrmSoundSection: View {
    @ObservedObject private var sound = WyrmSound.shared
    var body: some View {
        VStack(spacing: 0) {
            WSSectionLabel("Music and sounds")
            WSCard {
                WSBoolRow(title: "Music", detail: "Slither's music: the menu tune everywhere outside a match, game songs from Play on.",
                          on: sound.musicOn, first: true) { sound.setMusic($0) }
                WSBoolRow(title: "New music", detail: "Off plays slither's old game tune instead of the eight new songs.",
                          on: sound.newMusic, first: false) { sound.setNewMusic($0) }
                WSBoolRow(title: "Sounds", detail: "Eating, boosting, and snakes dying on your screen (zoom out and you hear more of them).",
                          on: sound.soundsOn, first: false) { sound.setSounds($0) }
                WSBoolRow(title: "New sounds", detail: "Off plays slither's old eating sounds.",
                          on: sound.newSounds, first: false) { sound.setNewSounds($0) }
            }
        }
    }
}

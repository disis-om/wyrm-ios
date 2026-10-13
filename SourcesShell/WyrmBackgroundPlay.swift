import AVFoundation
import UIKit

/*
 * Background play (OM, 2026-10-13): a match left in the background (the app
 * switcher, the screen locked, a call) keeps running — with the bot on, the
 * snake keeps playing. Android twin: BackgroundPlayService.
 *
 * iOS suspends an app a few seconds after it leaves the screen unless it is
 * playing audio (UIBackgroundModes `audio`, Info.plist). While a match is on
 * and Wyrm is in the background, a silent sound plays, mixed with whatever
 * else is playing, so the app stays awake; Main.m keeps the match ticking on a
 * timer and draws nothing (main.c `wyrm_background_tick`). Back in front, or
 * once the match ends, the sound stops.
 */
@MainActor
final class WyrmBackgroundPlay {
    static let shared = WyrmBackgroundPlay()

    private var screen = 0
    private var inBackground = false
    private var audio: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var task: UIBackgroundTaskIdentifier = .invalid

    private var installed = false

    private init() {}

    func install() {
        guard !installed else { return }
        installed = true
        let center = NotificationCenter.default
        center.addObserver(forName: Notification.Name("WyrmEngineScreenChanged"), object: nil, queue: .main) { note in
            let screen = note.userInfo?["screen"] as? Int ?? 0
            MainActor.assumeIsolated {
                let me = WyrmBackgroundPlay.shared
                me.screen = screen
                // The match ended in the background: nothing to keep awake for.
                if me.inBackground && screen != 2 { me.stop() }
            }
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let me = WyrmBackgroundPlay.shared
                me.inBackground = true
                if me.screen == 2 { me.start() }
            }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let me = WyrmBackgroundPlay.shared
                me.inBackground = false
                me.stop()
            }
        }
    }

    private func start() {
        guard audio == nil else { return }
        // Covers the moment between leaving the screen and the sound starting.
        task = UIApplication.shared.beginBackgroundTask(withName: "Wyrm background play") {
            MainActor.assumeIsolated { WyrmBackgroundPlay.shared.endTask() }
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            engine.attach(node)
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
            engine.connect(node, to: engine.mainMixerNode, format: format)
            // One second of silence, looped.
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100) else { throw CocoaError(.featureUnsupported) }
            silence.frameLength = silence.frameCapacity
            try engine.start()
            node.scheduleBuffer(silence, at: nil, options: .loops)
            node.play()
            audio = engine
            player = node
            WyrmDiagnostics.record("background play on (match keeps running)", category: "LIFECYCLE")
        } catch {
            WyrmDiagnostics.record("background play could not start: \(error.localizedDescription)", category: "LIFECYCLE")
        }
        endTask()
    }

    private func stop() {
        guard audio != nil else { return }
        player?.stop()
        audio?.stop()
        player = nil
        audio = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        WyrmDiagnostics.record("background play off", category: "LIFECYCLE")
    }

    private func endTask() {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
    }
}

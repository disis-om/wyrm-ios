import SwiftUI

/// Play orientation (OM, 2026-10-01): a match can be played upright. Android
/// twin: `data/PlayOrientation.kt` + `WyrmOverlay.switchPlayOrientation`.
///
/// Everything stays the same, only turned: the lobby, the match and the layout
/// editor are portrait when this is on (Main.m keeps the engine surface
/// unrotated; `WyrmLandscapeStage` stops turning SwiftUI). Each orientation
/// keeps its own layout (joystick, boost, zoom bar, on-screen buttons, HUD):
/// the engine holds the one in use, the other waits here, and they swap when
/// the orientation does. Saved under `wyrm.ios.orientation.*` (synced; the
/// portrait flag also travels in the shared document, the same on every
/// platform).
final class WyrmPlayOrientation: ObservableObject {
    static let shared = WyrmPlayOrientation()
    private static let portraitKey = "wyrm.ios.orientation.portrait"
    private static let landscapeLayoutKey = "wyrm.ios.orientation.layout-landscape"
    private static let portraitLayoutKey = "wyrm.ios.orientation.layout-portrait"

    /// The positions that belong to one orientation: controls, then the HUD pieces.
    static let pairs = ["layout.joystick", "layout.boost", "layout.zoom",
                        "hud.minimap", "hud.leaderboard", "hud.stats", "hud.team", "hud.chat"]
    private static let hudFallbacks: [String: CGPoint] = [
        "hud.minimap": CGPoint(x: 0.095, y: 0.205), "hud.leaderboard": CGPoint(x: 0.905, y: 0.155),
        "hud.stats": CGPoint(x: 0.945, y: 0.530), "hud.team": CGPoint(x: 0.095, y: 0.610),
        "hud.chat": CGPoint(x: 0.790, y: 0.075),
    ]

    @Published private(set) var portrait = false

    private init() { portrait = UserDefaults.standard.bool(forKey: Self.portraitKey) }

    /// The engine surface's turn (Main.m). Main thread.
    func publish() { WyrmIOSSetPortraitPlay(portrait) }

    /// After a log in or log out rewrote the defaults (WyrmAccountSync).
    func reloadFromDefaults() {
        portrait = UserDefaults.standard.bool(forKey: Self.portraitKey)
        publish()
    }

    private func setPortrait(_ value: Bool) {
        portrait = value
        UserDefaults.standard.set(value, forKey: Self.portraitKey)
        publish()
    }

    private func savedLayout(portrait upright: Bool) -> [String: Any]? {
        guard let raw = UserDefaults.standard.string(forKey: upright ? Self.portraitLayoutKey : Self.landscapeLayoutKey),
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }

    private func saveLayout(_ layout: [String: Any], portrait upright: Bool) {
        guard let data = try? JSONSerialization.data(withJSONObject: layout),
              let raw = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(raw, forKey: upright ? Self.portraitLayoutKey : Self.landscapeLayoutKey)
    }

    /// This orientation's layout as the engine holds it, or nil before the engine has described it.
    @MainActor private func capture(_ engine: WyrmShellStore) -> [String: Any]? {
        var pairs: [String: [Double]] = [:]
        for prefix in Self.pairs {
            guard let x = engine.setting("\(prefix)_x")?.values.first,
                  let y = engine.setting("\(prefix)_y")?.values.first else { return nil }
            pairs[prefix] = [x, y]
        }
        var keys: [String: [Double]] = [:]
        for key in engine.hotkeys { keys[String(key.id)] = [key.x, key.y] }
        return ["pairs": pairs, "keys": keys]
    }

    /// Writes a stored layout's positions to the engine (sizes and opacities are shared).
    @MainActor private func apply(_ layout: [String: Any], _ engine: WyrmShellStore) {
        let pairs = layout["pairs"] as? [String: Any] ?? [:]
        for prefix in Self.pairs {
            guard let xy = pairs[prefix] as? [Any], xy.count == 2,
                  let x = (xy[0] as? NSNumber)?.doubleValue, let y = (xy[1] as? NSNumber)?.doubleValue,
                  x.isFinite, y.isFinite else { continue }
            engine.moveLayout(prefix, x: x, y: y)
        }
        guard let keys = layout["keys"] as? [String: Any] else { return }
        for key in engine.hotkeys {
            guard let xy = keys[String(key.id)] as? [Any], xy.count == 2,
                  let x = (xy[0] as? NSNumber)?.doubleValue, let y = (xy[1] as? NSNumber)?.doubleValue,
                  x.isFinite, y.isFinite else { continue }
            var moved = key
            moved.x = min(max(x, 0), 1)
            moved.y = min(max(y, 0), 1)
            engine.writeHotkey(moved, log: false)
        }
    }

    /// A first layout for an orientation that has none yet (the same numbers as Android).
    @MainActor private func defaultLayout(portrait upright: Bool, _ engine: WyrmShellStore, keys: [String: Any]?) -> [String: Any] {
        let right = engine.value("layout.joystick_x", 0.8) >= 0.5
        var pairs: [String: [Double]] = [:]
        if upright {
            pairs["layout.joystick"] = [right ? 0.74 : 0.26, 0.80]
            pairs["layout.boost"] = [right ? 0.24 : 0.76, 0.80]
            pairs["layout.zoom"] = [0.50, 0.93]
            pairs["hud.minimap"] = [0.17, 0.115]
            pairs["hud.leaderboard"] = [0.80, 0.11]
            pairs["hud.stats"] = [0.86, 0.32]
            pairs["hud.team"] = [0.17, 0.32]
            pairs["hud.chat"] = [0.50, 0.045]
        } else {
            pairs["layout.joystick"] = [right ? 0.80 : 0.20, 0.72]
            pairs["layout.boost"] = [right ? 0.18 : 0.82, 0.72]
            pairs["layout.zoom"] = [0.50, 0.88]
            for (prefix, point) in Self.hudFallbacks { pairs[prefix] = [point.x, point.y] }
        }
        return ["pairs": pairs, "keys": keys ?? [:]]
    }

    /// Turns play upright or back, keeping the layout in use for the
    /// orientation it was made in and bringing in the other one.
    @MainActor func switchTo(_ upright: Bool, engine: WyrmShellStore) {
        guard upright != portrait else { return }
        guard let current = capture(engine) else {
            // The engine has not described its layout yet: switch without losing it.
            setPortrait(upright)
            return
        }
        saveLayout(current, portrait: portrait)
        apply(savedLayout(portrait: upright) ?? defaultLayout(portrait: upright, engine, keys: current["keys"] as? [String: Any]), engine)
        setPortrait(upright)
    }

    /// Reset layout: the engine's sideways defaults, or the upright first
    /// layout on top of them when playing upright (mask 2 controls, 8 HUD).
    @MainActor func reset(_ masks: [Int32], engine: WyrmShellStore, message: String) {
        for (index, mask) in masks.enumerated() { engine.reset(mask, message: index == masks.count - 1 ? message : "") }
        guard portrait else { return }
        var upright: Set<String> = []
        if masks.contains(2) { upright.formUnion(["layout.joystick", "layout.boost", "layout.zoom"]) }
        if masks.contains(8) { upright.formUnion(["hud.minimap", "hud.leaderboard", "hud.stats", "hud.team", "hud.chat"]) }
        guard !upright.isEmpty else { return }
        // The engine resets on its next frame; the upright positions go on top.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            let all = (self.defaultLayout(portrait: true, engine, keys: nil)["pairs"] as? [String: [Double]]) ?? [:]
            self.apply(["pairs": all.filter { upright.contains($0.key) }], engine)
        }
    }
}

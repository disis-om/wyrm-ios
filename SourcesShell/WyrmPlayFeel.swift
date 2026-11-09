import SwiftUI

/// Play feel (OM, 2026-10-05), Settings › Controls. Android twin:
/// `ui/PlayFeel.kt` (PlayFeelStore), same meaning.
///
/// - customArrow: on (the default) the arrow moves with the player's own start
///   distance and sensitivity; off it moves exactly like slither's (Main.as: start
///   distance, 0.6 catch-up a frame, the 260-unit release drift). Near
///   Original always moves like slither's.
/// - lookAhead: slither's look ahead: the camera sits ahead of the snake
///   toward where it is going (further while boosting). Both modes.
/// - zoomSpring: the zoom bar as a spring: the knob rests in the middle,
///   toward + zooms in, toward - zooms out, and it springs back.
/// - knobCentre (OM, 2026-10-13): the joystick's knob goes back to the centre
///   instead of following the snake (Near Original keeps slither's). Shared
///   document key `joystickKnobCentre`; engine `WyrmIOSSetJoystickKnob`.
///
/// The engine draws and steers (`mobile_controls_set_play_feel` through
/// `WyrmIOSSetPlayFeel`). Saved under `wyrm.ios.play-feel.*`, synced with the
/// account and common to every platform (the shared document:
/// arrowCustomMotion, lookAhead, zoomSpring).
final class WyrmPlayFeelStore: ObservableObject {
    static let shared = WyrmPlayFeelStore()
    static let customArrowKey = "wyrm.ios.play-feel.custom-arrow"
    static let lookAheadKey = "wyrm.ios.play-feel.look-ahead"
    static let zoomSpringKey = "wyrm.ios.play-feel.zoom-spring"
    static let knobCentreKey = "wyrm.ios.play-feel.knob-centre"
    /// Settings › Display › Auto zoom (OM, 2026-11-09): on (the default) the
    /// view zooms out as the snake grows; off keeps the player's own zoom.
    /// Shared document key `autoZoom`; engine `WyrmIOSSetAutoZoom`.
    static let autoZoomKey = "wyrm.ios.play-feel.auto-zoom"

    @Published private(set) var customArrow = true
    @Published private(set) var lookAhead = false
    @Published private(set) var zoomSpring = false
    @Published private(set) var knobCentre = false
    @Published private(set) var autoZoom = true

    private init() { read() }

    /// Called once at launch: the saved choices reach the engine.
    func publish() {
        WyrmIOSSetPlayFeel(!customArrow, lookAhead, zoomSpring ? 1 : 0)
        WyrmIOSSetJoystickKnob(knobCentre)
        WyrmIOSSetAutoZoom(autoZoom)
    }

    /// After a log in or log out rewrote the defaults (WyrmAccountSync).
    func reloadFromDefaults() {
        read()
        publish()
    }

    func setCustomArrow(_ value: Bool) {
        customArrow = value
        UserDefaults.standard.set(value, forKey: Self.customArrowKey)
        publish()
    }

    func setLookAhead(_ value: Bool) {
        lookAhead = value
        UserDefaults.standard.set(value, forKey: Self.lookAheadKey)
        publish()
    }

    func setZoomSpring(_ value: Bool) {
        zoomSpring = value
        UserDefaults.standard.set(value, forKey: Self.zoomSpringKey)
        publish()
    }

    func setKnobCentre(_ value: Bool) {
        knobCentre = value
        UserDefaults.standard.set(value, forKey: Self.knobCentreKey)
        publish()
    }

    func setAutoZoom(_ value: Bool) {
        autoZoom = value
        UserDefaults.standard.set(value, forKey: Self.autoZoomKey)
        publish()
    }

    private func read() {
        let d = UserDefaults.standard
        customArrow = d.object(forKey: Self.customArrowKey) as? Bool ?? true
        lookAhead = d.object(forKey: Self.lookAheadKey) as? Bool ?? false
        zoomSpring = d.object(forKey: Self.zoomSpringKey) as? Bool ?? false
        knobCentre = d.object(forKey: Self.knobCentreKey) as? Bool ?? false
        autoZoom = d.object(forKey: Self.autoZoomKey) as? Bool ?? true
    }
}

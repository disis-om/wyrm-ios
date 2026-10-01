import SwiftUI
import UIKit

/// Assist laser in joystick mode (OM, 2026-10-01). Android twin:
/// `ui/JoystickLaser.kt` (JoystickLaserStore, JoystickLaserPreview).
///
/// With assist on and a joystick (the arrow already has its laser), the engine
/// draws a line from the head where the snake is being steered: the stick's way
/// while it is held, the snake's own heading otherwise (`ui_overlay.c`, patched
/// in by prepare-original-engine.py). Its length is a share of the screen's
/// short side; colour and thickness are the laser's own. Saved under
/// `wyrm.ios.joystick-laser.*`, synced with the account (WyrmAccountSync.rules).
final class WyrmJoystickLaserStore: ObservableObject {
    static let shared = WyrmJoystickLaserStore()
    static let defaultLength = 0.45
    static let range = 0.1...1.0
    private static let onKey = "wyrm.ios.joystick-laser.on"
    private static let lengthKey = "wyrm.ios.joystick-laser.length"

    @Published private(set) var on = true
    @Published private(set) var length = WyrmJoystickLaserStore.defaultLength

    private init() { read() }

    /// Called once at launch: the saved choice reaches the engine.
    func publish() { WyrmIOSSetJoystickLaser(on, Float(length)) }

    /// After a log in or log out rewrote the defaults (WyrmAccountSync).
    func reloadFromDefaults() {
        read()
        publish()
    }

    func setOn(_ value: Bool) {
        on = value
        UserDefaults.standard.set(value, forKey: Self.onKey)
        publish()
    }

    func setLength(_ value: Double) {
        length = min(max(value, Self.range.lowerBound), Self.range.upperBound)
        UserDefaults.standard.set(length, forKey: Self.lengthKey)
        publish()
    }

    static func label(_ length: Double) -> String { "\(Int(length * 100))%" }

    private func read() {
        let defaults = UserDefaults.standard
        on = defaults.object(forKey: Self.onKey) as? Bool ?? true
        let stored = defaults.object(forKey: Self.lengthKey) as? Double ?? Self.defaultLength
        length = min(max(stored, Self.range.lowerBound), Self.range.upperBound)
    }
}

/// Settings › Modes › Assist: the switch, the length and a live preview.
struct WyrmJoystickLaserSection: View {
    @ObservedObject var engine: WyrmShellStore
    @ObservedObject var store = WyrmJoystickLaserStore.shared

    var body: some View {
        let channels = engine.setting("general.laser_color")?.channels ?? [0.5, 1, 0.5, 1]
        let colour = Color(red: channels[0], green: channels[1], blue: channels[2]).opacity(channels.count > 3 ? channels[3] : 1)
        let thickness = engine.setting("general.laser_thickness")?.number ?? 2
        VStack(alignment: .leading, spacing: 0) {
            WSSectionLabel("Assist laser in joystick")
            WSCard {
                WyrmJoystickLaserPreview(length: store.length, on: store.on, colour: colour, thickness: thickness)
                    .wyrmSettingAnchor("app.joystick-laser")
                WSBoolRow(title: "Assist laser in joystick",
                          detail: "With assist on, a line from your head shows where your snake is heading.",
                          on: store.on) { store.setOn($0) }
                if store.on {
                    WSSliderRow(title: "Laser length", valueText: WyrmJoystickLaserStore.label(store.length),
                                detail: "A share of the screen's short side",
                                value: store.length, range: WyrmJoystickLaserStore.range) { store.setLength($0) }
                }
            }
            WSCaption("Colour and thickness are the laser's own, under Advanced · helper lines. Arrow steering keeps its own laser.")
        }
    }
}

/// A slice of arena the shape of this phone held sideways, a snake whose stick
/// sways, and the laser at exactly the length, colour and thickness the arena
/// will draw (length a share of the short side; thickness in screen pixels,
/// scaled to this slice).
struct WyrmJoystickLaserPreview: View {
    let length: Double
    let on: Bool
    let colour: Color
    let thickness: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live preview: the line goes where your snake goes, at this length")
                .font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let screen = UIScreen.main.bounds.size
                    let shortSide = max(1, min(screen.width, screen.height))
                    let aspect = min(max(max(screen.width, screen.height) / shortSide, 1.3), 2.4)
                    let sliceH = min(size.height, size.width / aspect)
                    let sliceW = sliceH * aspect
                    let left = (size.width - sliceW) / 2
                    let top = (size.height - sliceH) / 2
                    // Engine thickness is in pixels of the short side.
                    let scale = sliceH / (shortSide * UIScreen.main.scale)
                    let step = sliceH / 6
                    var gx = left + step / 2
                    while gx < left + sliceW {
                        var gy = top + step / 2
                        while gy < top + sliceH {
                            context.fill(Path(ellipseIn: CGRect(x: gx - 1.4, y: gy - 1.4, width: 2.8, height: 2.8)),
                                         with: .color(.white.opacity(0.06)))
                            gy += step
                        }
                        gx += step
                    }
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let sway = sin(t * .pi / 2.6)
                    let angle = -0.35 + sway * 0.55
                    let head = CGPoint(x: left + sliceW * 0.42, y: top + sliceH * 0.56)
                    let bead = sliceH * 0.055
                    for i in stride(from: 9, through: 1, by: -1) {
                        let bend = angle - Double(i) * 0.06 * sway
                        let centre = CGPoint(x: head.x - cos(bend) * Double(i) * bead * 1.25,
                                             y: head.y - sin(bend) * Double(i) * bead * 1.25)
                        context.fill(Path(ellipseIn: CGRect(x: centre.x - bead, y: centre.y - bead, width: bead * 2, height: bead * 2)),
                                     with: .color(Color(red: 0.44, green: 0.83, blue: 0.65).opacity(0.92)))
                    }
                    let headBead = bead * 1.1
                    context.fill(Path(ellipseIn: CGRect(x: head.x - headBead, y: head.y - headBead, width: headBead * 2, height: headBead * 2)),
                                 with: .color(Color(red: 0.55, green: 0.91, blue: 0.75)))
                    if on {
                        var line = Path()
                        line.move(to: head)
                        line.addLine(to: CGPoint(x: head.x + cos(angle) * length * sliceH,
                                                 y: head.y + sin(angle) * length * sliceH))
                        context.stroke(line, with: .color(colour),
                                       style: StrokeStyle(lineWidth: max(1, thickness * scale), lineCap: .round))
                    }
                }
            }
            .frame(height: 150)
            .background(Color(red: 0.043, green: 0.055, blue: 0.071))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ATheme.rule))
            .overlay(alignment: .topLeading) {
                if !on {
                    Text("OFF").font(.androidWyrm(10, .bold)).tracking(1.2).foregroundColor(.white.opacity(0.6)).padding(10)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }
}

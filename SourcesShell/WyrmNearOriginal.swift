import SwiftUI

/// Near Original (OM, 2026-10-02). Android twin: `ui/NearOriginal.kt`
/// (NearOriginalStore).
///
/// A Home switch that turns the match into slither's own: the original
/// minimap top-left with "server N", the leaderboard top-right in each
/// snake's colour, no Wyrm stats, the fixed original joystick and boost
/// button, and the original arrow in the snake's colour (only its size follows
/// the player). The engine draws all of it (`ui_overlay.c`,
/// `mobile_controls.c`, patched in by prepare-original-engine.py) from the
/// original game's numbers; nothing the player set is overwritten, so turning
/// it off brings everything back as it was. Display and touch only.
///
/// Saved under `wyrm.ios.near-original.*` (WyrmAccountSync.rules) and in the
/// account's shared document as `nearOriginal`, the same on Android and iOS.
final class WyrmNearOriginalStore: ObservableObject {
    static let shared = WyrmNearOriginalStore()
    private static let onKey = "wyrm.ios.near-original.on"

    @Published private(set) var on = false
    /// The lobby arena's number, for the minimap's "server N" (0 = unknown).
    private var server = 0

    private init() { read() }

    /// Called once at launch: the saved choice reaches the engine.
    func publish() { WyrmIOSSetNearOriginal(on, Int32(server)) }

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

    func setServer(_ number: Int) {
        let next = max(number, 0)
        guard next != server else { return }
        server = next
        publish()
    }

    private func read() {
        on = UserDefaults.standard.object(forKey: Self.onKey) as? Bool ?? false
    }
}

/// Home › Near Original: a loadout row with a switch instead of a chevron.
struct WyrmNearOriginalRow: View {
    @ObservedObject var store = WyrmNearOriginalStore.shared
    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(ATheme.rowRule).frame(height: 1)
            HStack(spacing: 0) {
                WyrmLoadoutIcon(symbol: "arrow.clockwise")
                Spacer().frame(width: 12)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Near Original").font(.androidWyrm(15.5)).foregroundColor(ATheme.ink).lineLimit(1)
                    Text("Slither's own HUD, joystick and arrow. Only on-screen buttons stay movable.")
                        .font(.androidWyrm(12)).foregroundColor(ATheme.quiet)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 10)
                WSInkSwitch(on: store.on) { store.setOn($0) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
    }
}

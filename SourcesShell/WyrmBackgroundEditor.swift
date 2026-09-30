import SwiftUI

/// Adjust arena background size (OM, 2026-10-01). Android twin:
/// `ArenaBackgroundSizeEditor` in LayoutEditors.kt.
///
/// The AI arena sideways, as the HUD editor opens it, with the minimap and the
/// leaderboard where the player keeps them, and one slider along the bottom.
/// The engine redraws the floor at the new size every frame, so the player
/// sees exactly what they will get. The floor is the one chosen in Skin ›
/// Arena background. One size for both modes; Cancel puts the old one back.
enum WyrmBackgroundSize {
    /// The engine's default background scale (599/4096, `user_settings.c`).
    static let standard = 599.0 / 4096.0
    static let range = 0.05...4.0

    /// Slider position (0...1) ⇄ scale, on a log scale so small sizes get room.
    static func scale(at t: Double) -> Double {
        range.lowerBound * pow(range.upperBound / range.lowerBound, min(max(t, 0), 1))
    }

    static func slider(of scale: Double) -> Double {
        log(min(max(scale, range.lowerBound), range.upperBound) / range.lowerBound) / log(range.upperBound / range.lowerBound)
    }

    /// "100%" is the arena's own size.
    static func label(_ scale: Double) -> String { "\(Int((scale / standard * 100).rounded()))%" }

    @MainActor static func write(_ scale: Double, engine: WyrmShellStore) {
        for id in ["normal.bg_scale", "assist.bg_scale"] { engine.write(id: id, values: [scale]) }
    }
}

struct WyrmBackgroundSizeEditor: View {
    @ObservedObject var engine: WyrmShellStore
    let onClose: () -> Void
    @State private var original: [Double] = []
    @State private var scale = WyrmBackgroundSize.standard

    var body: some View {
        WyrmLandscapeStage { size, insets in canvas(size, insets) }
            .statusBar(hidden: true)
            .onAppear {
                original = [engine.value("normal.bg_scale", WyrmBackgroundSize.standard),
                            engine.value("assist.bg_scale", WyrmBackgroundSize.standard)]
                scale = original[0]
            }
    }

    private func point(_ prefix: String, _ fallback: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: engine.value("\(prefix)_x", fallback.x) * size.width, y: engine.value("\(prefix)_y", fallback.y) * size.height)
    }

    private func canvas(_ size: CGSize, _ insets: EdgeInsets) -> some View {
        let screen = UIScreen.main.scale
        let minimap = min(max(engine.value("general.minimap_size", 300), 128), 512) / screen
        let lbScale = 1 + Double(min(max(Int(engine.value("general.lb_font", 1)), 0), 2)) * 0.16
        return ZStack {
            // Clear: the AI arena shows through; stray touches never reach it.
            Color.black.opacity(0.001)
            // References only: where the player keeps them.
            Text("MAP").font(.androidWyrm(14, .bold)).foregroundColor(ATheme.ink)
                .frame(width: minimap, height: minimap)
                .background(Circle().fill(ATheme.card.opacity(0.18)))
                .overlay(Circle().stroke(ATheme.ink.opacity(0.76), lineWidth: 3))
                .position(point("hud.minimap", CGPoint(x: 0.095, y: 0.205), size))
            Text("LEADERBOARD\n1  Wyrm Player     9503\n2  Northwind       2819\n3  Orbit            418\n4  Meadow           389\n5  Drift            248")
                .font(.androidWyrm(12)).lineSpacing(5).foregroundColor(ATheme.ink)
                .frame(width: 250 * lbScale / screen, height: 132 * lbScale / screen, alignment: .topLeading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ATheme.card.opacity(0.92)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ATheme.rule))
                .position(point("hud.leaderboard", CGPoint(x: 0.905, y: 0.155), size))
            VStack {
                Spacer()
                panel.frame(maxWidth: 460).padding(.bottom, max(insets.bottom, 0) + 14)
            }
        }
        .clipped()
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("ARENA BACKGROUND SIZE").font(.androidWyrm(10, .bold)).tracking(1.2).foregroundColor(ATheme.quiet)
                Spacer()
                Text(WyrmBackgroundSize.label(scale)).font(.androidWyrm(15, .bold)).foregroundColor(ATheme.ink).monospacedDigit()
            }
            Slider(value: Binding(
                get: { WyrmBackgroundSize.slider(of: scale) },
                set: { t in
                    scale = WyrmBackgroundSize.scale(at: t)
                    WyrmBackgroundSize.write(scale, engine: engine)
                }
            ), in: 0...1)
            .tint(ATheme.ink)
            HStack(spacing: 8) {
                Text("Smaller looks further away").font(.androidWyrm(10.5)).foregroundColor(ATheme.quiet)
                Spacer()
                action("CANCEL") {
                    engine.write(id: "normal.bg_scale", values: [original.first ?? WyrmBackgroundSize.standard])
                    engine.write(id: "assist.bg_scale", values: [original.last ?? WyrmBackgroundSize.standard])
                    onClose()
                }
                action("RESET") {
                    scale = WyrmBackgroundSize.standard
                    WyrmBackgroundSize.write(scale, engine: engine)
                }
                action("SAVE", filled: true) { onClose() }
            }
        }
        .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 10)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(ATheme.card.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(ATheme.rule))
    }

    private func action(_ label: String, filled: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(label).font(.androidWyrm(9, .bold)).tracking(1).foregroundColor(filled ? ATheme.onInk : ATheme.quiet)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Capsule().fill(filled ? ATheme.ink : Color.clear))
        }.buttonStyle(.plain)
    }
}

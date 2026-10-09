import SwiftUI

/// Snake look (OM, 2026-10-05). The AI arena with the real snakes, on the mode
/// the Modes page is on. Every change is written at once. Cancel puts the old
/// values back; Done leaves them.
struct WyrmSnakeLookEditor: View {
    @ObservedObject var engine: WyrmShellStore
    let close: () -> Void
    @State private var assist: Bool
    @State private var original: [String: Double] = [:]

    private static let remembered = [
        "normal.render_mode", "assist.render_mode",
        "normal.spine", "assist.spine", "assist.hide_cosmetics",
        "normal.spine_width", "assist.spine_width", "normal.snake_shadow", "assist.snake_shadow",
    ]

    init(engine: WyrmShellStore, close: @escaping () -> Void) {
        self.engine = engine
        self.close = close
        _assist = State(initialValue: engine.snakeLookAssist)
    }

    private var group: String { assist ? "assist" : "normal" }

    private var renderIndex: Int {
        let raw = engine.value("\(group).render_mode")
        guard raw.isFinite else { return 0 }
        return min(max(Int(raw.rounded()), 0), 3)
    }

    private var spineOn: Bool { engine.value("\(group).spine") >= 0.5 }
    private var spineWidth: Double { min(max(engine.value("\(group).spine_width", 0.1), 0), 1) }
    private var shadowOn: Bool { engine.value("\(group).snake_shadow") >= 0.5 }
    private var hideOn: Bool { engine.value("assist.hide_cosmetics") >= 0.5 }

    var body: some View {
        WyrmLandscapeStage { size, insets in canvas(size, insets) }
            .statusBar(hidden: true)
            .onAppear {
                guard original.isEmpty else { return }
                assist = engine.snakeLookAssist
                remember()
            }
    }

    private func canvas(_ size: CGSize, _ insets: EdgeInsets) -> some View {
        ZStack {
            // Clear: the AI arena shows through; stray touches never reach it.
            Color.black.opacity(0.001)
            VStack {
                Spacer()
                panel.frame(maxWidth: min(520, max(size.width - 24, 0)))
                    .padding(.bottom, max(insets.bottom, 0) + 14)
            }
        }
        .clipped()
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SNAKE LOOK").font(.androidWyrm(10, .bold)).tracking(1.2).foregroundColor(ATheme.quiet)
                WSSegmented(options: ["Normal", "Assist"], selected: assist ? 1 : 0) { pick in
                    let on = pick == 1
                    assist = on
                    WyrmIOSSetEditorAssist(on)
                }
                WSSegmented(options: ["Texture", "Solid", "Flat", "Skinless"], selected: renderIndex) { index in
                    engine.write(id: "\(group).render_mode", values: [Double(index)])
                }
            }
            .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
            WSBoolRow(title: "Spine", detail: "A thin white line down the middle of every snake.",
                      on: spineOn, first: true) { on in
                engine.write(id: "\(group).spine", values: [on ? 1 : 0])
            }
            if spineOn {
                WSSliderRow(title: "Spine width", valueText: WyrmSpineWidth.label(spineWidth),
                            detail: "0 hides it; full is as wide as the snake",
                            value: spineWidth, range: 0...1) { value in
                    engine.write(id: "\(group).spine_width", values: [value])
                }
            }
            WSBoolRow(title: "Snake shadow", detail: "The soft shadow the original app draws under every snake.",
                      on: shadowOn) { on in
                engine.write(id: "\(group).snake_shadow", values: [on ? 1 : 0])
            }
            if assist {
                WSBoolRow(title: "Hide own tag and accessories",
                          detail: "While assist is on, your tag, accessory and Wyrm look are hidden.",
                          on: hideOn) { on in
                    engine.write(id: "assist.hide_cosmetics", values: [on ? 1 : 0])
                }
            }
            HStack(spacing: 8) {
                Spacer()
                action("CANCEL") {
                    restore()
                    close()
                }
                action("DONE", filled: true) { close() }
            }
            .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 10)
        }
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

    private func remember() {
        var saved: [String: Double] = [:]
        for id in Self.remembered { saved[id] = engine.value(id) }
        original = saved
    }

    private func restore() {
        for (id, value) in original { engine.write(id: id, values: [value]) }
    }
}

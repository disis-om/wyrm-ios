import SwiftUI
import UIKit

/// The look of the arena's team roster and chat window (OM, 2026-10-04).
/// Android twin: `ui/TeamHud.kt` (TeamHudStore), same keys, order and meaning.
///
/// The engine draws both (`android_team.c`), in the match and in the layout
/// editor; these are the numbers it draws them with, set from the editor's
/// long-press options: roster size, opacity, back-plate, width, height, name
/// and data colours; chat width, height, name and message colours, and its
/// own back-plate. The chat's size and
/// opacity stay the engine's `layout.chat_scale` / `layout.chat_opacity`.
/// Saved under `wyrm.ios.team-hud.*`, synced with the account
/// (WyrmAccountSync.rules, platform document: layouts are per device).
final class WyrmTeamHudStore: ObservableObject {
    static let shared = WyrmTeamHudStore()

    /// Editor ids are `teamhud.<key>`; the order is the engine's.
    static let keys = ["team_scale", "team_opacity", "team_width", "team_height", "team_name", "team_data",
                       "chat_width", "chat_height", "chat_name", "chat_text",
                       "team_panel", "chat_panel", "stats_panel",
                       // The stats panel's text colour (OM, 2026-10-11), appended:
                       // the engine reads this order; an older engine ignores it.
                       "stats_text",
                       // The leaderboard's WIDTH and HEIGHT (OM, 2026-10-13), appended
                       // likewise: multiples of the board's own width and row height.
                       "lb_width", "lb_height",
                       // The chat window's ONLINE tab (OM, 2026-10-14): name and
                       // "@username · server" colours, appended likewise.
                       "online_name", "online_data",
                       // GLOBAL's own colours and the folded chat button drawn like
                       // the keys: label + border, fill (9 = grey), size, opacity
                       // (OM, 2026-10-18), appended likewise.
                       "global_name", "global_text",
                       "chatbtn_label", "chatbtn_fill", "chatbtn_scale", "chatbtn_opacity",
                       // The chat button's label opacity (OM, 2026-11-01), appended likewise.
                       "chatbtn_label_opacity"]
    private static let defaults: [Double] = [1, 1, 340, 210, 0, 0, 400, 270, 0, 0, 1, 1, 1, 0, 0.75, 0.75, 0, 0,
                                             0, 0, 0, 9, 1, 0.9, 1]
    private static let ranges: [ClosedRange<Double>] = [0.65...1.60, 0.05...1, 220...900, 120...800, 0...8, 0...8,
                                                        240...1000, 150...900, 0...8, 0...8,
                                                        0...1, 0...1, 0...1,
                                                        0...8,
                                                        0.25...3, 0.25...3,
                                                        0...8, 0...8,
                                                        0...8, 0...8,
                                                        0...8, 0...9, 0.6...2.5, 0.1...1,
                                                        0...1]
    /// The engine's palette; 0 keeps the theme's colour.
    static let colourNames = ["Theme", "White", "Black", "Yellow", "Cyan", "Green", "Pink", "Orange", "Red"]
    /// White, yellow, cyan, green, pink and orange take dark text; black, red light (OM, 2026-10-14).
    static func isLight(_ index: Int) -> Bool {
        let rgb = [0, 0xFFFFFF, 0x111111, 0xFFD54A, 0x4DD9FF, 0x5BE37D, 0xFF6FB5, 0xFF9A3C, 0xFF5A5A]
        guard index > 0, index < rgb.count else { return false }
        let c = rgb[index]
        let l = 0.2126 * Double((c >> 16) & 255) / 255 + 0.7152 * Double((c >> 8) & 255) / 255 + 0.0722 * Double(c & 255) / 255
        return l > 0.55
    }
    static let swatches: [Color?] = [nil] + [0xFFFFFF, 0x111111, 0xFFD54A, 0x4DD9FF, 0x5BE37D,
                                             0xFF6FB5, 0xFF9A3C, 0xFF5A5A].map { (rgb: Int) -> Color? in
        Color(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
              blue: Double(rgb & 0xFF) / 255)
    }

    @Published private(set) var values: [Double] = WyrmTeamHudStore.defaults

    private init() { read() }

    static func owns(_ id: String) -> Bool { id.hasPrefix("teamhud.") && keys.contains(String(id.dropFirst(8))) }

    func value(_ key: String) -> Double {
        guard let index = Self.keys.firstIndex(of: key) else { return 0 }
        return values[index]
    }

    func range(_ key: String) -> ClosedRange<Double> {
        Self.keys.firstIndex(of: key).map { Self.ranges[$0] } ?? 0...1
    }

    func set(_ id: String, _ next: Double) {
        let key = id.hasPrefix("teamhud.") ? String(id.dropFirst(8)) : id
        guard let index = Self.keys.firstIndex(of: key), next.isFinite else { return }
        var clamped = min(max(next, Self.ranges[index].lowerBound), Self.ranges[index].upperBound)
        if key.hasSuffix("_name") || key.hasSuffix("_data") || key.hasSuffix("_text")
            || key == "chatbtn_label" || key == "chatbtn_fill" { clamped = clamped.rounded() }
        values[index] = clamped
        UserDefaults.standard.set(clamped, forKey: "wyrm.ios.team-hud.\(key)")
        publish()
    }

    /// Called once at launch: the saved look reaches the engine.
    func publish() {
        let floats = values.map { Float($0) }
        floats.withUnsafeBufferPointer { WyrmIOSSetTeamHudStyle($0.baseAddress, Int32($0.count)) }
    }

    /// After a log in or log out rewrote the defaults (WyrmAccountSync).
    func reloadFromDefaults() {
        read()
        publish()
    }

    private func read() {
        let d = UserDefaults.standard
        if !d.bool(forKey: "wyrm.ios.team-hud.lbOriginalV1") {
            d.set(0.75, forKey: "wyrm.ios.team-hud.lb_width")
            d.set(0.75, forKey: "wyrm.ios.team-hud.lb_height")
            d.set(true, forKey: "wyrm.ios.team-hud.lbOriginalV1")
        }
        values = Self.keys.indices.map { index in
            let stored = (d.object(forKey: "wyrm.ios.team-hud.\(Self.keys[index])") as? NSNumber)?.doubleValue
            guard let stored, stored.isFinite else { return Self.defaults[index] }
            return min(max(stored, Self.ranges[index].lowerBound), Self.ranges[index].upperBound)
        }
        // GLOBAL used TEAM's colours until 2026-10-18: keep what was chosen.
        for (global, team) in [("global_name", "chat_name"), ("global_text", "chat_text")]
        where d.object(forKey: "wyrm.ios.team-hud.\(global)") == nil {
            if let g = Self.keys.firstIndex(of: global), let t = Self.keys.firstIndex(of: team) { values[g] = values[t] }
        }
    }
}

/// The arena chat window's message box was tapped (the engine counts taps,
/// the shell's timer takes them): a one-line composer above the keyboard. The
/// match carries on behind it.
@MainActor
final class WyrmTeamComposer: ObservableObject {
    static let shared = WyrmTeamComposer()
    /// The bar and the shell overlay are on screen. Stays true until the bar
    /// has slid away and the shell has faded out, so the portrait app under it
    /// never shows for a frame (OM, 2026-10-09: the lobby flickered on Send).
    @Published private(set) var open = false
    /// The bar (and, sideways, the Wyrm keys) slid in from the bottom.
    @Published private(set) var shown = false
    @Published var draft = ""
    /// The message box was tapped on the GLOBAL tab: Send writes to everyone.
    @Published private(set) var global = false
    private var generation = 0

    func takeEngineRequests() {
        if WyrmIOSTakeTeamComposerRequest() > 0, !open { present() }
    }

    /// In: the overlay first (it fades in over two frames), then the bar
    /// slides up from the bottom with the keys.
    func present() {
        global = WyrmArenaFeed.shared.globalTab
        generation += 1
        let mine = generation
        open = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) { [weak self] in
            guard let self, self.generation == mine, self.open else { return }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) { self.shown = true }
        }
    }

    /// Out: the bar and keys slide down, the shell fades out, and only then
    /// does the bar leave the tree.
    func close() {
        guard open else { return }
        WyrmKeyboardController.shared.dismiss()
        generation += 1
        let mine = generation
        withAnimation(.easeIn(duration: 0.22)) { shown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
            WyrmIOSSetShellOverlay(false)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
                guard let self, self.generation == mine else { return }
                self.open = false
            }
        }
    }

    /// The match ended under the bar: gone at once, no slide.
    func closeNow() {
        WyrmKeyboardController.shared.dismiss()
        generation += 1
        shown = false
        open = false
        WyrmIOSSetShellOverlay(false)
    }
}

/// One line above the keyboard, with Send; a tap outside closes it.
struct WyrmArenaComposerBar: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var composer = WyrmTeamComposer.shared
    @ObservedObject var team: WyrmTeamStore
    @ObservedObject private var keyboard = WyrmKeyboardController.shared
    @FocusState private var focused: Bool

    var body: some View {
        nativeComposer
        .onAppear {
            if !composer.global && composer.draft.isEmpty { composer.draft = team.failedDraft }
            // During a match the whole SwiftUI shell is hidden over the engine
            // (Main.m apply_shell_visibility), so this bar was never on screen
            // and its field could not take focus: no keyboard, in either
            // orientation (OM, 2026-10-06). Shown, clear, while it is open;
            // Main.m fades it in so no stale frame shows (2026-10-09).
            WyrmIOSSetShellOverlay(true)
        }
        .onDisappear {
            focused = false
            WyrmIOSSetShellOverlay(false)
        }
        // The keys follow the bar: up with it, down with it.
        .onChange(of: composer.shown) { shown in
            if shown { focusSoon() } else { focused = false }
        }
    }

    /// As the bar starts to rise, and once more if the first try did not take.
    private func focusSoon() {
        focused = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !keyboard.focused, composer.shown else { return }
            focused = false
            DispatchQueue.main.async { if composer.shown && composer.open { focused = true } }
        }
    }

    /// Same window coordinates in both native game orientations. The SwiftUI
    /// keyboard safe area seats this bar above Apple's keyboard automatically.
    private var nativeComposer: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.001).ignoresSafeArea(.container)
                .onTapGesture { composer.close() }
            VStack(spacing: 6) {
                if !composer.global && !team.deliveryError.isEmpty {
                    Text(team.deliveryError).font(.androidWyrm(12)).foregroundColor(wyrmScopedColours.ink)
                        .padding(8).background(wyrmScopedColours.card)
                }
                field
            }.frame(maxWidth: 560)
                .padding(.horizontal, 12).padding(.bottom, 10)
                // This root already ignores UIKit keyboard safe areas. Use the
                // logical overlap directly; global frames have physical axes
                // when UIKit keeps the window portrait for internal rotation.
                .padding(.bottom, keyboard.occlusion)
                .offset(y: composer.shown ? 0 : 140)
                .opacity(composer.shown ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .modifier(WyrmDismissKeyboardOnScroll())
    }

    private var field: some View {
            HStack(spacing: 8) {
                TextField(composer.global ? "Message everyone" : "Message the team", text: $composer.draft, prompt: wyrmPrompt(composer.global ? "Message everyone" : "Message the team"))
                    .font(.androidWyrm(15))
                    .foregroundColor(wyrmScopedColours.ink)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .onChange(of: composer.draft) { value in
                        if value.count > 280 { composer.draft = String(value.prefix(280)) }
                    }
                Button(action: send) {
                    Text("SEND").font(.androidWyrm(12, .bold)).tracking(1.2).foregroundColor(wyrmScopedColours.onInk)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(wyrmScopedColours.ink.opacity(blank ? 0.35 : 1)))
                }
                .disabled(blank)
            }
            .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 6)
            .background(Capsule().fill(wyrmScopedColours.card.opacity(0.97)))
            .overlay(Capsule().stroke(wyrmScopedColours.rule, lineWidth: 1))
            .background(WyrmKeyboardLayoutProbe(kind: "composer"))
    }

    private var blank: Bool { composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send() {
        guard !blank else { return }
        if composer.global {
            WyrmArenaFeed.shared.sendGlobal(composer.draft)
        } else {
            guard team.send(composer.draft) else { return }
        }
        composer.draft = ""
        composer.close()
    }
}

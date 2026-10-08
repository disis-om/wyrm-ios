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
                       "team_panel", "chat_panel", "stats_panel"]
    private static let defaults: [Double] = [1, 1, 340, 210, 0, 0, 400, 270, 0, 0, 1, 1, 1]
    private static let ranges: [ClosedRange<Double>] = [0.65...1.60, 0.05...1, 220...900, 120...800, 0...8, 0...8,
                                                        240...1000, 150...900, 0...8, 0...8,
                                                        0...1, 0...1, 0...1]
    /// The engine's palette; 0 keeps the theme's colour.
    static let colourNames = ["Theme", "White", "Black", "Yellow", "Cyan", "Green", "Pink", "Orange", "Red"]
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
        if key.hasSuffix("_name") || key.hasSuffix("_data") || key.hasSuffix("_text") { clamped = clamped.rounded() }
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
        values = Self.keys.indices.map { index in
            let stored = (d.object(forKey: "wyrm.ios.team-hud.\(Self.keys[index])") as? NSNumber)?.doubleValue
            guard let stored, stored.isFinite else { return Self.defaults[index] }
            return min(max(stored, Self.ranges[index].lowerBound), Self.ranges[index].upperBound)
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
    private var generation = 0

    func takeEngineRequests() {
        if WyrmIOSTakeTeamComposerRequest() > 0, !open { present() }
    }

    /// In: the overlay first (it fades in over two frames), then the bar
    /// slides up from the bottom with the keys.
    func present() {
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
        generation += 1
        shown = false
        open = false
        WyrmIOSSetShellOverlay(false)
    }
}

/// One line above the keyboard, with Send; a tap outside closes it.
struct WyrmArenaComposerBar: View {
    @ObservedObject var composer = WyrmTeamComposer.shared
    @ObservedObject var team: WyrmTeamStore
    @ObservedObject private var keyboard = WyrmKeyboardController.shared
    @ObservedObject private var orientation = WyrmPlayOrientation.shared
    @FocusState private var focused: Bool
    /// This composer's place in the keyboard's set of sideways canvases.
    @State private var keyboardHost = UUID()

    var body: some View {
        Group {
            if orientation.portrait {
                upright
            } else {
                sideways
            }
        }
        .onAppear {
            // Sideways the keys are drawn in the arena's own canvas, as in the
            // Ready Room (OM, 2026-10-06: no keyboard came up in a sideways
            // match). Registered before the field takes focus, which asks.
            keyboard.enterLandscapeHost(keyboardHost)
            // During a match the whole SwiftUI shell is hidden over the engine
            // (Main.m apply_shell_visibility), so this bar was never on screen
            // and its field could not take focus: no keyboard, in either
            // orientation (OM, 2026-10-06). Shown, clear, while it is open;
            // Main.m fades it in so no stale frame shows (2026-10-09).
            WyrmIOSSetShellOverlay(true)
        }
        .onDisappear {
            keyboard.leaveLandscapeHost(keyboardHost)
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
            DispatchQueue.main.async { focused = true }
        }
    }

    /// Playing upright: the phone's own docked keys, the bar rising above them.
    private var upright: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { composer.close() }
            field
                .frame(maxWidth: 560)
                .padding(.horizontal, 12).padding(.bottom, 10)
                // Rises with the phone's keys and sinks with them (2026-10-09).
                .offset(y: composer.shown ? 0 : 140)
                .opacity(composer.shown ? 1 : 0)
        }
    }

    /// Playing sideways: the bar and the Wyrm keys inside the landscape canvas
    /// the match is drawn in, the bar just above the keys.
    private var sideways: some View {
        WyrmLandscapeStage { size, safe in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.001)
                    .onTapGesture { composer.close() }
                VStack(spacing: 8) {
                    field.frame(maxWidth: 560)
                    if keyboard.embedded && (keyboard.focused || composer.shown) {
                        WyrmKeyboardView(compact: true)
                            .frame(width: min(size.width - safe.leading - safe.trailing - 24,
                                              WyrmKeyboardController.landscapeWidth * keyboard.scale))
                            .shadow(color: ATheme.ink.opacity(0.18), radius: 18, y: 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                // Bar and keys as one sheet: up from the bottom of the arena,
                // and back down into it after Send (2026-10-09).
                .offset(y: composer.shown ? 0 : size.height)
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private var field: some View {
            HStack(spacing: 8) {
                TextField("Message the team", text: $composer.draft)
                    .font(.androidWyrm(15))
                    .foregroundColor(ATheme.ink)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .onChange(of: composer.draft) { value in
                        if value.count > 280 { composer.draft = String(value.prefix(280)) }
                    }
                Button(action: send) {
                    Text("SEND").font(.androidWyrm(12, .bold)).tracking(1.2).foregroundColor(ATheme.onInk)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Capsule().fill(ATheme.ink.opacity(blank ? 0.35 : 1)))
                }
                .disabled(blank)
            }
            .padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 6)
            .background(Capsule().fill(ATheme.card.opacity(0.97)))
            .overlay(Capsule().stroke(ATheme.rule, lineWidth: 1))
    }

    private var blank: Bool { composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send() {
        guard !blank else { return }
        team.send(composer.draft)
        composer.draft = ""
        composer.close()
    }
}

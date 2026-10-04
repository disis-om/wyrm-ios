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
                       "team_panel", "chat_panel"]
    private static let defaults: [Double] = [1, 1, 340, 210, 0, 0, 400, 270, 0, 0, 1, 1]
    private static let ranges: [ClosedRange<Double>] = [0.65...1.60, 0.05...1, 220...900, 120...800, 0...8, 0...8,
                                                        240...1000, 150...900, 0...8, 0...8,
                                                        0...1, 0...1]
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
    @Published var open = false
    @Published var draft = ""

    func takeEngineRequests() {
        if WyrmIOSTakeTeamComposerRequest() > 0, !open {
            withAnimation(.easeOut(duration: 0.18)) { open = true }
        }
    }

    func close() {
        withAnimation(.easeOut(duration: 0.18)) { open = false }
    }
}

/// One line above the keyboard, with Send; a tap outside closes it.
struct WyrmArenaComposerBar: View {
    @ObservedObject var composer = WyrmTeamComposer.shared
    @ObservedObject var team: WyrmTeamStore
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture { composer.close() }
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
            .frame(maxWidth: 560)
            .padding(.horizontal, 12).padding(.bottom, 10)
        }
        .onAppear { focused = true }
    }

    private var blank: Bool { composer.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func send() {
        guard !blank else { return }
        team.send(composer.draft)
        composer.draft = ""
        composer.close()
    }
}

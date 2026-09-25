import SwiftUI

/*
 * Settings search.
 *
 * Every setting is indexed by its label, hint and page. A result is the real
 * control — switch, slider, segmented pill, colour — working right there in
 * the hub. The arrow in its card opens the page it lives on, scrolls to it,
 * opens whatever fold holds it and blinks it twice.
 */

/// The setting a result asked a page to reveal, and the query itself — kept
/// here so a theme change, which rebuilds the whole shell, keeps the results.
final class WyrmSettingsFocus: ObservableObject {
    static let shared = WyrmSettingsFocus()
    @Published var query = ""
    /// Engine setting id, `hotkey.<id>`, or an `app.` id for shell settings.
    @Published private(set) var target: String?
    /// Bumped each time a target is asked for, so a repeat still blinks.
    @Published private(set) var pulse = 0

    func reveal(_ id: String) {
        target = id
        pulse += 1
    }

    func finish(_ id: String) { if target == id { target = nil } }

    /// True when the target is one of these ids — pages use it to open the
    /// fold or pick the mode tab that holds it.
    func wants(_ ids: [String]) -> Bool { target.map(ids.contains) ?? false }
    func wants(_ id: String) -> Bool { target == id }
}

extension View {
    /// Makes a row findable by settings search: a scroll anchor plus two blinks
    /// when it is the one a result opened.
    /// `card` fits the glow to a whole `WSCard` instead of one row.
    func wyrmSettingAnchor(_ id: String, card: Bool = false) -> some View {
        modifier(WyrmSettingBlink(id: id, inset: card ? 16 : 2, radius: card ? 14 : 12)).id(id)
    }
}

private struct WyrmSettingBlink: ViewModifier {
    let id: String
    let inset: CGFloat
    let radius: CGFloat
    @ObservedObject private var focus = WyrmSettingsFocus.shared
    @State private var lit = false

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(ATheme.link.opacity(lit ? 0.16 : 0))
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(ATheme.link.opacity(lit ? 0.7 : 0), lineWidth: 1.5))
                    .padding(.horizontal, inset).padding(.vertical, 2)
                    .allowsHitTesting(false)
            )
            .onAppear { if focus.target == id { blink() } }
            .onChange(of: focus.pulse) { _ in if focus.target == id { blink() } }
    }

    /// Waits for the page to finish sliding in and scrolling, then two blinks.
    private func blink() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            for _ in 0..<2 {
                withAnimation(.easeInOut(duration: 0.22)) { lit = true }
                try? await Task.sleep(nanoseconds: 300_000_000)
                withAnimation(.easeInOut(duration: 0.22)) { lit = false }
                try? await Task.sleep(nanoseconds: 260_000_000)
            }
            focus.finish(id)
        }
    }
}

/// One searchable setting. `route` is nil for settings on the hub itself.
struct WyrmSettingsEntry: Identifiable {
    let id: String
    let title: String
    let detail: String
    let page: String
    let route: WyrmDesignRoute?
    var keywords = ""
    let control: () -> AnyView

    func matches(_ words: [String]) -> Bool {
        let haystack = "\(title) \(detail) \(page) \(keywords)".lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }
}

/// Every setting a page draws, placed where that page draws it. Settings no
/// page shows are left out, so every arrow lands on something.
enum WyrmSettingsIndex {
    static let controlsIDs = ["controls.joystick_mode", "controls.handedness", "controls.boost_mode",
                              "controls.joystick_size", "controls.boost_size", "controls.opacity"]
    static let botIDs = ["general.bot_circle", "general.bot_radius"]
    static let modeFood: Set<String> = ["food_type", "food_scale", "food_float", "food_flicker", "const_food_scale", "uniform_food_color", "food_color"]

    static func place(_ setting: EngineSetting) -> (WyrmDesignRoute, String)? {
        let id = setting.id, group = setting.group
        guard !setting.label.isEmpty, !id.hasPrefix("tags.") else { return nil }
        if botIDs.contains(id) { return (.bot, "Bot") }
        if group == "general.bot" { return nil }
        if group == "general" || group.hasPrefix("general.") { return (.display, "Display") }
        if controlsIDs.contains(id) { return (.controls, "Controls") }
        if group == "controls.zoom" { return (.controls, "Controls · Zoom bar") }
        if id == "keys.key_scale" || id == "keys.opacity" { return (.buttons, "On-screen buttons") }
        if group == "normal" || group == "assist" {
            let mode = group == "assist" ? "Assist" : "Normal"
            if WyrmFoodPage.isFood(setting) { return (.food, "Food · \(mode)") }
            if modeFood.contains(WyrmModesPage.local(setting)) { return nil }
            return (.modes, "Modes · \(mode)")
        }
        return nil
    }

    @MainActor
    static func entries(engine: WyrmShellStore) -> [WyrmSettingsEntry] {
        var result: [WyrmSettingsEntry] = engine.settings.compactMap { setting in
            guard let placed = place(setting) else { return nil }
            return WyrmSettingsEntry(id: setting.id, title: setting.label, detail: setting.hint, page: placed.1, route: placed.0,
                                     keywords: setting.id.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " ")) {
                AnyView(WSTypedRow(setting: setting, first: true, engine: engine))
            }
        }
        result += WyrmButtonsContent.allowed(engine.hotkeys).map { key in
            WyrmSettingsEntry(id: "hotkey.\(key.id)", title: "\(key.name) button", detail: "Show it in matches, and whether a press toggles or holds",
                              page: "On-screen buttons", route: .buttons, keywords: "hotkey key toggle hold") {
                AnyView(WyrmLiveHotkeyRow(id: key.id, engine: engine))
            }
        }
        if engine.setting("controls.joystick_mode")?.index == 2 {
            result.append(WyrmSettingsEntry(id: "app.arrow-style", title: "Arrow style", detail: "Drawn and image arrows, size, brightness and colour",
                                            page: "Controls · Arrow", route: .controls, keywords: "arrow skin steering cursor brightness") {
                AnyView(WyrmArrowSettingsCard(engine: engine).padding(.horizontal, -16).padding(.bottom, 2))
            })
        }
        result += [
            WyrmSettingsEntry(id: "app.theme", title: "Theme", detail: "Paper, dark and colour appearances", page: "Accessibility",
                              route: .themes, keywords: "appearance dark mode colour color " + WyrmThemeID.allCases.map(\.rawValue).joined(separator: " ")) {
                AnyView(WyrmThemeQuickPicker())
            },
            WyrmSettingsEntry(id: "app.theme-intensity", title: "Theme intensity", detail: "50% is the original look", page: "Accessibility",
                              route: .themes, keywords: "strength richer appearance") { AnyView(WyrmThemeIntensityRow()) },
            WyrmSettingsEntry(id: "app.keyboard", title: "Keyboard size and transparency", detail: "Also behind the gear key on the keyboard",
                              page: "Accessibility · Keyboard", route: .themes, keywords: "keys typing opacity bigger smaller") {
                AnyView(WyrmKeyboardLookRows())
            },
            WyrmSettingsEntry(id: "app.developer", title: "Developer Mode", detail: "Local diagnostics and export tools", page: "Settings",
                              route: nil, keywords: "logs diagnostics debug") { AnyView(WyrmDeveloperToggle()) },
        ]
        result.append(WyrmSettingsEntry(id: "app.notify.all", title: "All notifications", detail: "The iOS permission for Wyrm",
                                        page: "Notifications", route: .notificationSettings, keywords: "alerts push permission") {
            AnyView(WyrmNotifyRow(kind: nil, title: "All notifications", detail: "Tap to manage the iOS permission."))
        })
        for group in WyrmNotificationSettingsPage.groups {
            for row in group.1 {
                result.append(WyrmSettingsEntry(id: "app.notify.\(row.0)", title: row.1, detail: row.2, page: "Notifications · \(group.0)",
                                                route: .notificationSettings, keywords: "notification alert push") {
                    AnyView(WyrmNotifyRow(kind: row.0, title: row.1, detail: row.2))
                })
            }
        }
        return result
    }
}

/// A hotkey row that reads the key fresh each time, so it stays live.
private struct WyrmLiveHotkeyRow: View {
    let id: Int
    @ObservedObject var engine: WyrmShellStore
    var body: some View {
        if let key = engine.hotkeys.first(where: { $0.id == id }) { WyrmHotkeyRow(key: key, engine: engine) }
    }
}

private struct WyrmNotifyRow: View {
    let kind: String?
    let title: String
    let detail: String
    @ObservedObject var prefs = WyrmNotificationPrefs.shared
    var body: some View {
        let master = prefs.systemEnabled
        if let kind {
            WSBoolRow(title: title, detail: detail, on: master && prefs.isEnabled(kind), first: true) { _ in prefs.set(kind, !prefs.isEnabled(kind)) }
                .disabled(!master).opacity(master ? 1 : 0.46)
        } else {
            WSBoolRow(title: title, detail: detail, on: master, first: true) { _ in prefs.openSystem() }
        }
    }
}

private struct WyrmThemeQuickPicker: View {
    @ObservedObject var store = WyrmThemeStore.shared
    var body: some View {
        HStack {
            WSRowText(title: "Theme", detail: store.theme.description)
            Spacer()
            Picker("", selection: Binding(get: { store.theme }, set: { store.select($0) })) {
                ForEach(WyrmThemeID.allCases) { Text($0.displayName).tag($0) }
            }.pickerStyle(.menu).tint(ATheme.ink)
        }.padding(.horizontal, 14).padding(.vertical, 10)
    }
}

private struct WyrmThemeIntensityRow: View {
    @ObservedObject var store = WyrmThemeStore.shared
    var body: some View {
        WSSliderRow(title: "Theme intensity", valueText: "\(Int((store.intensity * 100).rounded()))%",
                    value: store.intensity, range: 0...1, first: true) { store.setIntensity($0) }
    }
}

private struct WyrmDeveloperToggle: View {
    @AppStorage("wyrm.ios.developer-mode") var developerMode = false
    var body: some View {
        WSBoolRow(title: "Developer Mode", detail: "Local diagnostics and export tools", on: developerMode, first: true) { developerMode = $0 }
    }
}

/// Keyboard size and transparency — the same values as the keyboard's gear key.
struct WyrmKeyboardLookRows: View {
    @ObservedObject var keyboard = WyrmKeyboardController.shared
    var body: some View {
        VStack(spacing: 0) {
            WSSliderRow(title: "Keyboard size", valueText: "\(Int((keyboard.scale * 100).rounded()))%",
                        value: keyboard.scale, range: 0.8...1.3, step: 0.05, first: true) { keyboard.setScale($0) }
            WSSliderRow(title: "Keyboard transparency", valueText: "\(Int(((1 - keyboard.opacity) * 100).rounded()))%",
                        value: 1 - keyboard.opacity, range: 0...0.6) { keyboard.setOpacity(1 - $0) }
        }
    }
}

/// The search field at the top of the hub.
struct WyrmSettingsSearchField: View {
    @Binding var query: String
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .semibold)).foregroundColor(ATheme.quiet)
            TextField("Search settings", text: $query)
                .font(.androidWyrm(15)).foregroundColor(ATheme.ink)
                .textInputAutocapitalization(.never).disableAutocorrection(true)
                .submitLabel(.search).focused($focused)
            if !query.isEmpty {
                Button { withAnimation(.easeOut(duration: 0.18)) { query = "" } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(ATheme.chevron)
                }.buttonStyle(.plain).transition(.opacity.combined(with: .scale))
            }
        }
        .padding(.horizontal, 14).frame(height: 44)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(ATheme.card))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(focused ? ATheme.ink.opacity(0.35) : ATheme.rule, lineWidth: 1))
        .padding(.horizontal, 16).padding(.bottom, 14)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// Results: each card is the page it belongs to, the live control, and an
/// arrow to go to its place.
struct WyrmSettingsSearchResults: View {
    let query: String
    @ObservedObject var engine: WyrmShellStore
    let open: (WyrmDesignRoute?) -> Void

    var body: some View {
        let words = query.lowercased().split(separator: " ").map(String.init)
        let all = WyrmSettingsIndex.entries(engine: engine).filter { $0.matches(words) }
        let first = query.lowercased()
        let ranked = all.sorted { a, b in
            let pa = a.title.lowercased().hasPrefix(first), pb = b.title.lowercased().hasPrefix(first)
            return pa != pb ? pa : a.title < b.title
        }
        VStack(alignment: .leading, spacing: 12) {
            Text(ranked.isEmpty ? "Nothing matches \u{201C}\(query)\u{201D}" : "\(ranked.count) result\(ranked.count == 1 ? "" : "s")")
                .font(.androidWyrm(11.5, .semibold)).tracking(0.6).foregroundColor(ATheme.quiet)
                .padding(.horizontal, 20)
            ForEach(ranked.prefix(40)) { entry in
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(entry.page.uppercased()).font(.androidWyrm(10, .bold)).tracking(1.1).foregroundColor(ATheme.quiet)
                        Spacer()
                        Button {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            WyrmSettingsFocus.shared.reveal(entry.id)
                            open(entry.route)
                        } label: {
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).foregroundColor(ATheme.ink)
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(ATheme.well))
                                .overlay(Circle().stroke(ATheme.rule, lineWidth: 1))
                        }
                        .buttonStyle(WSPressStyle())
                        .accessibilityLabel("Open \(entry.title) on \(entry.page)")
                    }
                    .padding(.leading, 14).padding(.trailing, 10).padding(.top, 10)
                    entry.control()
                }
                .background(ATheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                .padding(.horizontal, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: ranked.map(\.id))
    }
}

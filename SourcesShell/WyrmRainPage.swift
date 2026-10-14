import SwiftUI
import UIKit

/*
 * Snakey Rain (OM, 2026-10-14): the page opens like Loadout's Controls and
 * Modes (back, title, the Wyrm look), with the character's snake drawn the
 * way the Skin tab draws it, and Characters / Settings / Login below. A
 * character's skin, presets, tags and accessories are the Skin tab's own
 * pickers; only what Rain's character packet carries is offered. In the
 * arena the Rain key (an on-screen key, placed in Arrange the UI) opens
 * WyrmRainPanel. Same as Android's SnakeyRainScreen.kt.
 */

private enum WyrmRainTab: Int, CaseIterable {
    case characters, settings, login
    var title: String { ["Characters", "Settings", "Login"][rawValue] }
}

private enum WyrmRainEditor: String {
    case pattern = "Build a pattern", presets = "Presets", tags = "Tags", accessories = "Accessories"
}

extension WyrmRainCharacter {
    /// "/n" is preset n; anything else is bead letters.
    var presetIndex: Int? {
        guard skin.hasPrefix("/") || skin.hasPrefix("\\"), let n = Int(skin.dropFirst()), WyrmSkinCatalog.presets.indices.contains(n) else { return nil }
        return n
    }
    var beadGroups: [Int] { skin.compactMap { WyrmSkinCatalog.group(for: $0) } }
    var tagAsset: WyrmTagAsset? {
        guard let ntl = Int(tag) else { return nil }
        return WyrmSkinCatalog.tags.first { $0.ntlID == ntl && !WyrmSkinCatalog.isWyrmTag($0.ntlID) }
    }
    var previewGroups: [Int] {
        if let p = presetIndex { return WyrmSkinCatalog.presets[p] }
        let beads = beadGroups
        return beads.isEmpty ? (WyrmSkinCatalog.presets.first ?? [7]) : beads
    }
}

struct WyrmRainSnakePreview: View {
    @ObservedObject var textures: WyrmSkinTextureLibrary
    let character: WyrmRainCharacter?
    var body: some View {
        let c = character ?? WyrmRainCharacter()
        WyrmSkinPreview(textures: textures, groups: c.previewGroups, colors: [], preset: c.presetIndex ?? 0,
                        custom: c.presetIndex == nil && !c.beadGroups.isEmpty,
                        accessoryID: c.cosmetic == 255 ? -1 : c.cosmetic, tagID: c.tagAsset?.id ?? -1,
                        backgroundID: 0, chain: 1, swing: 1, tagScale: 1,
                        trialLook: WyrmTrailSkin.Look(hair: -1, hairTone: 0.22, ears: -1, glasses: -1))
    }
}

/// Rain's link in one word, with a dot: Connected (green) or Disconnected (OM, 2026-10-14).
struct WyrmRainStatusLine: View {
    @ObservedObject var rain = WyrmRain.shared
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(rain.connected ? ATheme.live : ATheme.quiet).frame(width: 8, height: 8)
            Text(!rain.connected ? "Disconnected" : rain.running ? "Connected · \(rain.count) bots" : "Connected")
                .font(.androidWyrm(13.5, .semibold)).foregroundColor(ATheme.ink).lineLimit(1)
        }
    }
}

/// The Skin tab's flow (OM, 2026-10-14: "yeh Wyrm app ka hi part hai"):
/// the preview stays put and only changes with the character; under the rule
/// each page comes in with the Skin tab's spring, and a page inside has the
/// round back arrow at the rule's top-left.
struct WyrmRainPage: View {
    @ObservedObject var engine: WyrmShellStore
    let close: () -> Void
    @ObservedObject private var rain = WyrmRain.shared
    @StateObject private var textures = WyrmSkinTextureLibrary.acquire()
    @State private var tab = WyrmRainTab.characters
    @State private var openID: String?
    @State private var editor: WyrmRainEditor?
    @State private var selection: Set<String> = []

    private var open: WyrmRainCharacter? { openID.flatMap { id in rain.characters.first { $0.id == id } } }
    private var previewed: WyrmRainCharacter? { open ?? rain.characters.first(where: \.enabled) ?? rain.characters.first }
    private var pageKey: String { "\(openID ?? "home")|\(editor?.rawValue ?? "")" }

    private func go(_ id: String?, _ next: WyrmRainEditor?) {
        withAnimation(.interactiveSpring(response: 0.42, dampingFraction: 0.86, blendDuration: 0.1)) { openID = id; editor = next }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    Button(action: close) {
                        Text("‹ Play").font(.androidWyrm(16)).foregroundColor(ATheme.link)
                            .padding(.horizontal, 6).padding(.vertical, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Spacer()
                }
                Text("Snakey Rain").font(.androidWyrm(16, .semibold)).foregroundColor(ATheme.ink)
            }.frame(height: 40).padding(.horizontal, 14)
            WyrmRainSnakePreview(textures: textures, character: previewed).frame(height: 218)
            Rectangle().fill(ATheme.rule).frame(height: 1).padding(.horizontal, 20)
            ZStack {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if let c = open, let editor {
                            inlineHeader(editor.rawValue) { go(c.id, nil) }
                            editorPage(c, editor)
                        } else if let c = open {
                            inlineHeader(c.label.isEmpty ? "Character" : c.label) { go(nil, nil) }
                            characterPage(c)
                        } else {
                            HStack(spacing: 10) {
                                WyrmRainStatusLine().frame(maxWidth: .infinity, alignment: .leading)
                                WSInkSwitch(on: rain.enabled) { rain.enable($0) }
                            }.padding(.leading, 20).padding(.trailing, 16).padding(.top, 12)
                            WSSegmented(options: WyrmRainTab.allCases.map(\.title), selected: tab.rawValue) { next in
                                withAnimation(.easeInOut(duration: 0.22)) { tab = WyrmRainTab(rawValue: next) ?? .characters }
                            }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                            Group {
                                switch tab {
                                case .characters: charactersTab
                                case .settings: settingsTab
                                case .login: WyrmRainLoginTab()
                                }
                            }.id(tab).transition(.opacity)
                        }
                        Spacer().frame(height: 60)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(pageKey)
                .transition(.opacity.combined(with: .scale(scale: 0.985, anchor: .top)))
            }
            .frame(maxHeight: .infinity)
            .clipped()
        }
        .foregroundColor(ATheme.ink)
        .background(ATheme.paper.ignoresSafeArea())
        .onAppear { textures.prepare() }
    }

    /// The Skin tab's inline header: round back arrow at the rule's top-left.
    private func inlineHeader(_ title: String, back: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Button(action: back) {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold)).foregroundColor(ATheme.ink)
                    .frame(width: 34, height: 34).background(WyrmGlass.native ? Color.clear : ATheme.card.opacity(0.92)).clipShape(Circle())
            }.modifier(WyrmGlassCircleButton()).accessibilityLabel("Back")
            Text(title).font(.androidWyrm(18, .bold)).lineLimit(1)
            Spacer()
            Text("AUTO-SAVED").font(.androidWyrm(8.5, .bold)).tracking(1).foregroundColor(ATheme.live)
        }.padding(.horizontal, 20).padding(.top, 15).padding(.bottom, 12)
    }

    // MARK: Characters

    private func roundButton(_ symbol: String, _ label: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundColor(ATheme.onInk)
                .frame(width: 36, height: 36).background(enabled ? ATheme.ink : ATheme.ink.opacity(0.3)).clipShape(Circle())
        }.buttonStyle(WSPressStyle()).disabled(!enabled).accessibilityLabel(label)
    }

    @ViewBuilder private var charactersTab: some View {
        let list = rain.characters
        HStack(spacing: 12) {
            if selection.isEmpty {
                Text("CHARACTERS · \(list.count)/\(WyrmRain.maxCharacters)").font(.androidWyrm(11.5, .semibold)).tracking(0.92)
                    .foregroundColor(ATheme.quiet).frame(maxWidth: .infinity, alignment: .leading)
                roundButton("plus", "Add a character", enabled: list.count < WyrmRain.maxCharacters) {
                    if let made = rain.add() { go(made.id, nil) }
                }
            } else {
                roundButton("xmark", "Cancel") { selection = [] }
                Text("\(selection.count) selected").font(.androidWyrm(15, .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                Button("Delete") { rain.remove(selection); selection = [] }
                    .font(.androidWyrm(15, .semibold)).foregroundColor(ATheme.badge).buttonStyle(.plain)
                    .padding(.horizontal, 10).padding(.vertical, 8)
            }
        }
        .frame(minHeight: 36).padding(.leading, 20).padding(.trailing, 16).padding(.top, 14).padding(.bottom, 8)
        if list.isEmpty {
            WSCaption("No characters yet. Tap + to add one; it starts as wyrm.bot.")
        } else {
            WSCard {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, c in
                    if index > 0 { WSHairline() }
                    characterRow(c)
                }
            }
            WSCaption("Tap a character to edit it. Touch and hold to select, then delete.")
        }
    }

    private func characterRow(_ c: WyrmRainCharacter) -> some View {
        let picked = selection.contains(c.id)
        return HStack(spacing: 12) {
            if !selection.isEmpty {
                ZStack {
                    Circle().stroke(picked ? ATheme.ink : ATheme.chevron, lineWidth: 1.5)
                    if picked { Circle().fill(ATheme.ink); Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundColor(ATheme.paper) }
                }.frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(c.label.isEmpty ? "Character" : c.label).font(.androidWyrm(15.5)).foregroundColor(c.enabled ? ATheme.ink : ATheme.quiet).lineLimit(1)
                Text((c.name.isEmpty ? "No name" : c.name) + (c.enabled ? "" : " · off")).font(.androidWyrm(11.5)).foregroundColor(ATheme.quiet).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            WyrmMiniSnake(textures: textures, groups: Array(c.previewGroups.prefix(24))).frame(width: 92, height: 26)
            if selection.isEmpty { Text("›").font(.androidWyrm(17)).foregroundColor(ATheme.chevron) }
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 62)
        .background(picked ? ATheme.hover : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            if selection.isEmpty { go(c.id, nil) }
            else if picked { selection.remove(c.id) } else { selection.insert(c.id) }
        }
        .onLongPressGesture { selection.insert(c.id) }
    }

    private func field(_ title: String, _ value: String, first: Bool, mono: Bool = false, placeholder: String, set: @escaping (String) -> Void) -> some View {
        VStack(spacing: 0) {
            if !first { WSHairline() }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.androidWyrm(12)).foregroundColor(ATheme.quiet)
                TextField(placeholder, text: Binding(get: { value }, set: set))
                    .font(mono ? .system(size: 15.5, design: .monospaced) : .androidWyrm(15.5))
                    .textInputAutocapitalization(.never).disableAutocorrection(true)
            }.padding(.horizontal, 14).padding(.vertical, 10)
        }
    }

    private func update(_ c: WyrmRainCharacter, _ change: (inout WyrmRainCharacter) -> Void) {
        var next = c; change(&next); rain.update(next)
    }

    @ViewBuilder private func characterPage(_ c: WyrmRainCharacter) -> some View {
        WSSectionLabel("Character")
        WSCard {
            field("Character name", c.label, first: true, placeholder: WyrmRainCharacter.defaultName) { v in update(c) { $0.label = String(v.prefix(24)) } }
            field("In-game name", c.name, first: false, placeholder: WyrmRainCharacter.defaultName) { v in update(c) { $0.name = String(v.prefix(24)) } }
            field("Skin code · \(c.skin.count)/250", c.skin, first: false, mono: true, placeholder: "Type or paste a skin code") { v in update(c) { $0.skin = String(v.prefix(250)) } }
        }
        WSSectionLabel("Look")
        WSCard {
            WSValueRow(title: WyrmRainEditor.pattern.rawValue, value: c.presetIndex == nil && !c.beadGroups.isEmpty ? "\(c.beadGroups.count) beads" : "", first: true) { go(c.id, .pattern) }
            WSValueRow(title: WyrmRainEditor.presets.rawValue, value: c.presetIndex.map { String(format: "%02d", $0 + 1) } ?? "") { go(c.id, .presets) }
            WSValueRow(title: WyrmRainEditor.tags.rawValue, value: c.tagAsset.map { "#\($0.ntlID)" } ?? "None") { go(c.id, .tags) }
            WSValueRow(title: WyrmRainEditor.accessories.rawValue, value: c.cosmetic == 255 ? "None" : String(format: "%02d", c.cosmetic + 1)) { go(c.id, .accessories) }
        }
        WSSectionLabel("Storm")
        WSCard {
            WSBoolRow(title: "Use this character", detail: "Rain spawns bots with it", on: c.enabled, first: true) { on in update(c) { $0.enabled = on } }
        }
        Spacer().frame(height: 18)
        WSCard { WSActionRow(title: "Delete character", first: true, danger: true) { rain.remove([c.id]); go(nil, nil) } }
    }

    /// The Skin tab's own pickers, writing to this character.
    @ViewBuilder private func editorPage(_ c: WyrmRainCharacter, _ editor: WyrmRainEditor) -> some View {
        switch editor {
        case .pattern:
            let groups = c.presetIndex == nil ? c.beadGroups : []
            // Rain's character packet carries the bead letters only (250 at most).
            WyrmPatternBuilder(textures: textures, groups: groups, colors: [], maxBeads: 250) { next, _ in
                update(c) { $0.skin = String(WyrmSkinCatalog.code(for: next).prefix(250)) }
            }
        case .presets:
            LazyVStack(spacing: 0) {
                ForEach(WyrmSkinCatalog.presets.indices, id: \.self) { index in
                    Button { update(c) { $0.skin = "/\(index)" } } label: {
                        HStack(spacing: 12) {
                            Text(String(format: "%02d", index + 1)).font(.androidWyrm(10.5, .bold))
                                .foregroundColor(c.presetIndex == index ? ATheme.live : ATheme.quiet).frame(width: 24)
                            WyrmMiniSnake(textures: textures, groups: WyrmSkinCatalog.presets[index]).frame(height: 38)
                        }.frame(maxWidth: .infinity).frame(height: 57)
                    }.buttonStyle(.plain).accessibilityLabel("Default skin \(index + 1)")
                    Rectangle().fill(ATheme.rule).frame(height: 1)
                }
            }.padding(.horizontal, 20)
        case .tags:
            // Rain's bots carry NTL's tags; Wyrm's own stickers cannot travel in its packet.
            let current = c.tagAsset?.id ?? -1
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                Button { update(c) { $0.tag = "-1"; $0.hash = "" } } label: { noneTile(current < 0) }.buttonStyle(.plain)
                ForEach(WyrmSkinCatalog.tagPickerOrder.filter { !WyrmSkinCatalog.isWyrmTag($0.ntlID) }) { item in
                    Button { update(c) { $0.tag = String(item.ntlID); $0.hash = "" } } label: {
                        imageTile(textures.tagThumbnails[item.id], inset: 7, selected: current == item.id, badge: "\(item.ntlID)")
                    }.buttonStyle(.plain).accessibilityLabel("Tag \(item.ntlID)")
                }
            }.padding(.horizontal, 16)
        case .accessories:
            let current = c.cosmetic == 255 ? -1 : c.cosmetic
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                Button { update(c) { $0.cosmetic = 255 } } label: { noneTile(current < 0) }.buttonStyle(.plain)
                ForEach(WyrmSkinCatalog.accessories) { item in
                    Button { update(c) { $0.cosmetic = item.id } } label: {
                        imageTile(textures.accessoryThumbnails[item.id], inset: 4, selected: current == item.id, badge: nil)
                    }.buttonStyle(.plain).accessibilityLabel("Accessory \(item.id + 1)")
                }
            }.padding(.horizontal, 16)
        }
    }

    private func check() -> some View {
        Image(systemName: "checkmark").font(.system(size: 10, weight: .heavy)).foregroundColor(ATheme.paper)
            .frame(width: 18, height: 18).background(ATheme.ink).clipShape(Circle()).padding(6)
    }

    private func noneTile(_ selected: Bool) -> some View {
        Text("NONE").font(.androidWyrm(9, .bold)).tracking(0.7).foregroundColor(ATheme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity).aspectRatio(1, contentMode: .fit)
            .background(ATheme.card.opacity(0.92)).clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(selected ? ATheme.ink : ATheme.rule, lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topTrailing) { if selected { check() } }
    }

    private func imageTile(_ image: CGImage?, inset: CGFloat, selected: Bool, badge: String?) -> some View {
        WyrmAtlasImage(image: image).padding(inset).aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
            .background(ATheme.card.opacity(0.92)).clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(selected ? ATheme.ink : ATheme.rule, lineWidth: selected ? 2 : 1))
            .overlay(alignment: .bottomTrailing) { if let badge { Text(badge).font(.androidWyrm(7.5, .bold)).foregroundColor(ATheme.quiet).padding(6) } }
            .overlay(alignment: .topTrailing) { if selected { check() } }
    }

    // MARK: Settings

    @ViewBuilder private var settingsTab: some View {
        WSSectionLabel("Bots", top: 14)
        WyrmRainSliders(keys: ["maxBots", "size", "separation", "finalAng", "rOC", "rotationDir"])
        WSSectionLabel("Movement")
        WyrmRainSliders(keys: ["period", "amplitude", "ranRate"])
        WSSectionLabel("Characters")
        WSCard {
            WSBoolRow(title: "Cycle through characters", detail: "Bots change character over time", on: rain.evolveEnabled, first: true) { rain.flag("evolveEnabled", $0) }
            WSBoolRow(title: "Player rotation", detail: "Rotate your snake with the storm", on: rain.rotationEnabled) { rain.flag("rotationEnabled", $0) }
        }
        if rain.evolveEnabled { WyrmRainSliders(keys: ["evolveTime", "evolveBots"]).padding(.top, 10) }
        VStack(spacing: 9) {
            WSPrimaryButton(label: "Arrange arena UI") { engine.openLayoutEditor() }
            WSOutlineButton(label: "Reset settings") { rain.reset() }
        }.padding(.horizontal, 16).padding(.top, 22)
        WSCaption(rain.enabled ? "The Rain button sits with your on-screen buttons. Drag it, or touch and hold it for size and opacity."
                               : "Turn on Snakey Rain to place its button in the arena.")
    }
}

func wyrmRainSettingName(_ key: String) -> String {
    ["maxBots": "Maximum bots", "size": "Tornado size", "separation": "Tornado separation", "finalAng": "Final angle",
     "rOC": "Angle change rate", "rotationDir": "Clockwise direction", "period": "Wigwag period", "amplitude": "Wigwag amplitude",
     "ranRate": "Random rate", "evolveTime": "Cycle time", "evolveBots": "Characters per cycle",
     "panelSize": "Panel size", "panelOpacity": "Panel opacity", "panelBack": "Back"][key] ?? key
}

func wyrmRainSettingValue(_ key: String, _ v: Double) -> String {
    switch key {
    case "rOC": return String(format: "%.2f", v)
    case "period", "ranRate": return "\(Int(v.rounded())) ms"
    case "evolveTime": return "\(Int(v.rounded())) s"
    case "finalAng": return "\(Int(v.rounded()))°"
    case "panelSize", "panelOpacity", "panelBack": return "\(Int((v * 100).rounded()))%"
    default: return "\(Int(v.rounded()))"
    }
}

struct WyrmRainSliders: View {
    @ObservedObject var rain = WyrmRain.shared
    let keys: [String]
    var body: some View {
        WSCard {
            ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                let range = WyrmRain.ranges.first { $0.0 == key }?.1 ?? 0...1
                let value = rain.config[key] ?? WyrmRain.defaults[key] ?? range.lowerBound
                WSSliderRow(title: wyrmRainSettingName(key), valueText: wyrmRainSettingValue(key, value),
                            value: value, range: range, first: index == 0) { rain.set(key, $0) }
            }
        }
    }
}

// MARK: Login

struct WyrmRainLoginTab: View {
    @ObservedObject private var rain = WyrmRain.shared
    @State private var personal = false
    @State private var user = ""
    @State private var pass = ""
    var body: some View {
        WSSectionLabel("Account", top: 14)
        WSCard {
            WSBoolRow(title: "Use my personal account", detail: personal ? "Sign in with your own Rain account" : "The public account is signed in",
                      on: personal, first: true) { on in
                personal = on
                if on { user = ""; pass = "" } else {
                    user = WyrmRain.publicUser; pass = WyrmRain.publicPassword
                    if rain.personal { rain.credentials("", "", personal: false) }
                }
            }
            row("Username") {
                TextField("Username", text: $user).textContentType(.username)
            }
            row("Password") {
                SecureField("Password", text: $pass).textContentType(.password)
            }
        }
        Spacer().frame(height: 14)
        WSPrimaryButton(label: "Connect", enabled: !personal || (!user.trimmingCharacters(in: .whitespaces).isEmpty && !pass.isEmpty)) {
            rain.credentials(user, pass, personal: personal); rain.enable(true)
        }.padding(.horizontal, 16)
        WSCaption("Your password stays on this phone, locked. The public account is shared by everyone.")
        Color.clear.frame(height: 0).onAppear {
            personal = rain.personal
            user = rain.personal ? rain.username : WyrmRain.publicUser
            pass = rain.personal ? rain.password : WyrmRain.publicPassword
        }
    }
    private func row<F: View>(_ title: String, @ViewBuilder _ field: () -> F) -> some View {
        VStack(spacing: 0) {
            WSHairline()
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.androidWyrm(12)).foregroundColor(ATheme.quiet)
                field().font(.androidWyrm(15.5)).foregroundColor(personal ? ATheme.ink : ATheme.quiet)
                    .textInputAutocapitalization(.never).disableAutocorrection(true).disabled(!personal)
            }.padding(.horizontal, 14).padding(.vertical, 10)
        }
    }
}

// MARK: Arena panel

/// A key as the arena draws its own: paper, an ink edge, ink and a green ring while it is on.
private struct WyrmRainKey: View {
    let label: String
    let lit: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.androidWyrm(13.5, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundColor(lit ? ATheme.onInk : ATheme.ink)
                .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 46)
                .background(lit ? ATheme.ink : ATheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(ATheme.ink.opacity(lit ? 0.82 : 0.48), lineWidth: 1.5))
                .padding(3)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ATheme.live.opacity(lit ? 0.6 : 0), lineWidth: 2.5))
        }.buttonStyle(WSPressStyle())
    }
}

/// The arena's Rain panel (OM, 2026-10-14): opened by the Rain key, tabs for
/// the controls, modes, nearby snakes and live settings. Its size, opacity
/// and back plate are the player's ("panelSize", "panelOpacity", "panelBack").
struct WyrmRainPanel: View {
    @ObservedObject private var rain = WyrmRain.shared
    @State private var open = false
    @State private var seen = WyrmRain.shared.panelRequests
    @State private var tab = 0
    private var scale: CGFloat { CGFloat(min(max(rain.config["panelSize"] ?? 1, 0.7), 1.3)) }

    /// Panel size scales the whole panel, type and keys too, not only its box (OM, 2026-10-14).
    var body: some View {
        panel.frame(width: 380, height: 340)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: 380 * scale, height: 340 * scale, alignment: .topLeading)
    }

    @ViewBuilder private var panel: some View {
        let opacity = min(max(rain.config["panelOpacity"] ?? 1, 0.3), 1)
        let back = min(max(rain.config["panelBack"] ?? 0.94, 0), 1)
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Snakey Rain").font(.androidWyrm(16, .bold)).foregroundColor(ATheme.ink)
                    WyrmRainStatusLine()
                }
                Spacer()
                Button { open = false; layout() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(ATheme.ink)
                        .frame(width: 34, height: 34).background(ATheme.card).clipShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel("Close")
            }.padding(.leading, 16).padding(.trailing, 8).padding(.top, 10)
            WSSegmented(options: ["Controls", "Modes", "Target", "Settings"], selected: tab) { tab = $0 }
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) { content }.padding(.bottom, 10)
            }
            // The knob at the bottom centre drags the panel anywhere (OM, 2026-10-14).
            Capsule().fill(ATheme.ink.opacity(0.32)).frame(width: 42, height: 5)
                .frame(maxWidth: .infinity).frame(height: 26).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    // The view follows the finger, so each step is finger minus grab point.
                    WyrmIOSMoveRainPanel(Double((v.location.x - v.startLocation.x) * scale),
                                         Double((v.location.y - v.startLocation.y) * scale))
                })
                .accessibilityLabel("Move Rain panel")
        }
        .background(ATheme.paper.opacity(back))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ATheme.rule.opacity(max(back, 0.25)), lineWidth: 1))
        .shadow(color: ATheme.ink.opacity(0.12 * back), radius: 18 * back)
        .padding(6)
        .opacity(opacity)
        .onChange(of: rain.panelRequests) { now in if now != seen { seen = now; open.toggle(); layout() } }
        .onChange(of: rain.enabled) { on in if !on { open = false }; layout() }
        .onChange(of: rain.config["panelSize"] ?? 1) { _ in layout() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WyrmEngineScreenChanged"))) { _ in open = false; layout() }
        .onAppear { layout() }
    }

    private func row<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 4) { c() }.padding(.horizontal, 12)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case 0:
            row {
                WyrmRainKey(label: rain.running ? "Stop" : "Start", lit: rain.running) { if rain.running { rain.stop() } else { rain.start() } }
                WyrmRainKey(label: "Boost", lit: rain.boosting) { rain.boost() }
                WyrmRainKey(label: "Reconnect", lit: false) { rain.disconnect(); rain.connect() }
            }
            if rain.rotationEnabled {
                row {
                    WyrmRainKey(label: "Rotate left", lit: rain.rotation == -1) { rain.rotate(rain.rotation == -1 ? 0 : -1) }
                    WyrmRainKey(label: "Rotate right", lit: rain.rotation == 1) { rain.rotate(rain.rotation == 1 ? 0 : 1) }
                }
            }
            Text("Mode · \(WyrmRain.modes[min(max(rain.mode, 1), 14) - 1])").font(.androidWyrm(12.5)).foregroundColor(ATheme.quiet)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16).padding(.top, 8)
        case 1:
            ForEach(0..<7, id: \.self) { r in
                row {
                    ForEach(1...2, id: \.self) { c in
                        let id = r * 2 + c
                        WyrmRainKey(label: WyrmRain.modes[id - 1], lit: rain.mode == id) { rain.setMode(id) }
                    }
                }
            }
        case 2:
            let targets = rain.snapshot["targets"] as? [[String: Any]] ?? []
            if targets.isEmpty {
                Text("No snakes nearby").font(.androidWyrm(13)).foregroundColor(ATheme.quiet)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                let name = (target["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                row { WyrmRainKey(label: name.isEmpty ? "Unnamed snake" : name, lit: false) { rain.target(target) } }
            }
        default:
            Spacer().frame(height: 6)
            WyrmRainSliders(keys: ["panelSize", "panelOpacity", "panelBack"])
            Spacer().frame(height: 10)
            WyrmRainSliders(keys: ["maxBots", "size", "separation", "finalAng", "rOC", "rotationDir", "period", "amplitude", "ranRate"])
            Spacer().frame(height: 10)
            WSCard { WSBoolRow(title: "Cycle through characters", on: rain.evolveEnabled, first: true) { rain.flag("evolveEnabled", $0) } }
        }
    }

    /// The hosting view covers only the panel, centred: the rest still steers.
    private func layout() {
        let scale = min(max(rain.config["panelSize"] ?? 1, 0.7), 1.3)
        WyrmIOSSetRainPanel(rain.enabled && open, true, 380 * scale, 340 * scale)
    }
}

@objc(WyrmRainHost)
@MainActor
final class WyrmRainHost: NSObject {
    @objc static func handleKey(_ key: String) -> Bool { WyrmRain.shared.handleKey(key) }
    @objc static func makeViewController() -> UIViewController {
        let controller = UIHostingController(rootView: WyrmRainPanel()); controller.view.backgroundColor = .clear; return controller
    }
}

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
    var previewColors: [UInt32] {
        guard presetIndex == nil else { return [] }
        return Array(skin.enumerated()).compactMap { index, c in
            WyrmSkinCatalog.group(for: c) == nil ? nil : (index < colors.count ? colors[index] : 0)
        }
    }
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
        let groups = c.previewGroups
        let colors = c.previewColors
        WyrmSkinPreview(textures: textures, groups: (0..<256).map { groups[$0 % groups.count] },
                        colors: (0..<256).map { colors.isEmpty ? 0 : colors[$0 % colors.count] }, preset: c.presetIndex ?? 0,
                        custom: c.presetIndex == nil && !c.beadGroups.isEmpty,
                        accessoryID: c.cosmetic == 255 ? -1 : c.cosmetic, tagID: c.tagAsset?.id ?? -1,
                        backgroundID: 0, chain: 1, swing: 1, tagScale: 1,
                        trialLook: WyrmTrailSkin.Look(hair: -1, hairTone: 0.22, ears: -1, glasses: -1))
    }
}

/// Rain's link in one word, with a dot: Connected (green) or Disconnected (OM, 2026-10-14).
struct WyrmRainStatusLine: View {
    @ObservedObject var rain = WyrmRain.shared
    var ink: Color? = nil
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(rain.connected ? ATheme.live : ATheme.quiet).frame(width: 8, height: 8)
            Text(!rain.connected ? "Disconnected" : rain.running ? "Connected · \(rain.count) bots" : "Connected")
                .font(.androidWyrm(13.5, .semibold)).foregroundColor(ink ?? ATheme.ink).lineLimit(1)
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
            WyrmMiniSnake(textures: textures, groups: c.previewGroups, colors: c.previewColors).frame(width: 92, height: 26)
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
            field("Skin code · \(c.skin.count)/250", c.skin, first: false, mono: true, placeholder: "Type or paste a skin code") { v in update(c) { $0.setSkin(v) } }
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
            WyrmPatternBuilder(textures: textures, groups: groups, colors: c.previewColors, maxBeads: 250) { next, colors in
                update(c) { $0.skin = String(WyrmSkinCatalog.code(for: next).prefix(250)); $0.colors = Array(colors.prefix(250)) }
            }
        case .presets:
            LazyVStack(spacing: 0) {
                ForEach(WyrmSkinCatalog.presets.indices, id: \.self) { index in
                    Button { update(c) { $0.setSkin("/\(index)") } } label: {
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
        WSSectionLabel("Arena panel", top: 14)
        WyrmRainColourRows()
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

/// The panel's Back (OM, 2026-10-14): how much of every fill shows, the
/// plate, the cards and the keys; type and borders stay whole. 1 on the page.
private struct WyrmRainPanelLook {
    let ink: Color
    let fill: Color
}
private struct WyrmRainLookKey: EnvironmentKey { static let defaultValue: WyrmRainPanelLook? = nil }

private func wyrmRainSwatch(_ index: Int, fallback: Color) -> Color {
    index > 0 && index < WyrmTeamHudStore.swatches.count ? (WyrmTeamHudStore.swatches[index] ?? fallback) : fallback
}

private struct WyrmRainBackKey: EnvironmentKey { static let defaultValue: Double = 1 }
extension EnvironmentValues {
    fileprivate var wyrmRainLook: WyrmRainPanelLook? {
        get { self[WyrmRainLookKey.self] }
        set { self[WyrmRainLookKey.self] = newValue }
    }
    var wyrmRainBack: Double {
        get { self[WyrmRainBackKey.self] }
        set { self[WyrmRainBackKey.self] = newValue }
    }
}

/// WSCard whose fill follows the panel's Back; the edge stays.
struct WyrmRainCard<Content: View>: View {
    @Environment(\.wyrmRainBack) private var back
    @Environment(\.wyrmRainLook) private var look
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        if look == nil && back >= 0.999 {
            WSCard { content }
        } else {
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((look?.fill ?? ATheme.card).opacity(back))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke((look?.ink ?? ATheme.ink).opacity(0.35), lineWidth: 1))
                .padding(.horizontal, 16)
        }
    }
}

struct WyrmRainSliders: View {
    @ObservedObject var rain = WyrmRain.shared
    let keys: [String]
    @Environment(\.wyrmRainLook) private var look
    var body: some View {
        WyrmRainCard {
            ForEach(Array(keys.enumerated()), id: \.element) { index, key in
                let range = WyrmRain.ranges.first { $0.0 == key }?.1 ?? 0...1
                let value = rain.config[key] ?? WyrmRain.defaults[key] ?? range.lowerBound
                if let look {
                    VStack(spacing: 4) {
                        HStack {
                            Text(wyrmRainSettingName(key)).font(.androidWyrm(15.5))
                            Spacer()
                            Text(wyrmRainSettingValue(key, value)).font(.androidWyrm(14)).monospacedDigit()
                        }.foregroundColor(look.ink)
                        Slider(value: Binding(get: { value }, set: { rain.set(key, $0) }), in: range).tint(look.ink)
                    }.padding(14)
                } else {
                    WSSliderRow(title: wyrmRainSettingName(key), valueText: wyrmRainSettingValue(key, value),
                                value: value, range: range, first: index == 0) { rain.set(key, $0) }
                }
            }
        }
    }
}

private struct WyrmRainColourRows: View {
    @ObservedObject private var rain = WyrmRain.shared
    @Environment(\.wyrmRainLook) private var look
    var body: some View {
        let ink = look?.ink ?? ATheme.ink
        WyrmRainCard {
            row("panelTextColour", "TEXT AND BORDER", ink)
            row("panelFillColour", "FILL", ink)
        }
    }
    private func row(_ key: String, _ title: String, _ ink: Color) -> some View {
        let selected = min(max(Int(rain.config[key] ?? 0), 0), 8)
        return VStack(alignment: .leading, spacing: 9) {
            Text("\(title) · \(WyrmTeamHudStore.colourNames[selected].uppercased())")
                .font(.androidWyrm(10, .bold)).tracking(0.8).foregroundColor(ink)
            HStack {
                ForEach(0..<9, id: \.self) { index in
                    if index > 0 { Spacer(minLength: 2) }
                    Button { rain.set(key, Double(index)) } label: {
                        Circle().fill(WyrmTeamHudStore.swatches[index] ?? ink).padding(4)
                            .frame(width: 28, height: 28)
                            .overlay(Circle().stroke(ink.opacity(index == selected ? 1 : 0.35), lineWidth: index == selected ? 2 : 1))
                    }.buttonStyle(.plain).accessibilityLabel("\(title) \(WyrmTeamHudStore.colourNames[index])")
                }
            }
        }.padding(.horizontal, 14).padding(.vertical, 10)
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
    @Environment(\.wyrmRainBack) private var back
    @Environment(\.wyrmRainLook) private var look
    var body: some View {
        let ink = look?.ink ?? ATheme.ink
        let fill = look?.fill ?? ATheme.card
        Button(action: action) {
            Text(label).font(.androidWyrm(13.5, .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundColor(ink)
                .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 46)
                .background(fill.opacity(back))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(lit ? ATheme.live : ink.opacity(0.6), lineWidth: lit ? 2.5 : 1.5))
                .padding(3)
        }.buttonStyle(WSPressStyle())
    }
}

/// The arena's Rain panel (OM, 2026-10-14): opened by the Rain key, tabs for
/// the controls, modes, nearby snakes and live settings. Its size, opacity
/// and back plate are the player's ("panelSize", "panelOpacity", "panelBack").
@MainActor
private final class WyrmRainPanelPlacement: ObservableObject {
    static let shared = WyrmRainPanelPlacement()
    @Published var frame = CGRect(x: 0, y: 0, width: 428, height: 388)
}

struct WyrmRainPanel: View {
    @ObservedObject private var rain = WyrmRain.shared
    @ObservedObject private var placement = WyrmRainPanelPlacement.shared
    @State private var open = false
    @State private var seen = WyrmRain.shared.panelRequests
    @State private var tab = 0
    private var scale: CGFloat { CGFloat(min(max(rain.config["panelSize"] ?? 1, 0.7), 1.3)) }

    /// Panel size scales the whole panel, type and keys too, not only its box (OM, 2026-10-14).
    var body: some View {
        GeometryReader { _ in
            let frame = placement.frame
            let fit = min(frame.width / 428, frame.height / 388)
            panel.frame(width: 380, height: 340).padding(24)
                .scaleEffect(fit, anchor: .topLeading)
                .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                .offset(x: frame.minX, y: frame.minY)
        }
    }

    private var ink: Color { wyrmRainSwatch(Int(rain.config["panelTextColour"] ?? 0), fallback: ATheme.ink) }
    private var fill: Color { wyrmRainSwatch(Int(rain.config["panelFillColour"] ?? 0), fallback: ATheme.paper) }

    @ViewBuilder private var panel: some View {
        let opacity = min(max(rain.config["panelOpacity"] ?? 1, 0.3), 1)
        let back = min(max(rain.config["panelBack"] ?? 0.94, 0), 1)
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Snakey Rain").font(.androidWyrm(16, .bold)).foregroundColor(ink)
                    WyrmRainStatusLine(ink: ink)
                }
                Spacer()
                Button { open = false; layout() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundColor(ink)
                        .frame(width: 34, height: 34).background(fill.opacity(rain.config["panelBack"] ?? 0.94)).clipShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel("Close")
            }.padding(.leading, 16).padding(.trailing, 8).padding(.top, 10)
            HStack(spacing: 0) {
                ForEach(Array(["Controls", "Modes", "Target", "Settings"].enumerated()), id: \.offset) { index, title in
                    Button { tab = index } label: {
                        Text(title).font(.androidWyrm(12, tab == index ? .bold : .medium)).foregroundColor(ink)
                            .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity).frame(height: 36)
                            .background(ink.opacity(tab == index ? 0.14 : 0)).clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(3).background(ink.opacity(0.06)).clipShape(Capsule())
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) { content }.padding(.bottom, 10)
            }
            // The knob at the bottom centre drags the panel anywhere (OM, 2026-10-14).
            Capsule().fill(ink.opacity(0.5)).frame(width: 42, height: 5)
                .frame(maxWidth: .infinity).frame(height: 26).contentShape(Rectangle())
                .overlay(WyrmRainDragHandle())
                .accessibilityLabel("Move Rain panel")
        }
        .background(fill.opacity(back))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(ink.opacity(0.35), lineWidth: 1))
        .environment(\.wyrmRainBack, back)
        .environment(\.wyrmRainLook, WyrmRainPanelLook(ink: ink, fill: fill))
        .shadow(color: ATheme.ink.opacity(0.12 * back), radius: 18 * back)
        .opacity(opacity)
        .onChange(of: rain.panelRequests) { now in if now != seen { seen = now; open.toggle(); layout() } }
        .onChange(of: rain.enabled) { on in if !on { open = false }; layout() }
        .onChange(of: rain.config["panelSize"] ?? 1) { _ in layout() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WyrmEngineScreenChanged"))) { _ in open = false; layout() }
        .onAppear { layout() }
    }

    private func stepButton(_ symbol: String, _ label: String, _ enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .bold)).foregroundColor(ink)
                .frame(width: 36, height: 36).background(fill.opacity(rain.config["panelBack"] ?? 0.94)).clipShape(Circle())
                .overlay(Circle().stroke(ink.opacity(enabled ? 0.8 : 0.3), lineWidth: 1))
        }.buttonStyle(WSPressStyle()).disabled(!enabled).accessibilityLabel(label)
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
            Text("Mode · \(WyrmRain.modes[min(max(rain.mode, 1), 14) - 1])").font(.androidWyrm(12.5)).foregroundColor(ink)
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
            // My own bots crowd me; they carry my characters' in-game names (OM, 2026-10-14).
            let mine = Set(rain.characters.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
            let targets = (rain.snapshot["targets"] as? [[String: Any]] ?? []).filter {
                !mine.contains(($0["name"] as? String ?? "").trimmingCharacters(in: .whitespaces).lowercased())
            }
            if targets.isEmpty {
                Text("No snakes nearby").font(.androidWyrm(13)).foregroundColor(ink)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            }
            Color.clear.frame(height: 0)
                .onAppear { rain.liveTargets = true }
                .onDisappear { rain.liveTargets = false }
            ForEach(Array(targets.enumerated()), id: \.offset) { _, target in
                let name = (target["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                row { WyrmRainKey(label: name.isEmpty ? "Unnamed snake" : name, lit: false) { rain.target(target) } }
            }
        default:
            Spacer().frame(height: 6)
            // Minus / plus, not a slider: a slider resized the view under the finger (OM, 2026-10-14).
            WyrmRainCard {
                HStack(spacing: 10) {
                    Text("Panel size").font(.androidWyrm(15.5)).foregroundColor(ink).frame(maxWidth: .infinity, alignment: .leading)
                    let size = rain.config["panelSize"] ?? 1
                    stepButton("minus", "Smaller", size > 0.71) { rain.set("panelSize", size - 0.1) }
                    Text("\(Int((size * 100).rounded()))%").font(.androidWyrm(14)).monospacedDigit().foregroundColor(ink).frame(width: 56)
                    stepButton("plus", "Bigger", size < 1.29) { rain.set("panelSize", size + 0.1) }
                }.padding(.horizontal, 14).padding(.vertical, 10)
            }
            Spacer().frame(height: 10)
            WyrmRainColourRows()
            Spacer().frame(height: 10)
            WyrmRainSliders(keys: ["panelOpacity", "panelBack"])
            Spacer().frame(height: 10)
            WyrmRainSliders(keys: ["maxBots", "size", "separation", "finalAng", "rOC", "rotationDir", "period", "amplitude", "ranRate"])
            Spacer().frame(height: 10)
            WyrmRainCard {
                Toggle(isOn: Binding(get: { rain.evolveEnabled }, set: { rain.flag("evolveEnabled", $0) })) {
                    Text("Cycle through characters").font(.androidWyrm(15.5)).foregroundColor(ink)
                }.tint(ink).padding(14)
            }
        }
    }

    /// The hosting view covers only the panel, centred: the rest still steers.
    private func layout() {
        let scale = min(max(rain.config["panelSize"] ?? 1, 0.7), 1.3)
        WyrmIOSSetRainPanel(rain.enabled && open, true, 428 * scale, 388 * scale)
    }
}

/// Window coordinates stay stable while the small hosting view moves or rotates.
private struct WyrmRainDragHandle: UIViewRepresentable {
    final class Coordinator: NSObject {
        private var last = CGPoint.zero
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            let point = gesture.location(in: nil)
            if gesture.state == .began { last = point }
            if gesture.state == .changed {
                WyrmIOSMoveRainPanel(Double(point.x - last.x), Double(point.y - last.y))
                last = point
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.addGestureRecognizer(UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:))))
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

@objc(WyrmRainHost)
@MainActor
final class WyrmRainHost: NSObject {
    @objc static func handleKey(_ key: String) -> Bool { WyrmRain.shared.handleKey(key) }
    @objc(placePanelLeft:top:width:height:)
    static func placePanel(left: Double, top: Double, width: Double, height: Double) {
        let frame = CGRect(x: left, y: top, width: width, height: height)
        if WyrmRainPanelPlacement.shared.frame != frame { WyrmRainPanelPlacement.shared.frame = frame }
    }
    @objc static func makeViewController() -> UIViewController {
        let controller = UIHostingController(rootView: WyrmRainPanel()); controller.view.backgroundColor = .clear; return controller
    }
}

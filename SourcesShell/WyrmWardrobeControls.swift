import SwiftUI

struct WyrmWardrobeAction: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let glyph: WyrmWardrobeGlyph
    let label: String
    var selected = false
    var enabled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            WyrmWardrobeIcon(glyph: glyph, tint: selected ? wyrmScopedColours.onInk : wyrmScopedColours.ink)
                .frame(width: 23, height: 23).frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 17).fill(selected ? wyrmScopedColours.ink : wyrmScopedColours.card))
                .overlay(RoundedRectangle(cornerRadius: 17).stroke(wyrmScopedColours.rule, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(WSPressStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.3)
            .accessibilityLabel(label).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct WyrmWardrobeHeader: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    let title: String
    var settings: (() -> Void)? = nil
    var settingsOpen = false
    var adjust: (() -> Void)? = nil
    let done: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.androidWyrm(18, .bold)).foregroundColor(wyrmScopedColours.ink)
            Spacer(minLength: 8)
            if let settings {
                Button(action: settings) {
                    ZStack {
                        WyrmWardrobeIcon(glyph: .settings).opacity(settingsOpen ? 0 : 1)
                        WyrmWardrobeIcon(glyph: .close).opacity(settingsOpen ? 1 : 0)
                    }.frame(width: 23, height: 23).rotationEffect(.degrees(settingsOpen ? 180 : 0))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(settingsOpen ? "Close tag settings" : "Tag settings")
            }
            if let adjust { WyrmWardrobeAction(glyph: .resize, label: "Adjust size", action: adjust) }
            WyrmWardrobeAction(glyph: .ok, label: "OK", action: done)
        }.padding(.horizontal, 16).padding(.vertical, 10).background(wyrmScopedColours.paper)
    }
}

/// Just the beads and the four pinned controls. Undo/redo restores exact per-bead colours too.
struct WyrmWardrobeBuilder: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var textures: WyrmSkinTextureLibrary
    let groups: [Int]
    let colors: [UInt32]
    let done: () -> Void
    let save: ([Int], [UInt32]) -> Void
    @State private var wheel: Bool
    @State private var history: WyrmWardrobeHistory
    @State private var revision = 0
    @State private var codeFocused = false
    @ObservedObject private var keyboard = WyrmKeyboardController.shared
    @AppStorage("wyrm.ios.skin.air-pointer-x") private var x = 0.0
    @AppStorage("wyrm.ios.skin.air-pointer-y") private var y = 0.0
    @AppStorage("wyrm.ios.skin.air-bezel") private var bezel = 0.0
    @AppStorage("wyrm.ios.skin.air-rgb") private var rgb = 0x808080
    init(textures: WyrmSkinTextureLibrary, groups: [Int], colors: [UInt32], showingWheel: Bool = false,
         done: @escaping () -> Void, save: @escaping ([Int], [UInt32]) -> Void) {
        self.textures = textures; self.groups = groups; self.colors = colors; self.done = done; self.save = save
        _wheel = State(initialValue: showingWheel)
        _history = State(initialValue: WyrmWardrobeHistory(.init(groups: groups, colors: colors)))
    }
    private func commit(_ groups: [Int], _ colors: [UInt32]) {
        let next = WyrmWardrobePattern(groups: groups, colors: colors)
        history.push(next); revision += 1; save(groups, colors)
    }
    private func add(_ group: Int, _ color: UInt32) {
        guard groups.count < 256 else { return }
        commit(groups + [group], groups.indices.map { $0 < colors.count ? colors[$0] : 0 } + [color])
    }
    var body: some View {
        let _ = revision
        HStack(alignment: .top, spacing: 8) {
            ScrollViewReader { scroll in
              ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                  // A normal field (OM, 2026-11-07): cursor drags, hold selects, Copy works.
                  WyrmSkinCodeField(groups: groups, placeholder: "Paste a skin code", focused: $codeFocused) { typed in
                        let next = typed.lowercased().prefix(256).compactMap { WyrmSkinCatalog.group(for: $0) }
                        let common = zip(next, groups).prefix { $0.0 == $0.1 }.count
                        commit(next, next.indices.map { $0 < common && $0 < colors.count ? colors[$0] : 0 })
                    }
                    .padding(.horizontal, 12).padding(.top, 10).id("wardrobe-code")
                ZStack(alignment: .top) {
                    if wheel {
                        WyrmAirWheelPanel(wheel: textures.airWheel, beads: textures.airBeads,
                            storedX: $x, storedY: $y, storedAngle: $bezel, storedRGB: $rgb,
                            allowedStyles: WyrmAirSkin.allowed(colors).styles) { kind, rgb in
                            add(WyrmAirSkin.nearestGroup(rgb), WyrmAirSkin.marker(kind: kind) | rgb)
                        }.transition(paletteTransition(true))
                    } else { beadGrid.transition(paletteTransition(false)) }
                }.padding(.top, 16).padding(.bottom, 12)
                }
              }
              .onChange(of: codeFocused) { focused in if focused { revealCode(scroll) } }
              .onChange(of: keyboard.occlusion) { _ in if codeFocused { revealCode(scroll) } }
            }
            VStack(spacing: 10) {
                WyrmWardrobeAction(glyph: .colours, label: wheel ? "Show beads" : "More colours", selected: wheel,
                                  enabled: !WyrmBead.builtBeadsOff) {
                    withAnimation(.linear(duration: 0.4)) { wheel.toggle() }
                }
                WyrmWardrobeAction(glyph: .undo, label: "Undo", enabled: history.canUndo) {
                    let value = history.undo(); revision += 1; save(value.groups, value.colors)
                }
                WyrmWardrobeAction(glyph: .redo, label: "Redo", enabled: history.canRedo) {
                    let value = history.redo(); revision += 1; save(value.groups, value.colors)
                }
                WyrmWardrobeAction(glyph: .ok, label: "OK", action: done)
            }.padding(.top, 12).padding(.trailing, 12)
        }
        .onChange(of: WyrmWardrobePattern(groups: groups, colors: colors)) { next in
            if next != history.current { history.push(next); revision += 1 }
        }
    }
    private func revealCode(_ scroll: ScrollViewProxy) {
        DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.25)) { scroll.scrollTo("wardrobe-code", anchor: .center) } }
    }
    private func paletteTransition(_ wheel: Bool) -> AnyTransition {
        .modifier(active: WyrmWardrobePalette(progress: 0, wheel: wheel), identity: WyrmWardrobePalette(progress: 1, wheel: wheel))
    }
    private var beadGrid: some View {
        let allowed = WyrmAirSkin.allowed(colors).grid
        let plain = WyrmSkinCatalog.validGroups
        let count = plain.count + WyrmBead.count
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                let isWyrm = index >= plain.count
                let kind = isWyrm ? index - plain.count : plain[index]
                let enabled = allowed && (!isWyrm || !WyrmBead.builtBeadsOff)
                Button {
                    if isWyrm {
                        let rgba = WyrmBead.rgba(kind, tint: UInt32(truncatingIfNeeded: rgb) & 0xFF_FFFF)
                        add(WyrmAirSkin.nearestGroup(rgba & 0xFF_FFFF), rgba)
                    } else { add(kind, 0) }
                } label: {
                    WyrmAtlasImage(image: isWyrm ? textures.wyrmBeads[kind] : textures.beads[kind])
                        .colorMultiply(isWyrm && WyrmBead.tinted[kind] ? WyrmLook.color(UInt32(truncatingIfNeeded: rgb)) : .white)
                        .padding(5).aspectRatio(1, contentMode: .fit).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.28)
                    .accessibilityLabel(isWyrm ? "\(WyrmBead.names[kind]) bead" : "Bead group \(kind)")
            }
        }
    }
}

struct WyrmWardrobeAccessories: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var textures: WyrmSkinTextureLibrary
    @Environment(\.wardrobeCosmeticsProgress) private var progress
    let selected: Int
    let pick: (Int) -> Void
    var body: some View {
        GeometryReader { proxy in
            let columns = proxy.size.width > 600 ? 8 : 5
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: columns), spacing: 8) {
                    ForEach([-1] + WyrmSkinCatalog.accessories.map(\.id), id: \.self) { id in
                        Button { pick(id) } label: {
                            ZStack {
                                if id < 0 { WyrmWardrobeIcon(glyph: .close).frame(width: 30, height: 30) }
                                else if let image = textures.accessoryThumbnails[id] {
                                    // The old AIR shelf's 0.3 scale, doubled, with the original rotation.
                                    let side = proxy.size.width / CGFloat(columns) * 112 * 0.6 / 84
                                    WyrmAtlasImage(image: image).frame(width: side, height: side).rotationEffect(.degrees(90))
                                }
                            }.frame(maxWidth: .infinity).frame(height: max(64, proxy.size.width / CGFloat(columns)))
                                .contentShape(RoundedRectangle(cornerRadius: 15))
                                .overlay(RoundedRectangle(cornerRadius: 15).stroke(selected == id ? wyrmScopedColours.ink : .clear, lineWidth: 1.5))
                                .scaleEffect(WyrmWardrobeGeometry.ease(progress)).opacity(progress)
                        }.buttonStyle(WSPressStyle()).accessibilityLabel(id < 0 ? "No accessory" : "Accessory \(id + 1)")
                            .accessibilityAddTraits(selected == id ? .isSelected : [])
                    }
                }.padding(.vertical, 10)
            }
        }
    }
}

private struct WardrobeCosmeticsProgress: EnvironmentKey { static let defaultValue = 1.0 }
extension EnvironmentValues {
    var wardrobeCosmeticsProgress: Double {
        get { self[WardrobeCosmeticsProgress.self] }
        set { self[WardrobeCosmeticsProgress.self] = newValue }
    }
}
private struct WardrobeCosmeticsReveal: AnimatableModifier {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View { content.environment(\.wardrobeCosmeticsProgress, progress) }
}
extension AnyTransition {
    static var wyrmWardrobeAccessories: AnyTransition {
        .modifier(active: WardrobeCosmeticsReveal(progress: 0), identity: WardrobeCosmeticsReveal(progress: 1))
    }
}

/// AIR's fourth-root wheel zoom, shared with the Android palette transition.
private struct WyrmWardrobePalette: AnimatableModifier {
    var progress: Double
    let wheel: Bool
    var animatableData: Double { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        content.scaleEffect(wheel ? 0.1 + 0.9 * pow(max(progress, 0), 0.25) : 0.01 + 0.99 * progress)
            .opacity(progress)
    }
}

/// The wardrobe has its own short dock; the full settings selector stays in settings.
struct WyrmWardrobeTextureDock: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject private var texture = WyrmSkinTexture.shared
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var appeared = false
    let onPick: (Int) -> Void
    let onMine: (Bool) -> Void
    var body: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Array(WyrmSkinTexture.offered.enumerated()), id: \.element) { position, index in
                    tile(index).offset(y: appeared ? 0 : 24).scaleEffect(appeared ? 1 : 0.82).opacity(appeared ? 1 : 0)
                        .animation(reduced ? nil : .interpolatingSpring(stiffness: 420, damping: 24).delay(Double(position) * 0.024), value: appeared)
                }
            }
            Button {
                texture.mine.toggle(); onMine(texture.mine)
            } label: {
                HStack(spacing: 8) {
                    Text("Mine").foregroundColor(texture.mine ? wyrmScopedColours.ink : wyrmScopedColours.mute)
                    Capsule().fill(wyrmScopedColours.ink).frame(width: 36, height: 22)
                        .overlay(Circle().fill(wyrmScopedColours.onInk).frame(width: 16, height: 16).offset(x: texture.mine ? -7 : 7))
                    Text("Everyone").foregroundColor(texture.mine ? wyrmScopedColours.mute : wyrmScopedColours.ink)
                }.font(.androidWyrm(12)).frame(height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Texture scope")
                .accessibilityValue(texture.mine ? "Mine" : "Everyone")
                .animation(reduced ? nil : .easeInOut(duration: 0.2), value: texture.mine)
        }.padding(.horizontal, 12).padding(.vertical, 8).onAppear { appeared = true }
    }
    private func tile(_ index: Int) -> some View {
        let selected = texture.current == index || (index == 0 && !WyrmSkinTexture.offered.contains(texture.current))
        return Button { texture.current = index; onPick(index) } label: {
            VStack(spacing: 6) {
                Canvas { context, size in
                    let hues: [UInt32] = [0xC080FF,0x9099FF,0x80D0D0,0x80FF80,0xEEEE70,0xFFA060]
                    let d = size.height * 0.8, step = (size.width - size.height * 0.8) / 5
                    for (i, hue) in hues.enumerated() {
                        let rect = CGRect(x: CGFloat(i) * step, y: (size.height - d) / 2, width: d, height: d)
                        if let image = texture.bead(hue, texture: index) { context.draw(Image(decorative: image, scale: 1), in: rect) }
                        else { context.fill(Path(ellipseIn: rect), with: .color(WyrmLook.color(hue))) }
                    }
                }.frame(height: 34)
                Text(WyrmSkinTexture.names[index]).font(.androidWyrm(12, selected ? .bold : .semibold))
                    .foregroundColor(selected ? wyrmScopedColours.ink : wyrmScopedColours.mute).lineLimit(1).minimumScaleFactor(0.7)
            }.padding(8).background(RoundedRectangle(cornerRadius: 14).fill(wyrmScopedColours.card))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? wyrmScopedColours.ink : wyrmScopedColours.rule, lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain).accessibilityLabel("\(WyrmSkinTexture.names[index]) texture")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

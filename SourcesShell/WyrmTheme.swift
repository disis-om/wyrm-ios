import SwiftUI
import UIKit

/// One Wyrm appearance, role for role the palette Android's `WyrmPalette`
/// carries. Colours are held as linear components so the intensity maths below
/// can be written exactly as the Android original is.
struct WyrmPalette: Equatable {
    var paper: WyrmRGBA, card: WyrmRGBA, ink: WyrmRGBA, onInk: WyrmRGBA
    var quiet: WyrmRGBA, mute: WyrmRGBA, rule: WyrmRGBA, rowRule: WyrmRGBA
    var live: WyrmRGBA, link: WyrmRGBA, tabIdle: WyrmRGBA, tabBar: WyrmRGBA
    var chevron: WyrmRGBA, badge: WyrmRGBA, well: WyrmRGBA, track: WyrmRGBA
    var hover: WyrmRGBA
    var hero: WyrmHero
    var hero2: WyrmHero
    var dark: Bool

    init(_ c: [UInt32], hero heroC: [UInt32], hero2 hero2C: [UInt32], dark: Bool) {
        let v = c.map(WyrmRGBA.init(argb:))
        paper = v[0]; card = v[1]; ink = v[2]; onInk = v[3]
        quiet = v[4]; mute = v[5]; rule = v[6]; rowRule = v[7]
        live = v[8]; link = v[9]; tabIdle = v[10]; tabBar = v[11]
        chevron = v[12]; badge = v[13]; well = v[14]; track = v[15]
        hover = v[16]
        hero = WyrmHero(heroC)
        hero2 = WyrmHero(hero2C)
        self.dark = dark
    }
}

struct WyrmRGBA: Equatable {
    var r: Double, g: Double, b: Double, a: Double

    init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(argb: UInt32) {
        a = Double((argb >> 24) & 0xff) / 255
        r = Double((argb >> 16) & 0xff) / 255
        g = Double((argb >> 8) & 0xff) / 255
        b = Double(argb & 0xff) / 255
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var argb: UInt32 {
        func byte(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return byte(a) << 24 | byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    /// Compose's `Color.luminance()`: WCAG relative luminance of linear sRGB.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    func mix(towards target: WyrmRGBA, _ amount: Double) -> WyrmRGBA {
        let t = min(1, max(0, amount))
        return WyrmRGBA(r: r + (target.r - r) * t, g: g + (target.g - g) * t,
                        b: b + (target.b - b) * t, a: a + (target.a - a) * t)
    }

    /// Android `mixKeepAlpha`: RGB moves, this colour's alpha stays.
    func mixKeepAlpha(towards target: WyrmRGBA, _ amount: Double) -> WyrmRGBA {
        let t = min(1, max(0, amount))
        return WyrmRGBA(r: r + (target.r - r) * t, g: g + (target.g - g) * t,
                        b: b + (target.b - b) * t, a: a)
    }

    func withIntensity(_ intensity: Double) -> WyrmRGBA {
        let safe = min(1, max(0, intensity))
        if abs(safe - 0.5) < 0.0001 { return self }
        let multiplier = safe * 2
        let l = r * 0.2126 + g * 0.7152 + b * 0.0722
        func c(_ v: Double) -> Double { min(1, max(0, l + (v - l) * multiplier)) }
        return WyrmRGBA(r: c(r), g: c(g), b: c(b), a: a)
    }

    static let white = WyrmRGBA(r: 1, g: 1, b: 1, a: 1)
    static let nearBlack = WyrmRGBA(argb: 0xFF111111)
}

private func contrastRatio(_ background: WyrmRGBA, _ foreground: WyrmRGBA) -> Double {
    let lighter = max(background.luminance, foreground.luminance)
    let darker = min(background.luminance, foreground.luminance)
    return (lighter + 0.05) / (darker + 0.05)
}

private extension WyrmRGBA {
    func ensureAgainst(_ backgrounds: [WyrmRGBA], _ minimum: Double) -> WyrmRGBA {
        func worst(_ c: WyrmRGBA) -> Double { backgrounds.map { contrastRatio($0, c) }.min() ?? 0 }
        if worst(self) >= minimum { return self }
        let black = WyrmRGBA(argb: 0xFF000000)
        let target = worst(black) >= worst(.white) ? black : WyrmRGBA.white
        var best = self
        var bestW = worst(self)
        var t = 0.04
        while t <= 1.001 {
            let mixed = mixKeepAlpha(towards: target, t)
            let w = worst(mixed)
            if w >= minimum { return mixed }
            if w > bestW { best = mixed; bestW = w }
            t += 0.04
        }
        return best
    }

    func separateToward(paper: WyrmRGBA, ink: WyrmRGBA) -> WyrmRGBA {
        if contrastRatio(self, ink) >= 4.5 { return self }
        var best = self
        var bestR = contrastRatio(self, ink)
        var t = 0.04
        while t <= 1.001 {
            let mixed = mixKeepAlpha(towards: paper, t)
            let r = contrastRatio(mixed, ink)
            if r >= 4.5 { return mixed }
            if r > bestR { best = mixed; bestR = r }
            t += 0.04
        }
        return best
    }
}

extension WyrmHero {
    /// Keep the prototype's 6.5 floor when attainable; otherwise use the best ink.
    func retinted(bg: WyrmRGBA, hi: WyrmRGBA, lo: WyrmRGBA, seedOn: WyrmRGBA) -> WyrmHero {
        let on = seedOn.ensureAgainst([bg], 6.5)
        var out = self
        out.bg = bg
        out.on = on
        let well = bg.mixKeepAlpha(towards: on, 0.14).separateToward(paper: bg, ink: on)
        out.quiet = on.mixKeepAlpha(towards: bg, 0.28).ensureAgainst([bg,well], 4.5)
        out.mute = on.mixKeepAlpha(towards: bg, 0.14).ensureAgainst([bg,well], 4.5)
        out.rule = WyrmRGBA(r: on.r, g: on.g, b: on.b, a: 0.22)
        out.well = well
        out.well.a = 1
        out.hi = hi
        out.lo = lo
        return out
    }
}

extension WyrmPalette {
    /// Android `withIntensity`. 50% returns this palette. Below 50% washes
    /// surfaces toward this theme's own paper. Above raises chroma. Text is
    /// re-ensured. The deleted Paper theme is not a target.
    func withIntensity(_ intensity: Double) -> WyrmPalette {
        let safe = min(1, max(0, intensity))
        // Secure reading roles at the neutral intensity too. Raw table
        // colours still match the prototype, including decorative seeds.
        let shifted: WyrmPalette
        if safe < 0.5 {
            let t = 1 - safe * 2
            var out = self
            out.card = card.mixKeepAlpha(towards: paper, t)
            out.well = well.mixKeepAlpha(towards: paper, t)
            out.track = track.mixKeepAlpha(towards: paper, t)
            out.hover = hover.mixKeepAlpha(towards: paper, t)
            out.live = live.mixKeepAlpha(towards: paper, t)
            out.badge = badge.mixKeepAlpha(towards: paper, t)
            out.tabBar = tabBar.mixKeepAlpha(towards: paper, t)
            out.rule.a = rule.a * (1 - t)
            out.rowRule.a = rowRule.a * (1 - t)
            out.hero = hero.retinted(bg: hero.bg.mixKeepAlpha(towards: paper, t),
                                     hi: hero.hi.mixKeepAlpha(towards: paper, t),
                                     lo: hero.lo.mixKeepAlpha(towards: paper, t),
                                     seedOn: hero.on)
            out.hero2 = hero2.retinted(bg: hero2.bg.mixKeepAlpha(towards: paper, t),
                                       hi: hero2.hi.mixKeepAlpha(towards: paper, t),
                                       lo: hero2.lo.mixKeepAlpha(towards: paper, t),
                                       seedOn: hero2.on)
            shifted = out
        } else {
            var out = self
            for path in [\WyrmPalette.paper, \.card, \.ink, \.onInk, \.quiet, \.mute, \.rule, \.rowRule,
                         \.live, \.link, \.tabIdle, \.tabBar, \.chevron, \.badge, \.well, \.track, \.hover] {
                out[keyPath: path] = self[keyPath: path].withIntensity(safe)
            }
            out.hero = hero.retinted(bg: hero.bg.withIntensity(safe), hi: hero.hi.withIntensity(safe),
                                     lo: hero.lo.withIntensity(safe), seedOn: hero.on.withIntensity(safe))
            out.hero2 = hero2.retinted(bg: hero2.bg.withIntensity(safe), hi: hero2.hi.withIntensity(safe),
                                       lo: hero2.lo.withIntensity(safe), seedOn: hero2.on.withIntensity(safe))
            shifted = out
        }
        return shifted.resecured()
    }

    /// Card-local palette. Slot 2 is hero2. Tab roles stay.
    func heroView(slot: Int) -> WyrmPalette {
        let h = slot == 2 ? hero2 : hero
        var out = self
        out.paper = h.bg
        out.card = h.bg
        out.ink = h.on
        out.onInk = h.bg
        out.quiet = h.quiet
        out.mute = h.mute
        out.rule = h.rule
        out.rowRule = h.rule
        out.live = h.on
        out.link = h.on
        out.chevron = h.quiet
        out.well = h.well
        out.track = h.rule
        out.dark = h.bg.luminance < 0.45
        return out
    }

    private func resecured() -> WyrmPalette {
        let ink2 = ink.ensureAgainst([paper], 7.5)
        let card2 = card.separateToward(paper: paper, ink: ink2)
        let well2 = well.separateToward(paper: paper, ink: ink2)
        let body = [paper, card2]
        var out = self
        out.ink = ink2
        out.card = card2
        out.well = well2
        out.onInk = onInk.ensureAgainst([ink2], 4.5)
        out.quiet = quiet.ensureAgainst(body + [well2], 4.5)
        out.mute = mute.ensureAgainst(body + [well2], 4.5)
        out.live = live.ensureAgainst(body + [well2], 4.5)
        out.badge = badge.ensureAgainst(body + [well2], 4.5)
        out.link = link.ensureAgainst(body + [well2], 4.5)
        out.tabIdle = tabIdle.ensureAgainst([tabBar, paper], 4.5)
        out.chevron = chevron.ensureAgainst(body + [well2], 4.5)
        out.dark = paper.luminance < 0.45
        return out
    }
}

/// The chosen appearance. Stored locally like every other setting, and pushed
/// into the original engine so the lobby, death card and arena chrome follow
/// the same palette the SwiftUI screens use.
final class WyrmThemeStore: ObservableObject {
    static let shared = WyrmThemeStore()
    private static let themeKey = "wyrm.ios.theme"
    private static let intensityKey = "wyrm.ios.theme-intensity"
    private static let modeKey = "wyrm.ios.theme-mode"

    @Published private(set) var theme: WyrmThemeID
    @Published private(set) var mode: WyrmThemeMode
    /// Phone light/dark. Read only while [mode] is auto.
    @Published private(set) var systemDark = false
    @Published private(set) var intensity: Double
    @Published private(set) var palette: WyrmPalette { didSet { pushCoverPaper() } }
    /// The intensity the rest of the shell has been rebuilt with. It trails the
    /// slider by a moment so dragging never tears down the slider under the finger.
    @Published private(set) var committedIntensity: Double
    private var commitWork: DispatchWorkItem?

    private init() {
        let defaults = UserDefaults.standard
        // Missing local appearance is Paper; a saved account choice always wins.
        defaults.set(true, forKey: "wyrm.ios.theme-refresh-v1")
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--smoke-theme"), arguments.indices.contains(index+1),
           let selected = WyrmThemeID(rawValue: arguments[index+1]) {
            defaults.set(selected.rawValue, forKey: Self.themeKey)
            if let i = arguments.firstIndex(of: "--smoke-theme-mode"), arguments.indices.contains(i+1),
               let mode = WyrmThemeMode(rawValue: arguments[i+1]) { defaults.set(mode.rawValue, forKey: Self.modeKey) }
            if let i = arguments.firstIndex(of: "--smoke-theme-intensity"), arguments.indices.contains(i+1),
               let value = Double(arguments[i+1]), value.isFinite { defaults.set(min(1,max(0,value)), forKey: Self.intensityKey) }
        }
        let choice = WyrmThemeID.resolve(name: defaults.string(forKey: Self.themeKey),
                                         modeRaw: defaults.string(forKey: Self.modeKey))
        let intensity = defaults.object(forKey: Self.intensityKey) as? Double ?? 0.5
        theme = choice.0
        mode = choice.1
        self.intensity = intensity
        committedIntensity = intensity
        palette = choice.0.side(mode: choice.1, systemDark: false).withIntensity(intensity)
        defaults.set(choice.0.rawValue, forKey: Self.themeKey)
        defaults.set(choice.1.rawValue, forKey: Self.modeKey)
        pushCoverPaper()
    }

    /// Nil while Auto, so the phone's own light/dark can show. About still forces dark.
    var preferredScheme: ColorScheme? {
        switch mode {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }

    /// The rotation cover shows this paper, never black (OM, 2026-10-30).
    private func pushCoverPaper() {
        WyrmIOSSetCoverPaper(palette.paper.r, palette.paper.g, palette.paper.b)
    }

    /// After a log in or log out rewrote the defaults (WyrmAccountSync).
    func reloadFromDefaults() {
        commitWork?.cancel()
        commitWork = nil
        let defaults = UserDefaults.standard
        let choice = WyrmThemeID.resolve(name: defaults.string(forKey: Self.themeKey),
                                         modeRaw: defaults.string(forKey: Self.modeKey))
        let level = defaults.object(forKey: Self.intensityKey) as? Double ?? 0.5
        theme = choice.0
        mode = choice.1
        intensity = level
        committedIntensity = level
        palette = choice.0.side(mode: choice.1, systemDark: systemDark).withIntensity(level)
        defaults.set(choice.0.rawValue, forKey: Self.themeKey)
        defaults.set(choice.1.rawValue, forKey: Self.modeKey)
    }

    /// Changing appearance rebuilds the whole shell (see `WyrmDesignMain`),
    /// so the key doubles as the identity that forces that rebuild.
    var identity: String { "\(theme.rawValue)-\(mode.rawValue)-\(systemDark)-\(Int((committedIntensity * 1000).rounded()))" }

    func select(_ next: WyrmThemeID) {
        guard next != theme else { return }
        theme = next
        let defaults = UserDefaults.standard
        defaults.set(next.rawValue, forKey: Self.themeKey)
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        recompute()
    }

    func setMode(_ next: WyrmThemeMode) {
        guard next != mode else { return }
        mode = next
        UserDefaults.standard.set(next.rawValue, forKey: Self.modeKey)
        recompute()
    }

    /// Republishes only while the saved mode is Auto. Ignore this while About forces a dark scheme.
    func noteSystemDark(_ dark: Bool) {
        guard systemDark != dark else { return }
        systemDark = dark
        if mode == .auto { recompute() }
    }

    func setIntensity(_ value: Double) {
        let next = min(1, max(0, value))
        guard abs(next - intensity) >= 0.0001 else { return }
        intensity = next
        UserDefaults.standard.set(next, forKey: Self.intensityKey)
        recompute()
        commitWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.committedIntensity = next }
        commitWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func recompute() {
        palette = theme.side(mode: mode, systemDark: systemDark).withIntensity(intensity)
        publishArenaTheme()
        applyControlAppearance()
    }

    /// System segmented controls take their type from UIAppearance, which is
    /// read when a control is created; a theme change rebuilds the shell, so
    /// every picker after it picks up the new palette.
    func applyControlAppearance() {
        func manrope(_ weight: UIFont.Weight, _ size: CGFloat) -> UIFont {
            let descriptor = UIFontDescriptor(fontAttributes: [
                .family: "Manrope",
                .traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue],
            ])
            return UIFont(descriptor: descriptor, size: size)
        }
        let control = UISegmentedControl.appearance()
        control.setTitleTextAttributes([.font: manrope(.medium, 13), .foregroundColor: UIColor(palette.mute.color)], for: .normal)
        control.setTitleTextAttributes([.font: manrope(.bold, 13), .foregroundColor: UIColor(selectedPillInk.color)], for: .selected)
    }

    /// Ink on a selected pill. In Graphite and Midnight the system thumb is a
    /// light lens, so the theme's light ink vanished on it: there the label is
    /// the theme's dark paper mixed towards black instead.
    var selectedPillInk: WyrmRGBA {
        palette.dark ? palette.paper.mix(towards: .nearBlack, 0.55) : palette.ink
    }

    /// The engine's twelve arena roles, in `arena_theme_role` order.
    func publishArenaTheme() {
        let p = palette
        let roles: [UInt32] = [p.paper, p.card, p.ink, p.onInk, p.quiet, p.mute, p.rule,
                               p.live, p.link, p.well, p.track, p.badge,
                               p.hero.bg, p.hero.on, p.hero2.bg, p.hero2.on].map(\.argb)
        roles.withUnsafeBufferPointer { WyrmIOSSetArenaTheme($0.baseAddress, Int32($0.count), p.dark) }
    }
}

/// Semantic colours for every SwiftUI screen. They read the live palette, so a
/// theme change reaches every view the next time it is drawn.
enum ATheme {
    private static var p: WyrmPalette { WyrmThemeStore.shared.palette }
    static var paper: Color { p.paper.color }
    static var card: Color { p.card.color }
    static var ink: Color { p.ink.color }
    static var onInk: Color { p.onInk.color }
    static var quiet: Color { p.quiet.color }
    static var mute: Color { p.mute.color }
    static var rule: Color { p.rule.color }
    static var rowRule: Color { p.rowRule.color }
    static var live: Color { p.live.color }
    static var link: Color { p.link.color }
    static var tabIdle: Color { p.tabIdle.color }
    static var tabBar: Color { p.tabBar.color }
    static var chevron: Color { p.chevron.color }
    static var badge: Color { p.badge.color }
    static var well: Color { p.well.color }
    static var track: Color { p.track.color }
    static var hover: Color { p.hover.color }
    static var dark: Bool { p.dark }
}

private struct WyrmPaletteOverrideKey: EnvironmentKey {
    static let defaultValue: WyrmPalette? = nil
}
extension EnvironmentValues {
    var wyrmPaletteOverride: WyrmPalette? {
        get { self[WyrmPaletteOverrideKey.self] }
        set { self[WyrmPaletteOverrideKey.self] = newValue }
    }
}

/// Semantic roles inherited by children of a hero card.
struct WyrmThemeColours {
    let palette: WyrmPalette
    var paper: Color { palette.paper.color }
    var card: Color { palette.card.color }
    var ink: Color { palette.ink.color }
    var onInk: Color { palette.onInk.color }
    var quiet: Color { palette.quiet.color }
    var mute: Color { palette.mute.color }
    var rule: Color { palette.rule.color }
    var rowRule: Color { palette.rowRule.color }
    var live: Color { palette.live.color }
    var link: Color { palette.link.color }
    var tabIdle: Color { palette.tabIdle.color }
    var tabBar: Color { palette.tabBar.color }
    var chevron: Color { palette.chevron.color }
    var badge: Color { palette.badge.color }
    var well: Color { palette.well.color }
    var track: Color { palette.track.color }
    var hover: Color { palette.hover.color }
    var dark: Bool { palette.dark }
}

/// Media and player-selected swatches may use any colour. Use the highest
/// contrast monochrome ink, instead of assuming white is always readable.
func wyrmReadableInk(on background: Color) -> Color {
    let ui = UIColor(background).resolvedColor(with: UITraitCollection(userInterfaceStyle: WyrmThemeStore.shared.palette.dark ? .dark : .light))
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
    guard ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return ATheme.ink }
    let colour = WyrmRGBA(r: Double(red), g: Double(green), b: Double(blue), a: 1)
    return contrastRatio(colour, .white) >= contrastRatio(colour, WyrmRGBA(argb: 0xFF000000)) ? .white : .black
}
private struct WyrmHeroScope: ViewModifier {
    @Environment(\.wyrmPaletteOverride) private var inherited
    @ObservedObject private var theme = WyrmThemeStore.shared
    let slot: Int
    func body(content: Content) -> some View {
        content.environment(\.wyrmPaletteOverride, (inherited ?? theme.palette).heroView(slot: slot))
    }
}
extension View {
    func wyrmHero(_ slot: Int = 1) -> some View { modifier(WyrmHeroScope(slot: slot)) }
}

struct WyrmHeroCard<Content: View>: View {
    @Environment(\.wyrmPaletteOverride) private var inherited
    @ObservedObject private var theme = WyrmThemeStore.shared
    var slot: Int = 1
    var enabled = true
    @ViewBuilder let content: (WyrmThemeColours) -> Content
    var body: some View {
        let base = inherited ?? theme.palette
        let palette = enabled ? base.heroView(slot: slot) : base
        content(WyrmThemeColours(palette: palette))
            .foregroundColor(palette.ink.color)
            .environment(\.wyrmPaletteOverride, palette)
    }
}

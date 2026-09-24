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
    var dark: Bool

    init(_ c: [UInt32], dark: Bool) {
        let v = c.map(WyrmRGBA.init(argb:))
        paper = v[0]; card = v[1]; ink = v[2]; onInk = v[3]
        quiet = v[4]; mute = v[5]; rule = v[6]; rowRule = v[7]
        live = v[8]; link = v[9]; tabIdle = v[10]; tabBar = v[11]
        chevron = v[12]; badge = v[13]; well = v[14]; track = v[15]
        hover = v[16]
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
    func readable(against foreground: WyrmRGBA, minimum: Double = 4.5) -> WyrmRGBA {
        if contrastRatio(self, foreground) >= minimum { return self }
        let target: WyrmRGBA = foreground.luminance < 0.5 ? .white : .nearBlack
        var low = 0.0, high = 1.0
        for _ in 0..<12 {
            let middle = (low + high) / 2
            if contrastRatio(mix(towards: target, middle), foreground) >= minimum { high = middle } else { low = middle }
        }
        return mix(towards: target, high)
    }
}

enum WyrmThemeID: String, CaseIterable, Identifiable {
    case paper, graphite, blush, sun, slate, lilac, forest, midnight
    var id: String { rawValue }

    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var description: String {
        switch self {
        case .paper: return "The original warm Wyrm canvas"
        case .graphite: return "Charcoal paper, warm readable type"
        case .blush: return "Soft rose paper with berry ink"
        case .sun: return "Cream and ochre without harsh glare"
        case .slate: return "Cool grey field with crisp graphite"
        case .lilac: return "Pale violet paper with aubergine ink"
        case .forest: return "Muted sage with deep evergreen ink"
        case .midnight: return "Blue-black paper with cool moonlit type"
        }
    }

    /// Byte-for-byte the Android `WyrmThemeId` table.
    var palette: WyrmPalette {
        switch self {
        case .paper: return WyrmPalette([
            0xFFF7F6F3, 0xFFFFFFFF, 0xFF37352F, 0xFFFFFFFF, 0xFF787774, 0xFF6B6660, 0x1437352F, 0x1237352F,
            0xFF448361, 0xFF2F6FDE, 0xFF7C776F, 0xF0FCFBFA, 0xFFC6C1B8, 0xFFC4554D, 0xFFF0EEE9, 0xFFEFEDE8,
            0xFFFAF9F7], dark: false)
        case .graphite: return WyrmPalette([
            0xFF171816, 0xFF222321, 0xFFF2EFE8, 0xFF171816, 0xFFB9B5AD, 0xFFD1CDC4, 0x24F2EFE8, 0x1CF2EFE8,
            0xFF72B68F, 0xFF8CB4FF, 0xFFA7A39B, 0xF01D1E1C, 0xFF77746E, 0xFFE17B72, 0xFF2B2C29, 0xFF30312E,
            0xFF282926], dark: true)
        case .blush: return WyrmPalette([
            0xFFFFF4F5, 0xFFFFFBFB, 0xFF4C3036, 0xFFFFFBFB, 0xFF8B696F, 0xFF73555B, 0x184C3036, 0x124C3036,
            0xFF3F8062, 0xFF9D4561, 0xFF8A7074, 0xF0FFF9FA, 0xFFCDB7BA, 0xFFC44F5F, 0xFFF7E7E9, 0xFFF3E1E4,
            0xFFFFF8F8], dark: false)
        case .sun: return WyrmPalette([
            0xFFFFF8DE, 0xFFFFFCF0, 0xFF463B22, 0xFFFFFCF0, 0xFF817254, 0xFF695C40, 0x18463B22, 0x12463B22,
            0xFF487A59, 0xFF9A681D, 0xFF82765E, 0xF0FFFAE9, 0xFFC9BB96, 0xFFB94F47, 0xFFF4EAC8, 0xFFF1E5BD,
            0xFFFFFBEA], dark: false)
        case .slate: return WyrmPalette([
            0xFFF0F2F3, 0xFFF9FAFA, 0xFF30383C, 0xFFF9FAFA, 0xFF687379, 0xFF566168, 0x1830383C, 0x1230383C,
            0xFF3F7D61, 0xFF356C8E, 0xFF727C81, 0xF0F5F7F7, 0xFFB8C0C3, 0xFFB65252, 0xFFE5E9EA, 0xFFE2E7E8,
            0xFFF5F7F7], dark: false)
        case .lilac: return WyrmPalette([
            0xFFF7F2FC, 0xFFFCFAFF, 0xFF403348, 0xFFFCFAFF, 0xFF796B81, 0xFF65566E, 0x18403348, 0x12403348,
            0xFF487D61, 0xFF7655A3, 0xFF7C7182, 0xF0FAF7FD, 0xFFC3B7CA, 0xFFC15362, 0xFFEDE4F2, 0xFFE9E0EF,
            0xFFFAF7FD], dark: false)
        case .forest: return WyrmPalette([
            0xFFF1F5ED, 0xFFFAFCF8, 0xFF2F3F34, 0xFFFAFCF8, 0xFF68766C, 0xFF536158, 0x182F3F34, 0x122F3F34,
            0xFF3D7B56, 0xFF356F5C, 0xFF707C73, 0xF0F7FAF5, 0xFFB6C2B7, 0xFFB95450, 0xFFE4EBDD, 0xFFE1E9DA,
            0xFFF7FAF5], dark: false)
        case .midnight: return WyrmPalette([
            0xFF101820, 0xFF19242D, 0xFFEAF1F4, 0xFF101820, 0xFFAAB8C0, 0xFFC5D0D5, 0x24EAF1F4, 0x1CEAF1F4,
            0xFF6DB68F, 0xFF83B8E8, 0xFF9DABB3, 0xF0141E27, 0xFF6B7B85, 0xFFE07972, 0xFF22303A, 0xFF283741,
            0xFF1E2A34], dark: true)
        }
    }
}

extension WyrmPalette {
    /// Android `WyrmPalette.withIntensity`: 50% is the palette as designed,
    /// the lower half walks towards Paper without losing text contrast and the
    /// upper half only adds chroma.
    func withIntensity(_ intensity: Double) -> WyrmPalette {
        let safe = min(1, max(0, intensity))
        if abs(safe - 0.5) < 0.0001 { return self }
        if safe < 0.5 {
            let base = WyrmThemeID.paper.palette
            if safe < 0.0001 { return base }
            let amount = safe * 2
            let rawPaper = base.paper.mix(towards: paper, amount)
            let rawCard = base.card.mix(towards: card, amount)
            let rawWell = base.well.mix(towards: well, amount)
            let surfaces = [rawPaper, rawCard, rawWell]
            let baseScore = surfaces.map { contrastRatio($0, base.ink) }.min() ?? 0
            let themeScore = surfaces.map { contrastRatio($0, ink) }.min() ?? 0
            let fallbackInk = [WyrmRGBA.nearBlack, .white].max { a, b in
                (surfaces.map { contrastRatio($0, a) }.min() ?? 0) < (surfaces.map { contrastRatio($0, b) }.min() ?? 0)
            } ?? .nearBlack
            let mixedInk: WyrmRGBA
            if baseScore >= 4.5 && baseScore >= themeScore { mixedInk = base.ink }
            else if themeScore >= 4.5 { mixedInk = ink }
            else { mixedInk = fallbackInk }
            let useThemeText = mixedInk == ink || mixedInk.luminance > 0.5
            let mixedOnInk: WyrmRGBA
            if mixedInk == base.ink { mixedOnInk = base.onInk }
            else if mixedInk == ink { mixedOnInk = onInk }
            else { mixedOnInk = mixedInk.luminance > 0.5 ? .nearBlack : .white }
            var out = self
            out.paper = rawPaper.readable(against: mixedInk)
            out.card = rawCard.readable(against: mixedInk)
            out.ink = mixedInk
            out.onInk = mixedOnInk
            out.quiet = useThemeText ? quiet : base.quiet
            out.mute = useThemeText ? mute : base.mute
            out.rule = base.rule.mix(towards: rule, amount)
            out.rowRule = base.rowRule.mix(towards: rowRule, amount)
            out.live = base.live.mix(towards: live, amount)
            out.link = base.link.mix(towards: link, amount)
            out.tabIdle = useThemeText ? tabIdle : base.tabIdle
            out.tabBar = base.tabBar.mix(towards: tabBar, amount)
            out.chevron = useThemeText ? chevron : base.chevron
            out.badge = base.badge.mix(towards: badge, amount)
            out.well = rawWell.readable(against: mixedInk)
            out.track = base.track.mix(towards: track, amount)
            out.hover = base.hover.mix(towards: hover, amount)
            out.dark = out.paper.luminance < 0.45
            return out
        }
        var out = self
        for path in [\WyrmPalette.paper, \.card, \.ink, \.onInk, \.quiet, \.mute, \.rule, \.rowRule,
                     \.live, \.link, \.tabIdle, \.tabBar, \.chevron, \.badge, \.well, \.track, \.hover] {
            out[keyPath: path] = self[keyPath: path].withIntensity(safe)
        }
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

    @Published private(set) var theme: WyrmThemeID
    @Published private(set) var intensity: Double
    @Published private(set) var palette: WyrmPalette
    /// The intensity the rest of the shell has been rebuilt with. It trails the
    /// slider by a moment so dragging never tears down the slider under the finger.
    @Published private(set) var committedIntensity: Double
    private var commitWork: DispatchWorkItem?

    private init() {
        let defaults = UserDefaults.standard
        // Earlier builds stored the display name ("Paper"); both spellings resolve.
        let stored = defaults.string(forKey: Self.themeKey)?.lowercased() ?? "paper"
        let theme = WyrmThemeID(rawValue: stored) ?? .paper
        let intensity = defaults.object(forKey: Self.intensityKey) as? Double ?? 0.5
        self.theme = theme
        self.intensity = intensity
        committedIntensity = intensity
        palette = theme.palette.withIntensity(intensity)
    }

    /// Changing appearance rebuilds the whole shell (see `WyrmDesignMain`),
    /// so the key doubles as the identity that forces that rebuild.
    var identity: String { "\(theme.rawValue)-\(Int((committedIntensity * 1000).rounded()))" }

    func select(_ next: WyrmThemeID) {
        guard next != theme else { return }
        theme = next
        UserDefaults.standard.set(next.rawValue, forKey: Self.themeKey)
        recompute()
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
        palette = theme.palette.withIntensity(intensity)
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
        control.setTitleTextAttributes([.font: manrope(.bold, 13), .foregroundColor: UIColor(palette.ink.color)], for: .selected)
    }

    /// The engine's twelve arena roles, in `arena_theme_role` order.
    func publishArenaTheme() {
        let p = palette
        let roles: [UInt32] = [p.paper, p.card, p.ink, p.onInk, p.quiet, p.mute, p.rule,
                               p.live, p.link, p.well, p.track, p.badge].map(\.argb)
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

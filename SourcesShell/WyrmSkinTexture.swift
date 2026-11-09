import CoreGraphics
import SwiftUI

/// Skin textures (OM, 2026-10-25), NTL 9.76's "Skin texture": the engine's `skin.texture`
/// (0 Default, 1 Rounded plain, 2 Squared plain, 3 NTL textured, 4 Striped plain) and
/// `skin.texture_mine` (my snake only, or every snake). The engine draws the arena
/// (game/redraw.c skin_texture_apply, bp.slang); here the Skin page's preview and the pattern
/// editor's beads wear the same texture, through `bead(_:)`. Android twin: ui/SkinTexture.kt.
final class WyrmSkinTexture: ObservableObject {
    static let shared = WyrmSkinTexture()
    static let names = ["Wyrm", "Rounded plain", "Squared plain", "NTL textured", "Striped plain",
                        "Glossy", "Matte", "Neon", "Pearl", "Metal"]
    /// What the picker offers (OM, 2026-10-26): eight. 2 and 4 (Squared and Striped plain)
    /// are retired and draw Wyrm's beads.
    static let offered = [0, 3, 1, 5, 6, 7, 8, 9]
    static let drawn: Set<Int> = [1, 3, 5, 6, 7, 8, 9]
    /// A drawn texture is on: beads are plain, upright, light at the top left.
    var drawnNow: Bool { Self.drawn.contains(current) }

    @Published var current = 0
    @Published var mine = false
    private var cache: [Int: CGImage] = [:]

    /// This colour's bead in `texture` (the current one by default); nil for Default.
    func bead(_ rgb: UInt32, texture: Int? = nil) -> CGImage? {
        let kind = texture ?? current
        guard Self.drawn.contains(kind) else { return nil }
        let key = (kind << 24) | Int(rgb & 0xFF_FFFF)
        if let made = cache[key] { return made }
        guard let made = Self.render(kind, rgb) else { return nil }
        cache[key] = made
        return made
    }

    private static func render(_ kind: Int, _ rgb: UInt32) -> CGImage? {
        let s = 96
        guard let ctx = CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let r = CGFloat((rgb >> 16) & 0xFF) / 255, g = CGFloat((rgb >> 8) & 0xFF) / 255, b = CGFloat(rgb & 0xFF) / 255
        let box = CGRect(x: 1, y: 1, width: CGFloat(s) - 2, height: CGFloat(s) - 2)
        switch kind {
        case 1:
            ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
            ctx.fillEllipse(in: box)
        case 3:
            // NTL's soft shaded ball: light from the upper left, a darker rim (bp.slang).
            func scaled(_ f: CGFloat) -> CGColor {
                CGColor(red: min(r * f, 1), green: min(g * f, 1), blue: min(b * f, 1), alpha: 1)
            }
            ctx.saveGState()
            ctx.addEllipse(in: box)
            ctx.clip()
            let colours = [scaled(1.2), scaled(0.95), scaled(0.62)] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours,
                                         locations: [0, 0.5, 1]) {
                // CoreGraphics' y runs up: the light sits at the upper left of the picture.
                let light = CGPoint(x: CGFloat(s) * 0.35, y: CGFloat(s) * 0.67)
                ctx.drawRadialGradient(gradient, startCenter: light, startRadius: 0, endCenter: light,
                                       endRadius: CGFloat(s) * 0.62, options: [.drawsAfterEndLocation])
            }
            ctx.restoreGState()
        default:
            drawNew(ctx, kind, r, g, b, box, CGFloat(s))
        }
        return ctx.makeImage()
    }

    /// The five of 2026-10-26, as bp.slang draws them: upright, light at the top left.
    /// CoreGraphics' y runs up, so "top" is the larger y.
    private static func drawNew(_ ctx: CGContext, _ kind: Int, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                                _ box: CGRect, _ s: CGFloat) {
        let space = CGColorSpaceCreateDeviceRGB()
        func c(_ f: CGFloat, _ add: CGFloat = 0) -> CGColor {
            CGColor(red: min(max(r * f + add, 0), 1), green: min(max(g * f + add, 0), 1),
                    blue: min(max(b * f + add, 0), 1), alpha: 1)
        }
        func radial(_ colours: [CGColor], _ at: CGPoint, _ radius: CGFloat, _ stops: [CGFloat]) {
            guard let gradient = CGGradient(colorsSpace: space, colors: colours as CFArray, locations: stops) else { return }
            ctx.drawRadialGradient(gradient, startCenter: at, startRadius: 0, endCenter: at, endRadius: radius,
                                   options: [.drawsAfterEndLocation])
        }
        ctx.saveGState()
        ctx.addEllipse(in: box)
        ctx.clip()
        switch kind {
        case 5: // Glossy
            radial([c(1.08), c(0.85), c(0.5)], CGPoint(x: s * 0.35, y: s * 0.67), s * 0.62, [0, 0.55, 1])
            if let spot = CGGradient(colorsSpace: space, colors: [CGColor(gray: 1, alpha: 0.85), CGColor(gray: 1, alpha: 0)] as CFArray,
                                     locations: [0, 1]) {
                let at = CGPoint(x: s * 0.32, y: s * 0.72)
                ctx.drawRadialGradient(spot, startCenter: at, startRadius: 0, endCenter: at, endRadius: s * 0.2, options: [])
            }
        case 6: // Matte
            radial([c(1.0), c(0.98), c(0.72)], CGPoint(x: s / 2, y: s / 2), s / 2, [0, 0.55, 1])
        case 7: // Neon
            ctx.setFillColor(c(0.22))
            ctx.fill(box)
            ctx.setStrokeColor(c(1.6, 0.12))
            let radius = (s / 2 - 1) * 0.78
            ctx.setLineWidth((s / 2 - 1) * 0.36)
            ctx.strokeEllipse(in: CGRect(x: s / 2 - radius, y: s / 2 - radius, width: radius * 2, height: radius * 2))
        case 8: // Pearl
            func pearl(_ f: CGFloat, _ add: CGFloat) -> CGColor {
                func ch(_ v: CGFloat) -> CGFloat { min(max((v * 0.7 + 0.3) * f + add, 0), 1) }
                return CGColor(red: ch(r), green: ch(g), blue: ch(b), alpha: 1)
            }
            radial([pearl(1.08, 0.1), pearl(0.9, 0.04), pearl(0.78, 0)], CGPoint(x: s * 0.35, y: s * 0.68), s * 0.75, [0, 0.5, 1])
        default: // Metal
            if let gradient = CGGradient(colorsSpace: space, colors: [c(0.95), c(1.0, 0.3), c(0.75), c(0.45), c(0.8)] as CFArray,
                                         locations: [0, 0.3, 0.45, 0.75, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
            }
        }
        ctx.restoreGState()
    }
}

/// Skin tab › Pattern: "Select texture" and, once open, the five textures with Mine / Everyone.
struct WyrmSkinTextureSelector: View {
    @Environment(\.wyrmPaletteOverride) private var wyrmPaletteOverride
    private var wyrmScopedColours: WyrmThemeColours { WyrmThemeColours(palette: wyrmPaletteOverride ?? WyrmThemeStore.shared.palette) }

    @ObservedObject var texture = WyrmSkinTexture.shared
    let onPick: (Int) -> Void
    let onMine: (Bool) -> Void
    @State private var open = false

    init(initiallyOpen: Bool = false, onPick: @escaping (Int) -> Void, onMine: @escaping (Bool) -> Void) {
        self.onPick = onPick; self.onMine = onMine; _open = State(initialValue: initiallyOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                HStack {
                    Text("Select texture").font(.androidWyrm(15, .bold)).foregroundColor(wyrmScopedColours.ink)
                    Spacer()
                    Text(WyrmSkinTexture.names[WyrmSkinTexture.offered.contains(texture.current) ? texture.current : 0])
                        .font(.androidWyrm(13.5, .semibold)).foregroundColor(wyrmScopedColours.mute)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(wyrmScopedColours.card))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(wyrmScopedColours.rule, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            if open {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(WyrmSkinTexture.offered, id: \.self) { index in
                        tile(index)
                    }
                }
                WSSegmented(options: ["Mine", "Everyone"], selected: texture.mine ? 0 : 1) { picked in
                    texture.mine = picked == 0
                    onMine(picked == 0)
                }
                Text("Mine puts the texture on your snake only. Everyone draws every snake in it. Every texture is light to draw, and far away fewer beads are drawn, so the game stays smooth.")
                    .font(.androidWyrm(12.5, .regular)).foregroundColor(wyrmScopedColours.mute)
            }
        }
        .padding(.horizontal, 20)
    }

    private func tile(_ index: Int) -> some View {
        let selected = texture.current == index || (index == 0 && !WyrmSkinTexture.offered.contains(texture.current))
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            texture.current = index
            onPick(index)
        } label: {
            VStack(spacing: 6) {
                Canvas { context, size in
                    let hues: [UInt32] = [0xC080FF, 0x9099FF, 0x80D0D0, 0x80FF80, 0xEEEE70, 0xFFA060]
                    let d = size.height * 0.8
                    let step = (size.width - d) / 5
                    for (i, hue) in hues.enumerated() {
                        let rect = CGRect(x: CGFloat(i) * step, y: (size.height - d) / 2, width: d, height: d)
                        if let image = WyrmSkinTexture.shared.bead(hue, texture: index) {
                            context.draw(Image(decorative: image, scale: 1), in: rect)
                        } else {
                            context.fill(Path(ellipseIn: rect), with: .color(Color(rgb: hue)))
                        }
                    }
                }
                .frame(height: 34)
                Text(WyrmSkinTexture.names[index]).font(.androidWyrm(12, selected ? .bold : .semibold))
                    .foregroundColor(selected ? wyrmScopedColours.ink : wyrmScopedColours.mute).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(wyrmScopedColours.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? wyrmScopedColours.ink : wyrmScopedColours.rule, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(WyrmSkinTexture.names[index]) texture")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension Color {
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xff) / 255,
                  green: Double((rgb >> 8) & 0xff) / 255,
                  blue: Double(rgb & 0xff) / 255)
    }
}

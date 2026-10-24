import CoreGraphics
import SwiftUI

/// Skin textures (OM, 2026-10-25), NTL 9.76's "Skin texture": the engine's `skin.texture`
/// (0 Default, 1 Rounded plain, 2 Squared plain, 3 NTL textured, 4 Striped plain) and
/// `skin.texture_mine` (my snake only, or every snake). The engine draws the arena
/// (game/redraw.c skin_texture_apply, bp.slang); here the Skin page's preview and the pattern
/// editor's beads wear the same texture, through `bead(_:)`. Android twin: ui/SkinTexture.kt.
final class WyrmSkinTexture: ObservableObject {
    static let shared = WyrmSkinTexture()
    static let names = ["Default", "Rounded plain", "Squared plain", "NTL textured", "Striped plain"]

    @Published var current = 0
    @Published var mine = false
    private var cache: [Int: CGImage] = [:]

    /// This colour's bead in `texture` (the current one by default); nil for Default.
    func bead(_ rgb: UInt32, texture: Int? = nil) -> CGImage? {
        let kind = texture ?? current
        guard (1...4).contains(kind) else { return nil }
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
            ctx.setFillColor(red: r, green: g, blue: b, alpha: 1)
            ctx.fill(box)
        }
        return ctx.makeImage()
    }
}

/// Skin tab › Pattern: "Select texture" and, once open, the five textures with Mine / Everyone.
struct WyrmSkinTextureSelector: View {
    @ObservedObject var texture = WyrmSkinTexture.shared
    let onPick: (Int) -> Void
    let onMine: (Bool) -> Void
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                HStack {
                    Text("Select texture").font(.androidWyrm(15, .bold)).foregroundColor(ATheme.ink)
                    Spacer()
                    Text(WyrmSkinTexture.names[min(max(texture.current, 0), 4)])
                        .font(.androidWyrm(13.5, .semibold)).foregroundColor(ATheme.mute)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ATheme.card))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ATheme.rule, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            if open {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(WyrmSkinTexture.names.indices, id: \.self) { index in
                        tile(index)
                    }
                }
                WSSegmented(options: ["Mine", "Everyone"], selected: texture.mine ? 0 : 1) { picked in
                    texture.mine = picked == 0
                    onMine(picked == 0)
                }
                Text("Mine puts the texture on your snake only. Everyone draws every snake in it. Far away fewer beads are drawn, so the game stays light.")
                    .font(.androidWyrm(12.5, .regular)).foregroundColor(ATheme.mute)
            }
        }
        .padding(.horizontal, 20)
    }

    private func tile(_ index: Int) -> some View {
        let selected = texture.current == index
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
                    .foregroundColor(selected ? ATheme.ink : ATheme.mute).lineLimit(1).minimumScaleFactor(0.8)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(ATheme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? ATheme.ink : ATheme.rule, lineWidth: selected ? 2 : 1))
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

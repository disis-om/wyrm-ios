import SwiftUI

/// Wyrm looks: hair, ears and glasses (OM, 2026-09-28).
///
/// Drawn only over the player's own snake and only on this phone: none of it
/// goes into the join packet or to anyone else. The art is one 8 x 8 atlas,
/// `Resources/WyrmAccessories.png` (Scripts/generate-wyrm-accessories.py);
/// the engine draws it in SourcesOriginal/AppleWyrmLook.c and this file
/// mirrors its layout for the Skin Studio. Android: `ui/WyrmLook.kt`.
enum WyrmLook {
    static let hairNames = ["Fluffy", "Flame", "Pom", "Dreadlocks", "Mohawk", "Ponytail",
                            "Pigtails", "Braid", "Long hair", "Space buns", "Man bun", "Bob"]
    static let earNames = ["Panda", "Bunny", "Lop bunny", "Cat", "Mouse", "Bear",
                           "Koala", "Fox", "Wolf", "Tiger", "Bat", "Dragon"]
    static let glassesNames = ["Heart", "Cat-eye", "Flower", "Pastel", "Nerd", "Sparkle",
                               "Aviator", "Pixel", "Cyber visor", "Evil visor", "Steampunk", "Punk"]
    /// Hair tints: the hair art is light grey and takes one of these.
    static let hairColours: [(name: String, rgb: UInt32)] = [
        ("Brown", 0x96603A), ("Cream", 0xF6E4C4), ("Purple", 0xAA7DF0),
        ("Pink", 0xFF8FC0), ("White", 0xFFFFFF), ("Black", 0x46464E),
    ]

    static let capSide: CGFloat = 4.4
    static let capBack: CGFloat = 0.6
    static let flowSpan: CGFloat = 3.4

    /// A style's flows: (atlas cell, root x, root y) in head radii, x forward.
    static func flows(_ style: Int) -> [(cell: Int, x: CGFloat, y: CGFloat)] {
        switch style {
        case 5: return [(12, -0.9, 0)]
        case 6: return [(13, -0.55, -0.8), (13, -0.55, 0.8)]
        case 7: return [(14, -0.95, 0)]
        case 8: return [(15, -0.6, 0)]
        default: return []
        }
    }

    static func color(_ rgb: UInt32) -> Color {
        Color(red: Double((rgb >> 16) & 0xff) / 255, green: Double((rgb >> 8) & 0xff) / 255, blue: Double(rgb & 0xff) / 255)
    }

    /// The look on a head at `head` with radius `r`, facing +x: hair at rest
    /// (flows straight back), then ears and glasses.
    static func draw(in context: GraphicsContext, cells: [Int: CGImage], head: CGPoint, r: CGFloat,
                     hair: Int, hairRGB: UInt32, ears: Int, glasses: Int) {
        func put(_ image: CGImage, _ rect: CGRect, tint: Color?, flip: CGFloat? = nil) {
            var c = context
            if let tint { c.addFilter(.colorMultiply(tint)) }
            if let pivot = flip {
                c.translateBy(x: pivot, y: 0)
                c.scaleBy(x: -1, y: 1)
                c.translateBy(x: -pivot, y: 0)
            }
            c.draw(Image(decorative: image, scale: 1), in: rect)
        }
        if hair >= 0 {
            let tint = color(hairRGB)
            for flow in flows(hair) {
                guard let image = cells[flow.cell] else { continue }
                let side = flowSpan * r
                let root = CGPoint(x: head.x + flow.x * r, y: head.y + flow.y * r)
                // The flow cell runs +x from its root; at rest it lies straight back.
                put(image, CGRect(x: root.x, y: root.y - side / 2, width: side, height: side), tint: tint, flip: root.x)
            }
            if let image = cells[hair] {
                let side = capSide * r
                put(image, CGRect(x: head.x - capBack * r - side / 2, y: head.y - side / 2, width: side, height: side), tint: tint)
            }
        }
        if ears >= 0, let image = cells[16 + ears] {
            put(image, CGRect(x: head.x - 2 * r, y: head.y - 2 * r, width: 4 * r, height: 4 * r), tint: nil)
        }
        if glasses >= 0, let image = cells[28 + glasses] {
            put(image, CGRect(x: head.x - 2 * r, y: head.y - 2 * r, width: 4 * r, height: 4 * r), tint: nil)
        }
    }
}

/// The saved look, handed to the engine through `WyrmIOSSetLook`, the way
/// `WyrmArrowSkinStore` hands over the arrow.
final class WyrmLookStore: ObservableObject {
    static let shared = WyrmLookStore()

    @Published private(set) var hair: Int
    @Published private(set) var hairColour: Int
    @Published private(set) var ears: Int
    @Published private(set) var glasses: Int

    private init() {
        let d = UserDefaults.standard
        func pick(_ key: String, _ count: Int) -> Int {
            let v = d.object(forKey: key) as? Int ?? -1
            return (0..<count).contains(v) ? v : -1
        }
        hair = pick("wyrm.ios.look.hair", WyrmLook.hairNames.count)
        hairColour = min(max(d.object(forKey: "wyrm.ios.look.hair-colour") as? Int ?? 0, 0), WyrmLook.hairColours.count - 1)
        ears = pick("wyrm.ios.look.ears", WyrmLook.earNames.count)
        glasses = pick("wyrm.ios.look.glasses", WyrmLook.glassesNames.count)
    }

    var hairRGB: UInt32 { WyrmLook.hairColours[hairColour].rgb }

    func publish() {
        WyrmIOSSetLook(Int32(hair), Int32(hairRGB), Int32(ears), Int32(glasses))
    }

    func pickHair(_ v: Int) { hair = WyrmLook.hairNames.indices.contains(v) ? v : -1; save() }
    func pickHairColour(_ v: Int) { hairColour = min(max(v, 0), WyrmLook.hairColours.count - 1); save() }
    func pickEars(_ v: Int) { ears = WyrmLook.earNames.indices.contains(v) ? v : -1; save() }
    func pickGlasses(_ v: Int) { glasses = WyrmLook.glassesNames.indices.contains(v) ? v : -1; save() }

    private func save() {
        let d = UserDefaults.standard
        d.set(hair, forKey: "wyrm.ios.look.hair")
        d.set(hairColour, forKey: "wyrm.ios.look.hair-colour")
        d.set(ears, forKey: "wyrm.ios.look.ears")
        d.set(glasses, forKey: "wyrm.ios.look.glasses")
        publish()
    }
}

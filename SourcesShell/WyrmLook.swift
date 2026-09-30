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
    /// The hair colour slider (OM, 2026-09-28: one slider, not six beads). The
    /// hair art is light grey and takes the colour at the slider's position.
    static let hairStops: [(at: Double, rgb: UInt32)] = [
        (0.00, 0x2A2A30), (0.12, 0x4A2E1A), (0.22, 0x96603A), (0.32, 0xB0452A),
        (0.40, 0xE07A30), (0.48, 0xF2D28A), (0.54, 0xF6E4C4), (0.60, 0xFFFFFF),
        (0.70, 0xFF8FC0), (0.78, 0xAA7DF0), (0.86, 0x5A8CF0), (0.93, 0x3EC6C0),
        (1.00, 0x4CC05A),
    ]

    /// The colour at `tone` (0...1) along `hairStops`.
    static func hairTone(_ tone: Double) -> UInt32 {
        let t = min(max(tone, 0), 1)
        let next = max(1, hairStops.firstIndex { $0.at >= t } ?? hairStops.count - 1)
        let a = hairStops[next - 1], b = hairStops[next]
        let f = b.at > a.at ? min(max((t - a.at) / (b.at - a.at), 0), 1) : 0
        func mix(_ shift: UInt32) -> UInt32 {
            let x = Double((a.rgb >> shift) & 0xFF), y = Double((b.rgb >> shift) & 0xFF)
            return UInt32(min(max((x + (y - x) * f).rounded(), 0), 255)) << shift
        }
        return mix(16) | mix(8) | mix(0)
    }

    /// Where the six old hair colours sit on the slider, for saved looks.
    static let oldHairTones: [Double] = [0.22, 0.54, 0.78, 0.70, 0.60, 0.0]

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
    /// The hair colour slider's position, 0...1 along `WyrmLook.hairStops`.
    @Published private(set) var hairTone: Double
    @Published private(set) var ears: Int
    @Published private(set) var glasses: Int

    private init() {
        let d = UserDefaults.standard
        func pick(_ key: String, _ count: Int) -> Int {
            let v = d.object(forKey: key) as? Int ?? -1
            return (0..<count).contains(v) ? v : -1
        }
        hair = pick("wyrm.ios.look.hair", WyrmLook.hairNames.count)
        if let tone = d.object(forKey: "wyrm.ios.look.hair-tone") as? Double {
            hairTone = min(max(tone, 0), 1)
        } else {
            let old = d.object(forKey: "wyrm.ios.look.hair-colour") as? Int ?? 0
            hairTone = WyrmLook.oldHairTones.indices.contains(old) ? WyrmLook.oldHairTones[old] : 0.22
        }
        ears = pick("wyrm.ios.look.ears", WyrmLook.earNames.count)
        glasses = pick("wyrm.ios.look.glasses", WyrmLook.glassesNames.count)
    }

    var hairRGB: UInt32 { WyrmLook.hairTone(hairTone) }

    /// After a log in or log out rewrote the defaults (WyrmAccountSync): read and publish.
    func reloadFromDefaults() {
        let d = UserDefaults.standard
        func pick(_ key: String, _ count: Int) -> Int {
            let v = d.object(forKey: key) as? Int ?? -1
            return (0..<count).contains(v) ? v : -1
        }
        hair = pick("wyrm.ios.look.hair", WyrmLook.hairNames.count)
        hairTone = min(max(d.object(forKey: "wyrm.ios.look.hair-tone") as? Double ?? 0.22, 0), 1)
        ears = pick("wyrm.ios.look.ears", WyrmLook.earNames.count)
        glasses = pick("wyrm.ios.look.glasses", WyrmLook.glassesNames.count)
        publish()
    }

    func publish() {
        WyrmIOSSetLook(Int32(hair), Int32(hairRGB), Int32(ears), Int32(glasses))
    }

    func pickHair(_ v: Int) { hair = WyrmLook.hairNames.indices.contains(v) ? v : -1; save() }
    func pickHairTone(_ v: Double) { hairTone = min(max(v, 0), 1); save() }
    func pickEars(_ v: Int) { ears = WyrmLook.earNames.indices.contains(v) ? v : -1; save() }
    func pickGlasses(_ v: Int) { glasses = WyrmLook.glassesNames.indices.contains(v) ? v : -1; save() }

    /// Try this skin's Wear: a whole look at once, saved and handed to the
    /// engine once.
    func wear(hair: Int, hairTone: Double, ears: Int, glasses: Int) {
        self.hair = WyrmLook.hairNames.indices.contains(hair) ? hair : -1
        if hairTone.isFinite { self.hairTone = min(max(hairTone, 0), 1) }
        self.ears = WyrmLook.earNames.indices.contains(ears) ? ears : -1
        self.glasses = WyrmLook.glassesNames.indices.contains(glasses) ? glasses : -1
        save()
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(hair, forKey: "wyrm.ios.look.hair")
        d.set(hairTone, forKey: "wyrm.ios.look.hair-tone")
        d.set(ears, forKey: "wyrm.ios.look.ears")
        d.set(glasses, forKey: "wyrm.ios.look.glasses")
        publish()
    }
}

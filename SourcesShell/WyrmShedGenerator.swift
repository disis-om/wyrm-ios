import Foundation

/*
 * Shed (OM, 2026-10-15): the skin generator behind Home › Shed.
 *
 * A line-for-line port of Android's data/ShedGenerator.kt (itself the HTML
 * prototype's gen/beads.js + gen/skinGen.js), so the same recipe and lucky
 * number make the same skins on every platform: only the seeded dice drive
 * choices, the dice are mulberry32 bit for bit, rounding is JavaScript's
 * Math.round and every sort is stable. Every skin:
 *   - uses only the 38 official skin characters (the arena accepts no other),
 *   - fits the arena: at most 256 beads and 146 runs (NTL's 300-byte cut),
 *   - never puts two beads that look the same side by side,
 *   - is not a near copy of another skin in the batch or in the history.
 * Beads overlap and show 8/48 of their width, so a band of 1-2 beads is a
 * hairline: bands are built 3-9 beads wide, only a deliberate accent is 2.
 * Nothing here is synced to the account (OM): the recipe and the history of
 * skins already shown stay on the phone (`wyrm.ios.shed.`, wiped on log out).
 */

/// One official bead as it really looks (measured from tex_atlas_8k.png, not the palette hex).
struct WyrmShedBead {
    let ch: Character
    let id: Int
    let L: Double
    let hue: Int
    let sat: Double
    let stars: Bool
    let lab: [Double]
    let family: String

    init(_ ch: Character, _ id: Int, _ rgb: Int, _ L: Double, _ hue: Int, _ sat: Double, stars: Bool = false) {
        self.ch = ch; self.id = id; self.L = L; self.hue = hue; self.sat = sat; self.stars = stars
        self.lab = WyrmShedBead.labOf(rgb)
        if sat < 0.15 { family = "grey" }
        else if hue < 12 || hue >= 345 { family = "red" }
        else if hue < 35 { family = "orange" }
        else if hue < 70 { family = "yellow" }
        else if hue < 170 { family = "green" }
        else if hue < 205 { family = "aqua" }
        else if hue < 250 { family = "blue" }
        else if hue < 285 { family = "purple" }
        else { family = "pink" }
    }

    private static func labOf(_ rgb: Int) -> [Double] {
        func lin(_ v: Int) -> Double { let c = Double(v) / 255.0; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = lin((rgb >> 16) & 255), g = lin((rgb >> 8) & 255), b = lin(rgb & 255)
        let x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
        let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
        let z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
        func f(_ v: Double) -> Double { v > 0.008856 ? cbrt(v) : 7.787 * v + 16.0 / 116.0 }
        return [116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z))]
    }
}

enum WyrmShedBeads {
    /// id = colour group = cell (id % 7, id / 7) of the bead atlas (`WyrmSkinTextureLibrary.beads`).
    static let all: [WyrmShedBead] = [
        WyrmShedBead("z", 0, 0xB377E8, 0.605, 272, 0.71),
        WyrmShedBead("x", 1, 0x868FE8, 0.621, 235, 0.68),
        WyrmShedBead("c", 2, 0x77C2C2, 0.739, 180, 0.38),
        WyrmShedBead("v", 3, 0x77E877, 0.835, 120, 0.71),
        WyrmShedBead("b", 4, 0xDCDC68, 0.859, 60, 0.63),
        WyrmShedBead("n", 5, 0xE89559, 0.691, 25, 0.76),
        WyrmShedBead("m", 6, 0xE88686, 0.665, 0, 0.68),
        WyrmShedBead(",", 7, 0xE83B3B, 0.526, 0, 0.79),
        WyrmShedBead("a", 8, 0xD12CD1, 0.518, 300, 0.65),
        WyrmShedBead("s", 9, 0xE8E8E8, 0.92, 0, 0.0),
        WyrmShedBead("d", 10, 0x8A92E9, 0.632, 235, 0.68, stars: true),
        WyrmShedBead("f", 11, 0x4A4A4A, 0.316, 0, 0.0),
        WyrmShedBead("g", 12, 0xE8B34A, 0.761, 40, 0.78),
        WyrmShedBead("h", 13, 0x257F59, 0.473, 155, 0.55),
        WyrmShedBead("j", 14, 0x5D6DE8, 0.508, 233, 0.75),
        WyrmShedBead("k", 15, 0x707DE8, 0.56, 233, 0.72),
        WyrmShedBead("l", 16, 0x434EE8, 0.42, 236, 0.78),
        WyrmShedBead("q", 17, 0x954AE8, 0.485, 268, 0.78),
        WyrmShedBead("w", 18, 0xE8D13B, 0.835, 52, 0.79),
        WyrmShedBead("e", 19, 0x3540E8, 0.384, 236, 0.8, stars: true),
        WyrmShedBead("r", 20, 0x3541E8, 0.385, 236, 0.8, stars: true),
        WyrmShedBead("t", 21, 0x4920B3, 0.287, 256, 0.69),
        WyrmShedBead("y", 22, 0xE85008, 0.55, 19, 0.93),
        WyrmShedBead("u", 23, 0x5EBBD8, 0.714, 194, 0.61),
        WyrmShedBead("i", 24, 0x828182, 0.541, 0, 0.0),
        WyrmShedBead("o", 25, 0x38B343, 0.646, 125, 0.53),
        WyrmShedBead("p", 26, 0x1CF55D, 0.852, 138, 0.92),
        WyrmShedBead("1", 27, 0xD64444, 0.504, 0, 0.64),
        WyrmShedBead("2", 28, 0xD63535, 0.484, 0, 0.66),
        WyrmShedBead("3", 29, 0x505050, 0.338, 0, 0.0),
        WyrmShedBead("4", 30, 0x16169C, 0.207, 240, 0.75),
        WyrmShedBead("5", 31, 0x9C1616, 0.335, 0, 0.75),
        WyrmShedBead("6", 32, 0x848425, 0.536, 60, 0.56),
        WyrmShedBead("7", 33, 0x845322, 0.398, 30, 0.59),
        WyrmShedBead("8", 34, 0x842584, 0.338, 300, 0.56),
        WyrmShedBead("9", 35, 0x258425, 0.483, 120, 0.56),
        WyrmShedBead("0", 37, 0x6177E8, 0.536, 230, 0.75),
        WyrmShedBead("-", 39, 0x61259F, 0.303, 270, 0.62),
    ]
    private static let byCh: [Character: WyrmShedBead] = Dictionary(uniqueKeysWithValues: all.map { ($0.ch, $0) })
    static subscript(_ ch: Character) -> WyrmShedBead { byCh[ch]! }
    static func isOfficial(_ ch: Character) -> Bool { byCh[ch] != nil }

    /// How different two beads look (CIE76 delta E): ~0 same, 25+ clearly different.
    static func look(_ a: Character, _ b: Character) -> Double {
        let x = self[a].lab, y = self[b].lab
        return sqrt((x[0] - y[0]) * (x[0] - y[0]) + (x[1] - y[1]) * (x[1] - y[1]) + (x[2] - y[2]) * (x[2] - y[2]))
    }
    /// Below this two beads read as the same colour (x/d, e/r, ,/2/1, f/3 ...).
    static let sameLook = 12.0
}

/// What the player asked for.
struct WyrmShedRecipe: Equatable {
    var count = 8
    var mood = "cute"
    /// auto | light | dark | mix
    var tone = "auto"
    /// a theme key, or ""
    var theme = ""
    /// the player's own beads, or empty
    var colours: [Character] = []
    /// a style key, or "auto"
    var style = "auto"
    /// short | medium | long
    var size = "medium"
    /// auto | on | off
    var symmetry = "auto"
    /// 0..1
    var wildness = 0.25
    var seed: Int32 = 1
}

struct WyrmShedSkin: Identifiable {
    let code: String
    let key: String
    let runs: Int
    let mood: String
    let style: String
    let rule: String
    let seed: UInt32
    let colours: [Character]
    let score: Double
    var id: String { key }
}

/// The order-keeping maps the generator walks (Kotlin's LinkedHashMap).
struct WyrmShedOrdered<V> {
    let pairs: [(String, V)]
    var keys: [String] { pairs.map { $0.0 } }
    subscript(_ key: String) -> V? { pairs.first { $0.0 == key }?.1 }
    func contains(_ key: String) -> Bool { pairs.contains { $0.0 == key } }
}

enum WyrmShedGenerator {
    static let maxBeads = 256
    static let maxRuns = 146
    private static let accent = 2 // the thinnest band that still reads as a line
    private static let sameLook = WyrmShedBeads.sameLook

    struct Mood { let label: String; let lo: Int; let hi: Int }
    // The label is English (OM, 2026-10-15); the key "danger" stays.
    static let moods = WyrmShedOrdered<Mood>(pairs: [
        ("cute", Mood(label: "Cute", lo: 2, hi: 4)),
        ("danger", Mood(label: "Dangerous", lo: 2, hi: 3)),
        ("random", Mood(label: "Random", lo: 2, hi: 5)),
        ("pattern", Mood(label: "Pattern", lo: 2, hi: 3)),
        ("unique", Mood(label: "Unique", lo: 3, hi: 4)),
    ])
    static let styles = WyrmShedOrdered<String>(pairs: [
        ("stripes", "Stripes"), ("thickThin", "Thick & thin"), ("ramp", "Gradient"), ("rainbow", "Rainbow"),
        ("pulse", "Pulse"), ("band", "Band"), ("duo", "Duo"), ("fib", "Fibonacci"), ("weave", "Weave"),
        ("chaos", "Chaos"), ("starry", "Starry"),
    ])
    private static let moodStyles: [String: WyrmShedOrdered<Int>] = [
        "cute": WyrmShedOrdered(pairs: [("stripes", 3), ("ramp", 3), ("rainbow", 3), ("pulse", 2), ("duo", 2)]),
        "danger": WyrmShedOrdered(pairs: [("thickThin", 3), ("pulse", 3), ("band", 3), ("stripes", 1)]),
        "random": WyrmShedOrdered(pairs: [("stripes", 2), ("thickThin", 1), ("ramp", 2), ("rainbow", 1), ("pulse", 1), ("band", 1), ("duo", 1), ("fib", 1), ("weave", 1), ("chaos", 1)]),
        "pattern": WyrmShedOrdered(pairs: [("duo", 3), ("stripes", 2), ("weave", 3), ("band", 2), ("thickThin", 2), ("fib", 1)]),
        "unique": WyrmShedOrdered(pairs: [("fib", 2), ("weave", 2), ("chaos", 2), ("starry", 2), ("band", 1), ("ramp", 1)]),
    ]
    struct Theme { let label: String; let chars: String }
    static let themes = WyrmShedOrdered<Theme>(pairs: [
        ("fire", Theme(label: "Fire", chars: "y7,5ngw")), ("ice", Theme(label: "Ice", chars: "scuxk")), ("toxic", Theme(label: "Toxic", chars: "fph9v")),
        ("galaxy", Theme(label: "Galaxy", chars: "4t-qzea")), ("ocean", Theme(label: "Ocean", chars: "4eljucs")), ("candy", Theme(label: "Candy", chars: "mszvbu")),
        ("sunset", Theme(label: "Sunset", chars: "-a,yngw")), ("royal", Theme(label: "Royal", chars: "t-qwgs")), ("warning", Theme(label: "Warning", chars: "fw3b")),
        ("blood", Theme(label: "Blood", chars: "f5,3")), ("void", Theme(label: "Void", chars: "4t-8f")), ("forest", Theme(label: "Forest", chars: "h9ov67")),
    ])
    /// Band width in beads, per pattern size.
    static let sizes = WyrmShedOrdered<[Int]>(pairs: [("short", [3, 4]), ("medium", [4, 6]), ("long", [6, 9])])

    // Earthy, muddy beads: lovely in a theme or a dark skin, dull in a cute one.
    private static let earthy: Set<Character> = ["6", "7", "9", "i", "3", "h"]
    // Beads that glow against a dark base.
    private static let glow: [Character] = ["p", "y", "w", "s", ",", "a", "g", "v", "u", "b", "n"]

    private static func B(_ c: Character) -> WyrmShedBead { WyrmShedBeads[c] }
    private static func look(_ a: Character, _ b: Character) -> Double { WyrmShedBeads.look(a, b) }

    // ------------------------------------------------------------ dice

    /// mulberry32, bit for bit as in JavaScript.
    private final class Dice {
        private var a: UInt32
        init(_ seed: UInt32) { a = seed }
        func next() -> Double {
            a = a &+ 0x6d2b79f5
            var t = a
            t = (t ^ (t >> 15)) &* (t | 1)
            t = t ^ (t &+ ((t ^ (t >> 7)) &* (t | 61)))
            return Double(t ^ (t >> 14)) / 4294967296.0
        }
        func int(_ lo: Int, _ hi: Int) -> Int { lo + Int(floor(next() * Double(hi - lo + 1))) }
        func pick<T>(_ list: [T]) -> T { list[Int(floor(next() * Double(list.count)))] }
        func chance(_ p: Double) -> Bool { next() < p }
        func weighted(_ map: WyrmShedOrdered<Int>) -> String {
            let sum = map.pairs.reduce(0) { $0 + $1.1 }
            var r = next() * Double(sum)
            for (k, w) in map.pairs { r -= Double(w); if r < 0 { return k } }
            return map.pairs.last!.0
        }
        func shuffle<T>(_ list: [T]) -> [T] {
            var out = list
            var i = out.count - 1
            while i >= 1 {
                let j = Int(floor(next() * Double(i + 1)))
                out.swapAt(i, j)
                i -= 1
            }
            return out
        }
    }

    static func mixSeed(_ seed: UInt32, _ n: Int) -> UInt32 {
        var h = seed ^ (UInt32(truncatingIfNeeded: n + 1) &* 0x9e3779b9)
        h = (h ^ (h >> 16)) &* 0x85ebca6b
        h = (h ^ (h >> 13)) &* 0xc2b2ae35
        return h ^ (h >> 16)
    }
    /// JavaScript's Math.round (and Java's): half up.
    private static func jsRound(_ x: Double) -> Int { Int(floor(x + 0.5)) }

    /// Kotlin's sortedWith: stable.
    private static func stableSorted<T>(_ list: [T], _ less: (T, T) -> Bool) -> [T] {
        list.enumerated().sorted { a, b in
            if less(a.element, b.element) { return true }
            if less(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map { $0.element }
    }
    /// Kotlin's toSet(): distinct, in order of first appearance.
    private static func distinctOrdered<S: Sequence>(_ s: S) -> [Character] where S.Element == Character {
        var seen = Set<Character>(); var out: [Character] = []
        for c in s where !seen.contains(c) { seen.insert(c); out.append(c) }
        return out
    }

    // ------------------------------------------------------------ colours

    private static func hueGap(_ a: Int, _ b: Int) -> Int { let d = abs(a - b) % 360; return d > 180 ? 360 - d : d }

    /// Add `ch` only if it looks clearly different from every colour already in.
    @discardableResult
    private static func addDistinct(_ set: inout [Character], _ ch: Character, _ minLook: Double = 18.0) -> Bool {
        if set.contains(where: { look($0, ch) < minLook }) { return false }
        set.append(ch)
        return true
    }

    private static func poolFor(_ r: WyrmShedRecipe, _ mood: String) -> [Character] {
        let tone = r.tone == "auto" ? (["cute": "light", "danger": "dark", "random": "mix", "pattern": "mix", "unique": "mix"][mood] ?? "") : r.tone
        var pool = WyrmShedBeads.all.filter { !$0.stars }
        if mood != "danger" && tone != "dark" { pool = pool.filter { !earthy.contains($0.ch) } }
        if mood == "cute" { pool = pool.filter { $0.ch != "p" && $0.ch != "y" } }
        if tone == "light" { pool = pool.filter { $0.L >= 0.6 } }
        if tone == "dark" { pool = pool.filter { $0.L < 0.55 } }
        return pool.map { $0.ch }
    }

    private static func sortedBy(_ list: [Character], _ key: (Character) -> Double) -> [Character] {
        stableSorted(list) { a, b in
            let ka = key(a), kb = key(b)
            if ka != kb { return ka < kb }
            return B(a).id < B(b).id
        }
    }

    private static func ruleAnalogous(_ pool: [Character], _ k: Int, _ d: Dice) -> [Character] {
        let coloured = pool.filter { B($0).sat >= 0.3 }
        let first = d.pick(coloured.isEmpty ? pool : coloured)
        var out = [first]
        for c in sortedBy(pool, { Double(hueGap(B($0).hue, B(first).hue)) }) {
            if out.count >= k { break }
            if hueGap(B(c).hue, B(first).hue) <= 70 && B(c).sat >= 0.3 { addDistinct(&out, c) }
        }
        return out
    }
    private static func ruleComplement(_ pool: [Character], _ k: Int, _ d: Dice) -> [Character] {
        let coloured = pool.filter { B($0).sat >= 0.4 }
        let first = d.pick(coloured.isEmpty ? pool : coloured)
        var out = [first]
        for c in sortedBy(pool, { Double(abs(hueGap(B($0).hue, B(first).hue) - 180)) }) {
            if B(c).sat >= 0.3 && addDistinct(&out, c, 30.0) { break }
        }
        for c in d.shuffle(Array("sf4tc")).filter({ pool.contains($0) }) {
            if out.count >= k { break }
            addDistinct(&out, c, 25.0)
        }
        return out
    }
    private static func ruleTriad(_ pool: [Character], _ k: Int, _ d: Dice) -> [Character] {
        let coloured = pool.filter { B($0).sat >= 0.4 }
        let first = d.pick(coloured.isEmpty ? pool : coloured)
        var out = [first]
        for shift in [120, 240] {
            let target = (B(first).hue + shift) % 360
            for c in sortedBy(coloured, { Double(hueGap(B($0).hue, target)) }) {
                if addDistinct(&out, c, 25.0) { break }
            }
        }
        return Array(out.prefix(max(2, k)))
    }
    private static func ruleMono(_ pool: [Character], _ k: Int, _ d: Dice) -> [Character] {
        let coloured = pool.filter { B($0).sat >= 0.3 }
        let first = d.pick(coloured.isEmpty ? pool : coloured)
        let fam = pool.filter { B($0).family == B(first).family || hueGap(B($0).hue, B(first).hue) <= 25 }
        var out: [Character] = []
        for c in stableSorted(fam, { B($0).L < B($1).L }) { addDistinct(&out, c, 14.0) }
        if out.count < 2 { for c in ["s", "f"] as [Character] where pool.contains(c) { addDistinct(&out, c) } }
        if out.count > k {
            let step = Int(ceil(Double(out.count) / Double(k)))
            return Array(out.enumerated().filter { $0.offset % step == 0 }.map { $0.element }.prefix(k))
        }
        return out
    }
    private static func ruleContrast(_ pool: [Character], _ k: Int, _ d: Dice) -> [Character] {
        let lights = pool.filter { B($0).L >= 0.62 }
        let darks = pool.filter { B($0).L < 0.45 }
        var out: [Character] = []
        if !lights.isEmpty { out.append(d.pick(lights)) }
        if !darks.isEmpty { addDistinct(&out, d.pick(darks), 35.0) }
        for c in d.shuffle(pool) {
            if out.count >= k { break }
            addDistinct(&out, c, 25.0)
        }
        return out
    }
    private static func ruleCandy(_ pool: [Character], _ k: Int, _ d: Dice) -> [Character] {
        let soft = pool.filter { B($0).L >= 0.6 && B($0).sat >= 0.3 }
        if soft.isEmpty { return [] }
        let first = d.pick(soft)
        var out = [first]
        if pool.contains("s") && d.chance(0.6) { out.append("s") }
        let near = sortedBy(soft.filter { hueGap(B($0).hue, B(first).hue) <= 60 }, { Double(hueGap(B($0).hue, B(first).hue)) })
        for c in near {
            if out.count >= k { break }
            addDistinct(&out, c, 18.0)
        }
        return out
    }
    private static func ruleRainbow(_ pool: [Character], _ k: Int, _ d: Dice) -> [Character] {
        let coloured = sortedBy(pool.filter { B($0).sat >= 0.45 }, { Double(B($0).hue) })
        if coloured.isEmpty { return [] }
        let n = max(3, k)
        let off = d.int(0, coloured.count - 1)
        var out: [Character] = []
        var i = 0
        while i < coloured.count && out.count < n {
            addDistinct(&out, coloured[(off + jsRound(Double(i) * Double(coloured.count) / Double(n))) % coloured.count], 20.0)
            i += 1
        }
        return out
    }
    private static func rule(_ name: String, _ pool: [Character], _ k: Int, _ d: Dice) -> [Character] {
        switch name {
        case "analogous": return ruleAnalogous(pool, k, d)
        case "complement": return ruleComplement(pool, k, d)
        case "triad": return ruleTriad(pool, k, d)
        case "mono": return ruleMono(pool, k, d)
        case "contrast": return ruleContrast(pool, k, d)
        case "candy": return ruleCandy(pool, k, d)
        default: return ruleRainbow(pool, k, d)
        }
    }

    private static func pickPalette(_ r: WyrmShedRecipe, _ mood: String, _ d: Dice) -> ([Character], String) {
        let m = moods[mood]!
        if !r.colours.isEmpty {
            var own: [Character] = []
            for c in d.shuffle(r.colours) { addDistinct(&own, c, sameLook) }
            let k = min(own.count, max(2, d.int(m.lo, m.hi)))
            return (Array(own.prefix(max(2, k))), "yours")
        }
        if let theme = themes[r.theme] {
            var out: [Character] = []
            let k = d.int(max(2, m.lo), max(3, m.hi))
            for c in d.shuffle(Array(theme.chars)) {
                if out.count >= k { break }
                addDistinct(&out, c, 16.0)
            }
            return (out, "theme")
        }
        let pool = poolFor(r, mood)
        let k = d.int(m.lo, m.hi)
        if mood == "danger" {
            let darks = pool.filter { B($0).L < 0.45 }
            var base: [Character] = []
            for c in d.shuffle(darks.isEmpty ? pool : darks) {
                if base.count >= k - 1 { break }
                addDistinct(&base, c, 16.0)
            }
            let glows = glow.filter { c in base.allSatisfy { look($0, c) >= 45 } }
            return (base + [glows.isEmpty ? "s" : d.pick(glows)], "dark + glow")
        }
        let weights: WyrmShedOrdered<Int>
        switch mood {
        case "cute": weights = WyrmShedOrdered(pairs: [("candy", 4), ("analogous", 3), ("mono", 2), ("rainbow", 1)])
        case "random": weights = WyrmShedOrdered(pairs: [("analogous", 2), ("complement", 2), ("triad", 2), ("mono", 1), ("contrast", 1), ("rainbow", 1)])
        case "pattern": weights = WyrmShedOrdered(pairs: [("contrast", 3), ("complement", 3), ("triad", 1)])
        default: weights = WyrmShedOrdered(pairs: [("triad", 2), ("complement", 2), ("rainbow", 1), ("contrast", 1)])
        }
        let ruleName = d.weighted(weights)
        var colours = rule(ruleName, pool, k, d)
        if mood == "cute" && ruleName != "candy" && colours.count < 4 && d.chance(0.3) { addDistinct(&colours, "s", 20.0) }
        if mood == "unique" && d.chance(0.5) {
            let star = d.pick(["d", "e"] as [Character])
            if colours.allSatisfy({ look($0, star) >= sameLook }) { colours.append(star) }
        }
        if colours.count < 2 { colours = ruleContrast(pool, 2, d) }
        return (colours, ruleName)
    }

    // ------------------------------------------------------------ patterns

    private struct Run { var ch: Character; var n: Int }
    private static func run(_ ch: Character, _ n: Int) -> Run { Run(ch: ch, n: max(1, n)) }
    private static func byL(_ cs: [Character]) -> [Character] {
        stableSorted(cs) { a, b in B(a).L != B(b).L ? B(a).L < B(b).L : B(a).id < B(b).id }
    }
    private static func byHue(_ cs: [Character]) -> [Character] {
        stableSorted(cs) { a, b in B(a).hue != B(b).hue ? B(a).hue < B(b).hue : B(a).L < B(b).L }
    }

    private static func build(_ style: String, _ P: [Character], _ u: Int, _ d: Dice) -> [Run] {
        switch style {
        case "stripes":
            return P.map { run($0, u) }
        case "thickThin":
            let s = d.chance(0.6) ? byL(P) : Array(byL(P).reversed())
            var out: [Run] = []
            for c in s.dropFirst() {
                out.append(run(s[0], u * d.int(2, 3)))
                out.append(run(c, max(accent, jsRound(Double(u) / 2.0))))
            }
            return out
        case "ramp":
            let s = d.chance(0.5) ? byL(P) : byHue(P)
            let seq = s + (s.count > 2 ? Array(s[1..<(s.count - 1)].reversed()) : [])
            let w = max(3, jsRound(Double(u) * 0.8))
            return seq.map { run($0, w) }
        case "rainbow":
            return byHue(P).map { run($0, u) }
        case "pulse":
            let s = d.chance(0.5) ? byL(P) : Array(byL(P).reversed())
            var out: [Run] = []
            for c in s.dropFirst() {
                out.append(run(s[0], u * d.int(2, 4)))
                out.append(run(c, accent))
            }
            return out
        case "band":
            let s = byL(P)
            let a = d.chance(0.5) ? s[0] : s[s.count - 1]
            let rest = s.filter { $0 != a }
            let edge = rest.last ?? a
            let mid = rest.count > 1 ? rest[0] : edge
            let first = run(a, u * d.int(3, 5))
            return [first, run(edge, accent), run(mid, u), run(edge, accent)]
        case "duo":
            let w = max(3, u - 1)
            let s = d.shuffle(P)
            return [run(s[0], w), run(s[1], w)]
        case "fib":
            let seq = [2, 3, 5, 8, 13]
            let s = d.chance(0.5) ? byL(P) : byHue(P)
            return seq.indices.map { run(s[$0 % s.count], seq[$0]) }
        case "weave":
            let s = d.shuffle(P)
            let a = s[0], b = s[1 % s.count], c = s[2 % s.count]
            return [run(a, u), run(b, accent), run(c, u), run(b, accent)]
        case "chaos":
            var out: [Run] = []
            var prev: Character? = nil
            let n = d.int(5, 9)
            for _ in 0..<n {
                var c = d.pick(P)
                var guardCount = 0
                while let p = prev, look(c, p) < sameLook {
                    let g = guardCount
                    guardCount += 1
                    if !(g < 10) { break }
                    c = d.pick(P)
                }
                out.append(run(c, d.int(accent, u + 2)))
                prev = c
            }
            return out
        default: // starry
            let plain = P.filter { !B($0).stars }
            let base: [Character] = plain.isEmpty ? ["4"] : plain
            let star = P.first(where: { B($0).stars }) ?? d.pick(["d", "e"] as [Character])
            var out: [Run] = []
            for c in base {
                out.append(run(c, u * 2))
                out.append(run(star, accent + 1))
            }
            return out
        }
    }

    private static func toCode(_ runs: [Run]) -> String {
        var s = ""
        for r in runs { s.append(String(repeating: r.ch, count: r.n)) }
        return s
    }
    private static func toRuns(_ code: String) -> [Run] {
        var out: [Run] = []
        for c in code {
            if let last = out.last, last.ch == c { out[out.count - 1].n += 1 } else { out.append(Run(ch: c, n: 1)) }
        }
        return out
    }
    /// Runs of the code as the arena counts them (a run longer than 255 splits).
    static func arenaRuns(_ code: String) -> Int { toRuns(code).reduce(0) { $0 + ($1.n + 254) / 255 } }

    private static func fixNeighbours(_ start: [Run], _ P: [Character], _ d: Dice) -> [Run] {
        var runs = start
        for _ in 0..<4 {
            var changed = false
            var i = 0
            while i < runs.count && runs.count > 1 {
                let prev = runs[(i - 1 + runs.count) % runs.count].ch
                let next = runs[(i + 1) % runs.count].ch
                let c = runs[i].ch
                func clash(_ x: Character) -> Bool { x != c && look(x, c) < sameLook }
                if clash(prev) || clash(next) {
                    let options = P.filter { look($0, prev) >= sameLook && look($0, next) >= sameLook }
                    runs[i].ch = options.isEmpty ? prev : d.pick(options)
                    changed = true
                }
                i += 1
            }
            runs = toRuns(toCode(runs))
            if !changed { break }
        }
        return runs
    }

    private static func mutate(_ start: [Run], _ P: [Character], _ wild: Double, _ d: Dice) -> [Run] {
        var runs = start
        let n = jsRound(wild * Double(runs.count) * 0.6)
        for _ in 0..<max(0, n) {
            let i = d.int(0, runs.count - 1)
            switch d.int(0, 2) {
            case 0: runs[i].ch = d.pick(P)
            case 1:
                let sign = d.chance(0.5) ? 1 : -1
                runs[i].n = max(accent, runs[i].n + sign * d.int(1, 2))
            default:
                let j = d.int(0, runs.count - 1)
                runs.swapAt(i, j)
            }
        }
        return runs
    }

    /// Keep the code inside the arena: <= 256 beads, <= 146 runs.
    private static func fitArena(_ start: [Run]) -> [Run] {
        var runs = start
        let total = runs.reduce(0) { $0 + $1.n }
        if total > maxBeads {
            let k = Double(maxBeads) / Double(total)
            runs = runs.map { Run(ch: $0.ch, n: max(1, Int(floor(Double($0.n) * k)))) }
        }
        while runs.count > maxRuns {
            var i = 0
            for j in 1..<runs.count where runs[j].n < runs[i].n { i = j }
            runs[i > 0 ? i - 1 : 1].n += runs[i].n
            runs.remove(at: i)
            runs = toRuns(toCode(runs))
        }
        return runs
    }

    // ------------------------------------------------------------ judging

    /// The code as one canonical loop: smallest rotation of its smallest block.
    static func canonical(_ code: String) -> String {
        let b = Array(code.utf8)
        return String(decoding: canonicalBytes(b), as: UTF8.self)
    }
    private static func canonicalBytes(_ code: [UInt8]) -> [UInt8] {
        let n = code.count
        var p = 1
        while p <= n / 2 {
            if n % p == 0 {
                var whole = true
                for i in p..<n where code[i] != code[i % p] { whole = false; break }
                if whole { return canonicalBytes(Array(code[0..<p])) }
            }
            p += 1
        }
        var best = code
        if n > 1 {
            for i in 1..<n {
                let r = Array(code[i...] + code[..<i])
                if r.lexicographicallyPrecedes(best) { best = r }
            }
        }
        return best
    }

    private static func distinctLooks<S: Sequence>(_ cs: S) -> Int where S.Element == Character {
        var out: [Character] = []
        for c in cs { addDistinct(&out, c, sameLook) }
        return out.count
    }

    private static func score(_ code: String, _ mood: String, _ style: String, _ allowEarthy: Bool) -> Double {
        let runs = toRuns(code)
        let chars = distinctOrdered(code)
        let all = Array(code)
        var edgeScore = 0.0
        var edges = 0
        for i in runs.indices {
            let a = runs[i].ch, b = runs[(i + 1) % runs.count].ch
            if a == b { continue }
            let dE = look(a, b)
            edgeScore += style == "ramp" ? max(0.0, 1 - abs(dE - 24) / 30) : min(1.0, dE / 45)
            edges += 1
        }
        edgeScore = edges > 0 ? edgeScore / Double(edges) : 0.0
        let widths = 1 - Double(runs.filter { $0.n < accent }.count) / Double(runs.count)
        let families = Set(chars.map { B($0).family }).count
        let calm = (style == "rainbow" || style == "chaos") ? 1.0 : (families <= 3 ? 1.0 : 0.7)
        let earthyCount = chars.filter { earthy.contains($0) }.count
        let clean = (allowEarthy || earthyCount == 0) ? 1.0 : 0.6
        let ls = chars.map { B($0).L }
        let depth = min(1.0, (ls.max()! - ls.min()!) / 0.3)
        let share = Double(chars.map { c in all.filter { $0 == c }.count }.max()!) / Double(all.count)
        let balance = ["pulse", "thickThin", "band", "starry"].contains(style) ? 1.0 : (share <= 0.66 ? 1.0 : 1 - (share - 0.66) * 2.5)
        let meanL = all.reduce(0.0) { $0 + B($1).L } / Double(all.count)
        var moodFit = 1.0
        if mood == "cute" { moodFit = min(1.0, max(0.0, (meanL - 0.5) / 0.2)) }
        if mood == "danger" { moodFit = min(1.0, Double(all.filter { B($0).L < 0.45 }.count) / Double(all.count) / 0.55) }
        let visible = all.count <= 128 ? 1.0 : 0.7
        return 0.3 * edgeScore + 0.12 * widths + 0.1 * calm + 0.12 * clean + 0.1 * depth + 0.1 * balance + 0.11 * moodFit + 0.05 * visible
    }

    private static func similar(_ a: WyrmShedSkin, _ b: WyrmShedSkin) -> Double {
        if a.key == b.key { return 1.0 }
        let sa = Set(a.code), sb = Set(b.code)
        let inter = sa.filter { sb.contains($0) }.count
        let jac = Double(inter) / Double(sa.count + sb.count - inter)
        return 0.6 * jac + 0.3 * (a.style == b.style ? 1 : 0) + 0.1 * (abs(a.code.count - b.code.count) <= 3 ? 1 : 0)
    }

    // ------------------------------------------------------------ one skin

    /// Build one skin from one seed, or nil when it fails the checks.
    static func makeSkin(_ r: WyrmShedRecipe, _ seed: UInt32) -> WyrmShedSkin? {
        let d = Dice(seed)
        let mood = r.mood
        let (P, ruleName) = pickPalette(r, mood, d)
        if distinctLooks(P) < 2 { return nil }
        var style = (r.style != "auto" && styles.contains(r.style)) ? r.style : d.weighted(moodStyles[mood]!)
        if style == "rainbow" && P.count < 3 { style = "stripes" }
        let size = sizes[r.size] ?? sizes["medium"]!
        let u = d.int(size[0], size[1])
        var runs = build(style, P, u, d)
        let symChance = ["cute": 0.5, "pattern": 0.35][mood] ?? 0.15
        let symOn = r.symmetry == "on" || (r.symmetry == "auto" && d.chance(symChance))
        if symOn && runs.count > 2 && style != "ramp" && style != "duo" {
            runs = runs + Array(runs[1..<(runs.count - 1)].reversed())
        }
        runs = mutate(runs, P, r.wildness, d)
        runs = toRuns(toCode(runs))
        runs = fixNeighbours(runs, P, d)
        runs = fitArena(runs)
        let code = toCode(runs)
        let chars = Array(code)
        if chars.isEmpty || chars.count > maxBeads || arenaRuns(code) > maxRuns { return nil }
        if chars.contains(where: { !WyrmShedBeads.isOfficial($0) }) { return nil }
        if distinctLooks(distinctOrdered(chars)) < 2 { return nil }
        for i in chars.indices {
            let a = chars[i], b = chars[(i + 1) % chars.count]
            if a != b && look(a, b) < sameLook { return nil }
        }
        let allowEarthy = mood == "danger" || !r.theme.isEmpty || !r.colours.isEmpty || r.tone == "dark"
        return WyrmShedSkin(code: code, key: canonical(code), runs: arenaRuns(code), mood: mood, style: style, rule: ruleName,
                            seed: seed, colours: distinctOrdered(chars), score: score(code, mood, style, allowEarthy))
    }

    // ------------------------------------------------------------ the batch

    /// `r.count` skins, best first; `history` = canonical codes already shown (never repeated).
    static func generate(_ r: WyrmShedRecipe, history: Set<String>) -> (skins: [WyrmShedSkin], tried: Int) {
        let want = min(max(r.count, 1), 48)
        var pool: [WyrmShedSkin] = []
        var seen = Set<String>()
        var tried = 0
        var n = 0
        let base = UInt32(bitPattern: r.seed)
        while n < want * 80 && pool.count < want * 4 {
            tried += 1
            let s = makeSkin(r, mixSeed(base, n))
            n += 1
            guard let s, !seen.contains(s.key), !history.contains(s.key) else { continue }
            seen.insert(s.key)
            pool.append(s)
        }
        let sorted = stableSorted(pool) { a, b in a.score != b.score ? a.score > b.score : a.seed < b.seed }
        var out: [WyrmShedSkin] = []
        for s in sorted {
            if out.count >= want { break }
            if out.contains(where: { similar($0, s) > 0.8 }) { continue }
            out.append(s)
        }
        for s in sorted {
            if out.count >= want { break }
            if !out.contains(where: { $0.key == s.key }) { out.append(s) }
        }
        return (out, tried)
    }
}
